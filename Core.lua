-- TauntMaster Forever
-- A rebuild of the classic TauntMaster addon for World of Warcraft: Forever (interface 16001).
-- One bar per party/raid member, colored by aggro. Click a bar to fire your bound taunt
-- at that member's target.

local ADDON, ns = ...
local TM = {}
ns.TM = TM
_G.TauntMasterForever = TM

local PREFIX = "|cffff6600TauntMaster|r: "
local function Print(msg) print(PREFIX .. msg) end
TM.Print = Print

-- Forever hands some values to addons as "secret". Comparing or doing math on them errors,
-- but they can still be passed straight into widgets (SetText, SetValue).
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

---------------------------------------------------------------------------
-- Binding definitions
---------------------------------------------------------------------------
TM.MODS = { "", "shift-", "ctrl-", "alt-" }
TM.MOD_LABELS = { [""] = "", ["shift-"] = "Shift-", ["ctrl-"] = "Ctrl-", ["alt-"] = "Alt-" }
TM.BUTTONS = { { id = 1, label = "Left" }, { id = 2, label = "Right" }, { id = 3, label = "Middle" } }
TM.KINDS = { "none", "enemy", "friend", "self", "macro", "assist", "target" }
TM.KIND_LABELS = {
    none   = "Nothing",
    enemy  = "Spell on their target",
    friend = "Spell on them",
    self   = "Spell (no target)",
    macro  = "Macro",
    assist = "Assist them",
    target = "Target them",
}

local function B(kind, text) return { kind = kind, text = text or "" } end

-- Forever tank kits (verify in-game with /tm check):
--   Warrior: Taunt, Mocking Blow, Challenging Shout
--   Druid:   Growl, Challenging Roar (Bear Form)
--   Paladin: Judgement taunts while Seal of Fury is active
TM.CLASS_DEFAULTS = {
    WARRIOR = {
        ["1"] = B("enemy", "Taunt"),
        ["2"] = B("enemy", "Mocking Blow"),
        ["shift-1"] = B("self", "Challenging Shout"),
    },
    DRUID = {
        ["1"] = B("enemy", "Growl"),
        ["2"] = B("self", "Challenging Roar"),
    },
    PALADIN = {
        ["1"] = B("enemy", "Judgement"),
        ["shift-1"] = B("friend", "Blessing of Protection"),
    },
}
-- Every class gets these unless overridden.
TM.COMMON_DEFAULTS = {
    ["ctrl-1"] = B("assist"),
    ["3"] = B("target"),
}

-- Every taunt-type ability per class, shown in the Left/Right Click Spell pickers.
-- kind: enemy = cast on the member's target, self = no target, friend = cast on the member.
TM.CLASS_SPELLS = {
    WARRIOR = {
        { name = "Taunt", kind = "enemy" },
        { name = "Mocking Blow", kind = "enemy" },
        { name = "Challenging Shout", kind = "self", note = "AoE" },
    },
    DRUID = {
        { name = "Growl", kind = "enemy", note = "Bear Form" },
        { name = "Challenging Roar", kind = "self", note = "Bear Form, AoE" },
    },
    PALADIN = {
        { name = "Judgement", kind = "enemy", note = "needs Seal of Fury" },
        { name = "Blessing of Protection", kind = "friend", utility = true },
    },
}

function TM:GetClassSpells()
    return self.CLASS_SPELLS[self:PlayerClass()] or {}
end

function TM:SetBinding(key, kind, text)
    local bindings = self:GetBindings()
    if kind == "none" then
        bindings[key] = nil
    else
        bindings[key] = { kind = kind, text = text or "" }
    end
    self:ApplyBindings()
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------
local DEFAULTS = {
    shown = true,
    locked = false,
    scale = 1.0,
    width = 120,
    height = 24,
    spacing = 2,
    unitsPerColumn = 5,
    maxColumns = 8,
    showSolo = true,
    showInRaid = true,
    showPlayer = true,
    minimap = true,
    minimapAngle = 225,
    hideManaWarning = false,
    headerFontSize = 10,
    nameFontSize = 10,
    classColors = true,
    aggroSound = false,
    flashAggro = true,
    sortByRole = false,
    healthText = false,
    rangeFade = true,
    roleIcons = true,
    showToT = false,
    tankOnly = false,
    barTexture = "blizzard",
    manaWarnPct = 20,
    cdShowOnCooldown = true,
    cdShowWhenReady = false,
    announceChannel = "none",
    announceText = "Taunted!",
    point = { "CENTER", "CENTER", -300, 0 },
    bindings = {},
}

local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = {}
                FillDefaults(dst[k], v)
            else
                dst[k] = v
            end
        end
    end
end

function TM:PlayerClass()
    local _, class = UnitClass("player")
    return class
end

function TM:DefaultBindings()
    local t = {}
    for k, v in pairs(self.COMMON_DEFAULTS) do t[k] = B(v.kind, v.text) end
    local classDefaults = self.CLASS_DEFAULTS[self:PlayerClass()]
    if classDefaults then
        for k, v in pairs(classDefaults) do t[k] = B(v.kind, v.text) end
    end
    return t
end

function TM:GetBindings()
    local class = self:PlayerClass()
    if not self.db.bindings[class] then
        self.db.bindings[class] = self:DefaultBindings()
    end
    return self.db.bindings[class]
end

---------------------------------------------------------------------------
-- Combat-safe queue: protected frames can't be changed in combat
---------------------------------------------------------------------------
function TM:RunOutOfCombat(fn)
    if InCombatLockdown() then
        self.pending = self.pending or {}
        table.insert(self.pending, fn)
        return false
    end
    fn()
    return true
end

function TM:FlushPending()
    if not self.pending then return end
    local list = self.pending
    self.pending = nil
    for _, fn in ipairs(list) do fn() end
end

---------------------------------------------------------------------------
-- Unit buttons
---------------------------------------------------------------------------
local THREAT_COLORS = {
    [0] = { 0.40, 0.40, 0.40 }, -- grey: fine
    [1] = { 1.00, 0.90, 0.00 }, -- yellow: more threat than the tank
    [2] = { 1.00, 0.50, 0.00 }, -- orange: insecurely tanking
    [3] = { 0.90, 0.05, 0.05 }, -- red: securely tanking
}

TM.buttons = {}
TM.unitToButton = {}

local function Button_OnEnter(self)
    GameTooltip_SetDefaultAnchor(GameTooltip, self)
    GameTooltip:SetUnit(self.unit)
    GameTooltip:Show()
end

local function Button_OnLeave()
    GameTooltip:Hide()
end

TM.TEXTURES = {
    { key = "blizzard", label = "Blizzard", path = "Interface\\TargetingFrame\\UI-StatusBar" },
    { key = "smooth",   label = "Smooth",   path = "Interface\\TargetingFrame\\UI-TargetingFrame-BarFill" },
    { key = "raid",     label = "Raid",     path = "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
    { key = "flat",     label = "Flat",     path = "Interface\\Buttons\\WHITE8X8" },
}
TM.TEXTURE_KEYS, TM.TEXTURE_LABELS = {}, {}
for _, t in ipairs(TM.TEXTURES) do
    table.insert(TM.TEXTURE_KEYS, t.key)
    TM.TEXTURE_LABELS[t.key] = t.label
end
function TM:TexturePath()
    for _, t in ipairs(self.TEXTURES) do
        if t.key == self.db.barTexture then return t.path end
    end
    return self.TEXTURES[1].path
end

local ROLE_ATLAS = { TANK = "roleicon-tiny-tank", HEALER = "roleicon-tiny-healer", DAMAGER = "roleicon-tiny-dps" }

function TM:GetRole(unit)
    if not UnitGroupRolesAssigned then return nil end
    local r = UnitGroupRolesAssigned(unit)
    if IsSecret(r) or r == nil or r == "NONE" then return nil end
    return r
end

function TM:CreateUnitButton(parent, unit)
    local btn = CreateFrame("Button", "TauntMasterForever_" .. unit, parent, "SecureUnitButtonTemplate")
    btn.unit = unit
    btn:SetAttribute("unit", unit)
    btn:RegisterForClicks("AnyUp")

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.7)
    btn.bg = bg

    local bar = CreateFrame("StatusBar", nil, btn)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("BOTTOMRIGHT", -1, 1)
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    btn.bar = bar

    local role = bar:CreateTexture(nil, "OVERLAY")
    role:SetSize(14, 14)
    role:SetPoint("LEFT", 3, 0)
    role:Hide()
    btn.roleIcon = role

    local name = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    name:SetPoint("LEFT", 4, 0)
    name:SetPoint("RIGHT", -34, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    btn.nameText = name

    local status = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    status:SetPoint("RIGHT", -4, 0)
    btn.statusText = status

    local mana = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mana:SetPoint("LEFT", btn, "RIGHT", 4, 0)
    mana:SetTextColor(0.35, 0.65, 1)
    mana:Hide()
    btn.manaText = mana

    -- Aggro flash: a white overlay that pulses
    local flash = bar:CreateTexture(nil, "OVERLAY", nil, 7)
    flash:SetAllPoints()
    flash:SetColorTexture(1, 1, 1, 0.35)
    flash:SetBlendMode("ADD")
    flash:SetAlpha(0)
    local ag = flash:CreateAnimationGroup()
    ag:SetLooping("BOUNCE")
    local anim = ag:CreateAnimation("Alpha")
    anim:SetFromAlpha(0)
    anim:SetToAlpha(1)
    anim:SetDuration(0.35)
    btn.flash, btn.flashAnim = flash, ag

    btn:SetScript("OnEnter", Button_OnEnter)
    btn:SetScript("OnLeave", Button_OnLeave)
    btn:HookScript("OnShow", function(b) TM:UpdateButton(b) end)

    RegisterUnitWatch(btn)

    table.insert(self.buttons, btn)
    self.unitToButton[unit] = btn
    return btn
end

local function SetFlash(btn, on)
    if on then
        if not btn.flashAnim:IsPlaying() then btn.flashAnim:Play() end
    elseif btn.flashAnim:IsPlaying() then
        btn.flashAnim:Stop()
        btn.flash:SetAlpha(0)
    end
end

local lastAggroSound = 0
local function PlayAggroSound()
    local now = GetTime()
    if now - lastAggroSound < 1.5 then return end
    lastAggroSound = now
    local kit = SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959
    pcall(PlaySound, kit, "Master")
end

-- Health % text. Health can be secret; the game formats it for us when it is.
local function SetHealthText(fs, unit)
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    if not IsSecret(cur) and not IsSecret(max) and cur and max and max > 0 then
        fs:SetText(math.floor(cur / max * 100 + 0.5) .. "%")
        return
    end
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if UnitHealthPercent and scale then
        local ok, pct = pcall(UnitHealthPercent, unit, false, scale)
        if ok and (IsSecret(pct) or pct ~= nil) and pcall(fs.SetFormattedText, fs, "%.0f%%", pct) then return end
    end
    fs:SetText("")
end

-- Returns an alpha (possibly secret) for range fading.
-- Uses your Left Click taunt vs. the member's target; falls back to the member's own range.
function TM:RangeAlpha(btn)
    local unit = btn.unit
    local isMe = UnitIsUnit(unit, "player")
    if not IsSecret(isMe) and isMe then return 1 end

    local r
    local bind = self:GetBindings()["1"]
    if bind and bind.kind == "enemy" and bind.text ~= "" and C_Spell and C_Spell.IsSpellInRange then
        local target = btn.isToT and "target" or (unit .. "target")
        r = C_Spell.IsSpellInRange(bind.text, target)
    end
    if not IsSecret(r) and r == nil then
        local inRange, checked = UnitInRange(unit)
        if not IsSecret(checked) and not checked then
            r = true
        else
            r = inRange
        end
    end
    if IsSecret(r) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local ok, a = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, r, 1, 0.35)
            if ok then return a end
        end
        return 1
    end
    return (r == false) and 0.35 or 1
end

function TM:UpdateButton(btn)
    if not btn:IsVisible() then return end
    local db = self.db
    local unit = btn.unit

    btn.nameText:SetText(UnitName(unit))

    local _, class = UnitClass(unit)
    local cc = db.classColors and not IsSecret(class) and class and RAID_CLASS_COLORS[class]
    if cc then
        btn.nameText:SetTextColor(cc.r, cc.g, cc.b)
    else
        btn.nameText:SetTextColor(1, 1, 1)
    end

    -- Role icon
    local role = self:GetRole(unit)
    btn.nameText:ClearAllPoints()
    if db.roleIcons and role and ROLE_ATLAS[role] then
        btn.roleIcon:SetAtlas(ROLE_ATLAS[role])
        btn.roleIcon:Show()
        btn.nameText:SetPoint("LEFT", btn.roleIcon, "RIGHT", 2, 0)
    else
        btn.roleIcon:Hide()
        btn.nameText:SetPoint("LEFT", 4, 0)
    end
    btn.nameText:SetPoint("RIGHT", -34, 0)

    -- Health may be secret on Forever; widgets accept it, math does not.
    pcall(btn.bar.SetMinMaxValues, btn.bar, 0, UnitHealthMax(unit))
    pcall(btn.bar.SetValue, btn.bar, UnitHealth(unit))

    -- Range fade (bar only; the secure button itself is never touched in combat).
    -- The alpha may be secret, so it's never truth-tested.
    local alpha = 1
    if db.rangeFade then alpha = self:RangeAlpha(btn) end
    pcall(btn.bar.SetAlpha, btn.bar, alpha)
    pcall(btn.bg.SetAlpha, btn.bg, alpha)

    local dead = UnitIsDeadOrGhost(unit)
    local connected = UnitIsConnected(unit)
    local isDead = not IsSecret(dead) and dead
    local isOff = not IsSecret(connected) and connected == false
    if isDead or isOff then
        btn.bar:SetStatusBarColor(0.25, 0.25, 0.25)
        btn.statusText:SetText(isDead and "Dead" or "Off")
        SetFlash(btn, false)
        btn.lastThreat = 0
        return
    end

    local threat = UnitThreatSituation(unit)
    if IsSecret(threat) or threat == nil then threat = 0 end
    local c = THREAT_COLORS[threat] or THREAT_COLORS[0]
    btn.bar:SetStatusBarColor(c[1], c[2], c[3])

    -- Someone other than you (and not another tank) has pulled aggro
    local isMe = UnitIsUnit(unit, "player")
    if IsSecret(isMe) then isMe = false end
    local stolen = threat >= 2 and not isMe and role ~= "TANK" and not btn.isToT
    SetFlash(btn, db.flashAggro and stolen)
    if db.aggroSound and stolen and (btn.lastThreat or 0) < 2 then
        PlayAggroSound()
    end
    btn.lastThreat = threat

    if db.healthText then
        SetHealthText(btn.statusText, unit)
    elseif threat == 3 then
        btn.statusText:SetText("AGGRO")
    elseif threat == 2 then
        btn.statusText:SetText("Aggro")
    elseif threat == 1 then
        btn.statusText:SetText("High")
    else
        btn.statusText:SetText("")
    end
end

function TM:RefreshAll()
    for _, btn in ipairs(self.buttons) do
        self:UpdateButton(btn)
    end
    self:UpdateManaWarning()
    self:UpdateCooldowns()
end

---------------------------------------------------------------------------
-- Low mana warning: you first, then healers (or every mana user if nobody
-- has a healer role).
--
-- Forever hides current mana from addons (a "secret" value), so we can't
-- compare it to the threshold ourselves. Instead we hand the game a step
-- curve (1 below the threshold, 0 above) through UnitPowerPercent and apply
-- the result as the line's alpha. The game decides visibility; we never
-- see the number.
---------------------------------------------------------------------------
local NO_MANA_CLASSES = { WARRIOR = true, ROGUE = true }

local manaCurve, manaCurveAt
local function GetManaCurve(pct)
    if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return nil end
    if manaCurve and manaCurveAt == pct then return manaCurve end
    local ok, curve = pcall(C_CurveUtil.CreateCurve)
    if not ok or not curve then return nil end
    if Enum.LuaCurveType and Enum.LuaCurveType.Step then
        pcall(curve.SetType, curve, Enum.LuaCurveType.Step)
    end
    curve:AddPoint(0, 1)
    curve:AddPoint(pct / 100 + 0.001, 0)
    curve:AddPoint(1, 0)
    manaCurve, manaCurveAt = curve, pct
    return curve
end

local function HasMana(unit)
    local max = UnitPowerMax(unit, 0)
    if not IsSecret(max) and max ~= nil then return max > 0 end
    local _, class = UnitClass(unit)
    if IsSecret(class) or not class then return false end
    return not NO_MANA_CLASSES[class]
end

-- Returns "readable", pct   or   "secret", alpha, pctForDisplay   or nil
local function ManaState(unit)
    if not HasMana(unit) then return nil end
    local cur, max = UnitPower(unit, 0), UnitPowerMax(unit, 0)
    if not IsSecret(cur) and not IsSecret(max) and cur and max and max > 0 then
        return "readable", math.floor(cur / max * 100 + 0.5)
    end
    if not UnitPowerPercent then return nil end
    local curve = GetManaCurve(TM.db.manaWarnPct)
    if not curve then return nil end
    local ok, alpha = pcall(UnitPowerPercent, unit, 0, false, curve)
    if not ok or (not IsSecret(alpha) and alpha == nil) then return nil end
    local pct
    local scale = CurveConstants and CurveConstants.ScaleTo100
    if scale then
        local ok2, v = pcall(UnitPowerPercent, unit, 0, false, scale)
        if ok2 then pct = v end
    end
    return "secret", alpha, pct
end

local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    elseif IsInGroup() then
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end

local function IsHealer(unit)
    if not UnitGroupRolesAssigned then return false end
    local role = UnitGroupRolesAssigned(unit)
    return not IsSecret(role) and role == "HEALER"
end

local function IsDead(unit)
    local d = UnitIsDeadOrGhost(unit)
    return not IsSecret(d) and d
end

function TM:UpdateManaWarning()
    if not self.buttons then return end
    local hide = self.db.hideManaWarning
    local threshold = self.db.manaWarnPct

    local anyHealer = false
    for _, u in ipairs(GroupUnits()) do
        if IsHealer(u) then anyHealer = true break end
    end

    for _, btn in ipairs(self.buttons) do
        local fs = btn.manaText
        local unit = btn.unit
        if hide or btn.isToT or not btn:IsVisible() or IsDead(unit) then
            fs:Hide()
        else
            local isMe = UnitIsUnit(unit, "player")
            if IsSecret(isMe) then isMe = false end
            -- You always; others only if they're a healer (or everyone, if no roles are set)
            if not isMe and anyHealer and not IsHealer(unit) then
                fs:Hide()
            else
                local state, a, b = ManaState(unit)
                if state == "readable" then
                    if a <= threshold then
                        fs:SetText(("Low mana %d%%"):format(a))
                        fs:SetAlpha(1)
                        fs:Show()
                    else
                        fs:Hide()
                    end
                elseif state == "secret" and pcall(fs.SetAlpha, fs, a) then
                    local formatted = false
                    if IsSecret(b) or b ~= nil then
                        formatted = pcall(fs.SetFormattedText, fs, "Low mana %.0f%%", b)
                    end
                    if not formatted then fs:SetText("Low mana") end
                    fs:Show()
                else
                    fs:Hide()
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Taunt cooldown icons (Left and Right Click spells), in a row above the header
---------------------------------------------------------------------------
function TM:BuildCooldownIcons()
    self.cdIcons = {}
    for i, key in ipairs({ "1", "2" }) do
        local b = CreateFrame("Frame", nil, self.main)
        b:SetSize(26, 26)
        if i == 1 then
            b:SetPoint("BOTTOMLEFT", self.handle, "TOPLEFT", 0, 2)
        else
            b:SetPoint("LEFT", self.cdIcons[1], "RIGHT", 2, 0)
        end
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetAllPoints()
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
        b.cd:SetAllPoints()
        b.key = key
        b:Hide()
        self.cdIcons[i] = b
    end
end

local CD_KINDS = { enemy = true, self = true, friend = true }

function TM:UpdateCooldowns()
    if not self.cdIcons then return end
    local db = self.db
    local bindings = self:GetBindings()
    for _, b in ipairs(self.cdIcons) do
        local bind = bindings[b.key]
        local spell = bind and CD_KINDS[bind.kind] and bind.text ~= "" and bind.text
        local info = spell and C_Spell and C_Spell.GetSpellInfo(spell)
        if not info or not (db.cdShowOnCooldown or db.cdShowWhenReady) then
            b:Hide()
        else
            b.icon:SetTexture(info.iconID)
            local cd = C_Spell.GetSpellCooldown(info.spellID)
            local state
            if cd and not IsSecret(cd.startTime) and not IsSecret(cd.duration) then
                -- Ignore the global cooldown
                if cd.startTime > 0 and cd.duration > 1.5 then
                    state = "cd"
                    b.cd:SetCooldown(cd.startTime, cd.duration)
                else
                    state = "ready"
                    b.cd:Clear()
                end
            else
                -- Cooldown hidden from addons: still draw the swipe, can't tell ready vs not
                state = "unknown"
                if cd then pcall(b.cd.SetCooldown, b.cd, cd.startTime, cd.duration) end
            end
            b.icon:SetDesaturated(state == "cd")
            b:SetShown(state == "unknown"
                or (state == "cd" and db.cdShowOnCooldown)
                or (state == "ready" and db.cdShowWhenReady))
        end
    end
end

---------------------------------------------------------------------------
-- Click bindings -> secure attributes
---------------------------------------------------------------------------
local ANNOUNCE_CMDS = { SAY = "/s", YELL = "/y", PARTY = "/p", RAID = "/raid", INSTANCE = "/i", RAID_WARNING = "/rw" }
TM.ANNOUNCE_CHANNELS = { "none", "SAY", "YELL", "PARTY", "RAID", "INSTANCE", "RAID_WARNING" }
TM.ANNOUNCE_LABELS = { none = "Off", SAY = "Say", YELL = "Yell", PARTY = "Party", RAID = "Raid", INSTANCE = "Instance", RAID_WARNING = "Raid Warning" }

function TM:AnnounceLine()
    local cmd = ANNOUNCE_CMDS[self.db.announceChannel]
    local text = self.db.announceText
    if not cmd or not text or text == "" then return "" end
    return "\n" .. cmd .. " " .. text
end

function TM:BuildMacro(kind, text, unit, enemyUnit)
    enemyUnit = enemyUnit or (unit .. "target")
    if kind == "enemy" then
        return "/cast [@" .. enemyUnit .. ",harm,nodead] " .. text .. self:AnnounceLine()
    elseif kind == "friend" then
        return "/cast [@" .. unit .. ",help,nodead] " .. text
    elseif kind == "self" then
        return "/cast " .. text .. self:AnnounceLine()
    elseif kind == "macro" then
        local m = text:gsub("{unit}", unit)
        m = m:gsub("\\n", "\n")
        return m
    end
end

function TM:ApplyBindingsToButton(btn, bindings)
    for _, mod in ipairs(self.MODS) do
        for _, b in ipairs(self.BUTTONS) do
            local key = mod .. b.id
            local typeAttr = mod .. "type" .. b.id
            local macroAttr = mod .. "macrotext" .. b.id
            btn:SetAttribute(typeAttr, nil)
            btn:SetAttribute(macroAttr, nil)

            local bind = bindings[key]
            if bind and bind.kind ~= "none" then
                if bind.kind == "assist" or bind.kind == "target" then
                    btn:SetAttribute(typeAttr, bind.kind)
                elseif bind.text and bind.text ~= "" then
                    btn:SetAttribute(typeAttr, "macro")
                    btn:SetAttribute(macroAttr, self:BuildMacro(bind.kind, bind.text, btn.unit,
                        btn.isToT and "target" or nil))
                end
            end
        end
    end
end

function TM:ApplyBindings()
    self:RunOutOfCombat(function()
        local bindings = self:GetBindings()
        for _, btn in ipairs(self.buttons) do
            self:ApplyBindingsToButton(btn, bindings)
        end
    end)
end

---------------------------------------------------------------------------
-- Layout, visibility, position
---------------------------------------------------------------------------
local ROLE_RANK = { TANK = 1, HEALER = 2, DAMAGER = 3 }

local function UnitPresent(unit)
    local e = UnitExists(unit)
    if IsSecret(e) then return true end
    return e and true or false
end

function TM:SortedByRole(list)
    local sorted = {}
    for i, btn in ipairs(list) do sorted[i] = { btn = btn, i = i } end
    table.sort(sorted, function(a, b)
        local ra = UnitPresent(a.btn.unit) and (ROLE_RANK[self:GetRole(a.btn.unit) or ""] or 4) or 9
        local rb = UnitPresent(b.btn.unit) and (ROLE_RANK[self:GetRole(b.btn.unit) or ""] or 4) or 9
        if ra ~= rb then return ra < rb end
        return a.i < b.i
    end)
    local out = {}
    for i, e in ipairs(sorted) do out[i] = e.btn end
    return out
end

function TM:LayoutGroup(list, parent)
    local db = self.db
    if db.sortByRole then list = self:SortedByRole(list) end
    local w, h, s = db.width, db.height, db.spacing
    local upc, maxCols = db.unitsPerColumn, db.maxColumns
    local idx = 0
    for _, btn in ipairs(list) do
        btn:SetSize(w, h)
        btn:ClearAllPoints()
        local col = math.floor(idx / upc)
        if (btn.unit == "player" and not db.showPlayer) or col >= maxCols then
            UnregisterUnitWatch(btn)
            btn:Hide()
        else
            RegisterUnitWatch(btn)
            btn:SetPoint("TOPLEFT", parent, "TOPLEFT", col * (w + s), -(idx % upc) * (h + s))
            idx = idx + 1
        end
    end
    parent:SetSize(1, 1)
end

-- Raid bars are laid out by raid group: each group gets its own column (or row, when
-- Units Per Column is under 5). Empty groups are skipped, Max Columns caps how many
-- groups show, and Sort by role orders members within each group.
function TM:LayoutRaid()
    local db = self.db
    local w, h, s = db.width, db.height, db.spacing
    local horizontal = db.unitsPerColumn < 5

    local buckets = {}
    for i, btn in ipairs(self.raidButtons) do
        local g = 99 -- slots not in use yet go last
        if UnitPresent(btn.unit) then
            g = math.floor((i - 1) / 5) + 1
            if GetRaidRosterInfo then
                local _, _, sub = GetRaidRosterInfo(i)
                if not IsSecret(sub) and type(sub) == "number" then g = sub end
            end
        end
        buckets[g] = buckets[g] or {}
        table.insert(buckets[g], btn)
    end

    local order = {}
    for g in pairs(buckets) do order[#order + 1] = g end
    table.sort(order)

    local block = 0
    for _, g in ipairs(order) do
        local list = buckets[g]
        if db.sortByRole then list = self:SortedByRole(list) end
        for pos, btn in ipairs(list) do
            btn:SetSize(w, h)
            btn:ClearAllPoints()
            if block >= db.maxColumns then
                UnregisterUnitWatch(btn)
                btn:Hide()
            else
                RegisterUnitWatch(btn)
                local p = pos - 1
                if horizontal then
                    btn:SetPoint("TOPLEFT", self.raidFrame, "TOPLEFT", p * (w + s), -block * (h + s))
                else
                    btn:SetPoint("TOPLEFT", self.raidFrame, "TOPLEFT", block * (w + s), -p * (h + s))
                end
            end
        end
        block = block + 1
    end
    self.raidFrame:SetSize(1, 1)
end

function TM:Layout()
    self:RunOutOfCombat(function()
        self:LayoutGroup(self.partyButtons, self.partyFrame)
        self:LayoutRaid()
        self.main:SetScale(self.db.scale)
        self.handle:SetWidth(self.db.width)

        -- Target-of-target bar sits above the cooldown icon row
        local tot = self.totButton
        if tot then
            tot:SetSize(self.db.width, self.db.height)
            tot:ClearAllPoints()
            tot:SetPoint("BOTTOMLEFT", self.handle, "TOPLEFT", 0, 44)
            if self.db.showToT then
                RegisterUnitWatch(tot)
            else
                UnregisterUnitWatch(tot)
                tot:Hide()
            end
        end
    end)
end

-- Queue at most one re-layout while in combat
function TM:RequestLayout()
    if InCombatLockdown() then
        self.layoutPending = true
    else
        self:Layout()
    end
end

function TM:ApplyVisibility()
    self:RunOutOfCombat(function()
        local db = self.db
        UnregisterStateDriver(self.main, "visibility")
        UnregisterStateDriver(self.partyFrame, "visibility")
        UnregisterStateDriver(self.raidFrame, "visibility")

        -- Whole addon (header, icons, warning): hidden entirely, or only when solo
        -- Warrior Defensive Stance = stance 2, Druid Bear Form = form 1
        local TANK_COND = { WARRIOR = "stance:2", DRUID = "form:1" }
        local mainCond = "show"
        if not db.shown then
            mainCond = "hide"
        else
            local parts = {}
            if not db.showSolo then parts[#parts + 1] = "group" end
            local tank = db.tankOnly and TANK_COND[self:PlayerClass()]
            if tank then parts[#parts + 1] = tank end
            if #parts > 0 then
                mainCond = "[" .. table.concat(parts, ",") .. "] show; hide"
            end
        end
        RegisterStateDriver(self.main, "visibility", mainCond)
        RegisterStateDriver(self.partyFrame, "visibility", "[group:raid] hide; show")
        RegisterStateDriver(self.raidFrame, "visibility", db.showInRaid and "[group:raid] show; hide" or "hide")
    end)
    self:UpdateHeader()
end

-- Header stays visible when locked so its right-click menu is always reachable.
function TM:UpdateHeader()
    if not self.handle then return end
    if self.db.locked then
        self.handle.text:SetText("TauntMaster")
        self.handle.bg:SetColorTexture(0.15, 0.15, 0.15, 0.85)
    else
        self.handle.text:SetText("TauntMaster (drag)")
        self.handle.bg:SetColorTexture(0.6, 0.25, 0, 0.85)
    end
end

function TM:SetLocked(locked)
    self.db.locked = locked
    self:UpdateHeader()
    Print(locked and "locked." or "unlocked — drag the header to move.")
end

function TM:ShowHeaderMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        self:OpenConfig()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("TauntMaster")
        root:CreateCheckbox("Lock",
            function() return TM.db.locked end,
            function() TM:SetLocked(not TM.db.locked) end)
        root:CreateButton("Settings", function() TM:OpenConfig("display") end)
    end)
end

function TM:SavePosition()
    local point, _, relPoint, x, y = self.main:GetPoint()
    self.db.point = { point, relPoint, x, y }
end

function TM:RestorePosition()
    local p = self.db.point
    self.main:ClearAllPoints()
    self.main:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

-- Text sizes: header, and names/status/mana text on the member bars
function TM:ApplyFonts()
    local font, _, flags = GameFontNormalSmall:GetFont()
    if self.handle then
        self.handle.text:SetFont(font, self.db.headerFontSize, flags)
        self:RunOutOfCombat(function() self.handle:SetHeight(self.db.headerFontSize + 6) end)
    end
    local tex = self:TexturePath()
    local iconSize = math.max(10, math.min(self.db.height - 6, 18))
    for _, btn in ipairs(self.buttons) do
        btn.nameText:SetFont(font, self.db.nameFontSize, flags)
        btn.statusText:SetFont(font, self.db.nameFontSize, flags)
        btn.manaText:SetFont(font, self.db.nameFontSize, flags)
        btn.bar:SetStatusBarTexture(tex)
        btn.roleIcon:SetSize(iconSize, iconSize)
    end
end

function TM:ApplySettings()
    self:ApplyFonts()
    self:Layout()
    self:ApplyVisibility()
    self:ApplyBindings()
    self:UpdateMinimapButton()
    if InCombatLockdown() then
        Print("Changes will apply when you leave combat.")
    end
end

---------------------------------------------------------------------------
-- Main frame construction
---------------------------------------------------------------------------
function TM:BuildFrames()
    local main = CreateFrame("Frame", "TauntMasterForeverFrame", UIParent)
    main:SetSize(1, 1)
    main:SetMovable(true)
    main:SetClampedToScreen(true)
    self.main = main
    self:RestorePosition()

    -- Header: drag to move (when unlocked), right-click for menu
    local handle = CreateFrame("Frame", nil, main)
    handle:SetHeight(16)
    handle:SetPoint("BOTTOMLEFT", main, "TOPLEFT", 0, 2)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle.bg = handle:CreateTexture(nil, "BACKGROUND")
    handle.bg:SetAllPoints()
    handle.text = handle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    handle.text:SetPoint("CENTER")
    handle:SetScript("OnDragStart", function()
        if TM.db.locked or InCombatLockdown() then return end
        main:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        main:StopMovingOrSizing()
        TM:SavePosition()
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then TM:ShowHeaderMenu(self) end
    end)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("TauntMaster")
        if not TM.db.locked then GameTooltip:AddLine("Drag to move", 1, 1, 1) end
        GameTooltip:AddLine("Right-click for options", 1, 1, 1)
        GameTooltip:Show()
    end)
    handle:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.handle = handle

    local partyFrame = CreateFrame("Frame", "TauntMasterForeverParty", main, "SecureFrameTemplate")
    partyFrame:SetPoint("TOPLEFT", main, "TOPLEFT")
    self.partyFrame = partyFrame

    local raidFrame = CreateFrame("Frame", "TauntMasterForeverRaid", main, "SecureFrameTemplate")
    raidFrame:SetPoint("TOPLEFT", main, "TOPLEFT")
    self.raidFrame = raidFrame

    self.partyButtons = {}
    table.insert(self.partyButtons, self:CreateUnitButton(partyFrame, "player"))
    for i = 1, 4 do
        table.insert(self.partyButtons, self:CreateUnitButton(partyFrame, "party" .. i))
    end

    self.raidButtons = {}
    for i = 1, 40 do
        table.insert(self.raidButtons, self:CreateUnitButton(raidFrame, "raid" .. i))
    end

    -- Target of target: shows who your target is hitting; clicking taunts your target
    local tot = self:CreateUnitButton(main, "targettarget")
    tot.isToT = true
    self.totButton = tot
    local totLabel = tot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totLabel:SetPoint("BOTTOMLEFT", tot, "TOPLEFT", 0, 1)
    totLabel:SetText("Target's target")
    self.totLabel = totLabel

    self:BuildMinimapButton()
    self:BuildCooldownIcons()
    self.built = true
    self:ApplySettings()

    C_Timer.NewTicker(0.25, function() TM:RefreshAll() end)
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function TM:PositionMinimapButton()
    local angle = math.rad(self.db.minimapAngle or 225)
    local radius = (Minimap:GetWidth() / 2) + 10
    self.minimapButton:ClearAllPoints()
    self.minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

function TM:BuildMinimapButton()
    local b = CreateFrame("Button", "TauntMasterForeverMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetTexture("Interface\\Icons\\Spell_Nature_Reincarnation")
    icon:SetPoint("TOPLEFT", 7, -5)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            TM:Toggle()
        else
            TM:OpenConfig()
        end
    end)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            TM.db.minimapAngle = math.deg(math.atan2(py - my, px - mx))
            TM:PositionMinimapButton()
        end)
    end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("TauntMaster Forever")
        GameTooltip:AddLine("Left-click: options", 1, 1, 1)
        GameTooltip:AddLine("Right-click: show/hide bars", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    self.minimapButton = b
    self:PositionMinimapButton()
end

function TM:UpdateMinimapButton()
    if self.minimapButton then
        self.minimapButton:SetShown(self.db.minimap)
    end
end

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
function TM:SetShown(show)
    self.db.shown = show
    self:ApplyVisibility()
    if InCombatLockdown() then
        Print("Will " .. (show and "show" or "hide") .. " when you leave combat.")
    else
        Print(show and "shown." or "hidden.")
    end
end

function TM:Toggle()
    self:SetShown(not self.db.shown)
end

local function SpellKnown(spellID)
    if IsPlayerSpell then return IsPlayerSpell(spellID) end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then return C_SpellBook.IsSpellInSpellBook(spellID) end
    return nil
end

function TM:CheckSpells()
    Print("Checking bound spells for " .. (UnitClass("player")) .. ":")
    local bindings = self:GetBindings()
    local any = false
    for _, mod in ipairs(self.MODS) do
        for _, b in ipairs(self.BUTTONS) do
            local bind = bindings[mod .. b.id]
            if bind and (bind.kind == "enemy" or bind.kind == "friend" or bind.kind == "self") and bind.text ~= "" then
                any = true
                local label = self.MOD_LABELS[mod] .. b.label
                local info = C_Spell and C_Spell.GetSpellInfo(bind.text)
                if not info then
                    print(("  %s: |cffff4040%s — not found. Check spelling or that it exists in Forever.|r"):format(label, bind.text))
                else
                    local known = SpellKnown(info.spellID)
                    if known == false then
                        print(("  %s: |cffffcc00%s (ID %d) — exists, not learned yet.|r"):format(label, bind.text, info.spellID))
                    else
                        print(("  %s: |cff40ff40%s (ID %d) — OK.|r"):format(label, bind.text, info.spellID))
                    end
                end
            end
        end
    end
    if not any then print("  No spells bound. Open /tm spells.") end
end

-- "TauntMaster Forever loaded. Growl assigned to Left Click, Challenging Roar assigned to Right Click."
-- Spells the client can't find are flagged in red, so no manual /tm check is needed.
function TM:PrintLoadMessage()
    local bindings = self:GetBindings()
    local parts = {}
    for _, mod in ipairs(self.MODS) do
        for _, b in ipairs(self.BUTTONS) do
            local bind = bindings[mod .. b.id]
            if bind and (bind.kind == "enemy" or bind.kind == "friend" or bind.kind == "self") and bind.text ~= "" then
                local name = "|cffffd100" .. bind.text .. "|r"
                if C_Spell and not C_Spell.GetSpellInfo(bind.text) then
                    name = "|cffff4040" .. bind.text .. " (not found)|r"
                end
                parts[#parts + 1] = name .. " assigned to " .. self.MOD_LABELS[mod] .. b.label .. " Click"
            end
        end
    end
    local msg = "|cffff6600TauntMaster Forever|r loaded."
    if #parts > 0 then
        msg = msg .. " " .. table.concat(parts, ", ") .. "."
    else
        msg = msg .. " No taunts assigned — type /tm to pick one."
    end
    print(msg)
end

local function Help()
    Print("commands:")
    print("  /tm — open options")
    print("  /tm show | hide | toggle — show or hide the bars")
    print("  /tm lock | unlock — lock or unlock the bars' position")
    print("  /tm display | advanced | spells | extras — open that tab")
    print("  /tm check — verify your bound spells exist in Forever")
    print("  /tm reset — move the bars back to the default position")
end

SLASH_TAUNTMASTERFOREVER1 = "/tm"
SLASH_TAUNTMASTERFOREVER2 = "/tauntmaster"
SlashCmdList.TAUNTMASTERFOREVER = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if not TM.built then Print("not ready yet.") return end
    if msg == "" or msg == "config" or msg == "options" then
        TM:OpenConfig()
    elseif msg == "show" then
        TM:SetShown(true)
    elseif msg == "hide" then
        TM:SetShown(false)
    elseif msg == "toggle" then
        TM:Toggle()
    elseif msg == "lock" or msg == "unlock" then
        TM:SetLocked(msg == "lock")
    elseif msg == "spells" or msg == "display" or msg == "advanced" or msg == "extras" then
        TM:OpenConfig(msg)
    elseif msg == "check" then
        TM:CheckSpells()
    elseif msg == "debug" then
        local function show(label, v)
            if IsSecret(v) then
                print("  " .. label .. ": |cffff4040SECRET (hidden from addons)|r")
            else
                print("  " .. label .. ": " .. tostring(v))
            end
        end
        Print("debug (v" .. (C_AddOns and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?") .. ")")
        show("Mana", UnitPower("player", 0))
        show("Max mana", UnitPowerMax("player", 0))
        show("Power type", UnitPowerType("player"))
        show("Warning at %", TM.db.manaWarnPct)
        show("Warning hidden", TM.db.hideManaWarning)
        show("UnitPowerPercent available", UnitPowerPercent ~= nil)
        show("C_CurveUtil available", C_CurveUtil ~= nil and C_CurveUtil.CreateCurve ~= nil)
    elseif msg == "reset" then
        TM.db.point = { "CENTER", "CENTER", -300, 0 }
        TM:RunOutOfCombat(function() TM:RestorePosition() end)
        Print("position reset.")
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("GROUP_ROSTER_UPDATE")
events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
events:RegisterEvent("UNIT_HEALTH")
events:RegisterEvent("UNIT_MAXHEALTH")
events:RegisterEvent("SPELL_UPDATE_COOLDOWN")
events:RegisterEvent("PLAYER_ROLES_ASSIGNED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        TauntMasterForeverDB = TauntMasterForeverDB or {}
        FillDefaults(TauntMasterForeverDB, DEFAULTS)
        TM.db = TauntMasterForeverDB
        -- Settings migrations for installs from earlier versions
        if (TM.db.schema or 0) < 2 then
            TM.db.aggroSound = false -- aggro sound is now off by default
            TM.db.schema = 2
        end
        -- Older versions allowed both cooldown modes at once
        if TM.db.cdShowOnCooldown and TM.db.cdShowWhenReady then
            TM.db.cdShowWhenReady = false
        end
    elseif event == "PLAYER_LOGIN" then
        TM:RunOutOfCombat(function() TM:BuildFrames() end)
        TM:PrintLoadMessage()
    elseif event == "PLAYER_REGEN_ENABLED" then
        TM:FlushPending()
        if TM.layoutPending then
            TM.layoutPending = nil
            if TM.built then TM:Layout() end
        end
    elseif not TM.built then
        return
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        TM:UpdateCooldowns()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        if TM.db.sortByRole or IsInRaid() then TM:RequestLayout() end
        TM:RefreshAll()
    elseif arg1 and TM.unitToButton[arg1] then
        TM:UpdateButton(TM.unitToButton[arg1])
    end
end)
