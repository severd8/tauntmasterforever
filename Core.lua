-- TauntMaster Forever
-- A rebuild of the classic TauntMaster addon for World of Warcraft: Forever (interface 16001).
-- One bar per party/raid member, colored by aggro. Click a bar to fire your bound taunt
-- at that member's target.

local ADDON, ns = ...
local TM = {}
ns.TM = TM
_G.TauntMasterForever = TM

-- Chat lines start with the logo and name, as in every addon with this look (Theme.lua)
local function Print(msg) print(ns.Theme.CHAT_PREFIX .. ": " .. msg) end
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

-- Every bindable click, in menu order: key "shift-1", label "Shift-Left", and the
-- secure attributes that hold its action
TM.CLICKS = {}
for _, mod in ipairs(TM.MODS) do
    for _, b in ipairs(TM.BUTTONS) do
        TM.CLICKS[#TM.CLICKS + 1] = { key = mod .. b.id, label = TM.MOD_LABELS[mod] .. b.label,
            typeAttr = mod .. "type" .. b.id, macroAttr = mod .. "macrotext" .. b.id }
    end
end
TM.SPELL_KINDS = { enemy = true, friend = true, self = true }      -- kinds that cast a named spell
TM.NO_TEXT_KINDS = { none = true, assist = true, target = true }   -- kinds that need no spell or macro text

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
        { name = "Taunt", id = 355, kind = "enemy" },
        { name = "Mocking Blow", id = 694, kind = "enemy" },
        { name = "Challenging Shout", id = 1161, kind = "self", note = "AoE" },
    },
    DRUID = {
        { name = "Growl", id = 6795, kind = "enemy", note = "Bear Form" },
        { name = "Challenging Roar", id = 5209, kind = "self", note = "Bear Form, AoE" },
    },
    PALADIN = {
        { name = "Judgement", id = 20271, kind = "enemy", note = "needs Seal of Fury" },
        { name = "Blessing of Protection", id = 1022, kind = "friend", utility = true },
    },
}

function TM:GetClassSpells()
    return self.CLASS_SPELLS[self:PlayerClass()] or {}
end

-- Spell info by name. The game only finds spells by name once they're in your
-- spellbook, so the class taunts are also looked up by ID (not learned yet).
function TM:GetSpellInfo(name)
    if type(name) ~= "string" or name == "" or not (C_Spell and C_Spell.GetSpellInfo) then return nil end
    local info = C_Spell.GetSpellInfo(name)
    if info then return info end
    local lower = name:lower()
    for _, spells in pairs(self.CLASS_SPELLS) do
        for _, s in ipairs(spells) do
            if s.id and s.name:lower() == lower then
                info = C_Spell.GetSpellInfo(s.id)
                if info and type(info.name) == "string" and info.name:lower() == lower then return info end
            end
        end
    end
    return nil
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
    showSplash = true,
    showInRaid = true,
    showPlayer = true,
    minimap = true,
    minimapAngle = 225,
    hideManaWarning = false,
    headerFontSize = 10,
    nameFontSize = 10,
    classColors = true,
    aggroSound = false,
    aggroSoundKey = "raidwarning",
    aggroSoundLevel = 2,       -- 1 = yellow, 2 = orange/red, 3 = red only
    aggroSoundChannel = "Master",
    flashAggro = true,
    sortByRole = false,
    healthText = false,
    keyHints = true,
    rangeFade = true,
    roleIcons = true,
    showToT = false,
    tauntFallback = false,   -- no enemy targeted: taunt what their target is fighting
    nameplateMarks = true,   -- mark mobs attacking a non-tank on their nameplates
    tankOnly = false,
    barTexture = "blizzard",
    manaWarnPct = 20,
    cdShowOnCooldown = true,
    cdShowWhenReady = false,
    cdIconSize = 26,
    announceChannel = "none",
    announceText = "{target} has been taunted off of {player}!",
    point = { "CENTER", "CENTER", -300, 0 },
    bindings = {},
}

-- Fills in missing settings. A saved value of the wrong type (a damaged or
-- hand-edited settings file) is replaced by its default, so nothing later has to
-- cope with a number where a table should be.
local function FillDefaults(dst, src)
    for k, v in pairs(src) do
        if type(dst[k]) ~= type(v) then
            dst[k] = type(v) == "table" and {} or v
        end
        if type(v) == "table" then FillDefaults(dst[k], v) end
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
-- Combat-safe queue: protected frames can't be changed in combat. Work queued
-- under the same key replaces the earlier request, so a setting changed ten
-- times during a fight is applied once when it ends.
---------------------------------------------------------------------------
function TM:RunOutOfCombat(key, fn)
    if not InCombatLockdown() then
        fn()
        return true
    end
    self.pending = self.pending or { keys = {}, fns = {} }
    local p = self.pending
    if not p.fns[key] then p.keys[#p.keys + 1] = key end
    p.fns[key] = fn
    return false
end

function TM:FlushPending()
    local p = self.pending
    if not p then return end
    self.pending = nil
    for _, key in ipairs(p.keys) do p.fns[key]() end
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
    mana:SetPoint("LEFT", btn, "RIGHT", 20, 0)
    mana:SetTextColor(0.35, 0.65, 1)
    mana:Hide()
    btn.manaText = mana

    -- "No enemy targeted" marker: this player has nothing hostile targeted, so a click
    -- has nothing to taunt. Its alpha comes from the game (may be hidden from addons).
    local noTarget = btn:CreateTexture(nil, "OVERLAY")
    noTarget:SetSize(14, 14)
    noTarget:SetPoint("LEFT", btn, "RIGHT", 3, 0)
    noTarget:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    noTarget:SetAlpha(0)
    btn.noTarget = noTarget

    -- Keybinding hint, just left of the bar (controller / keyboard users)
    local hint = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("RIGHT", btn, "LEFT", -4, 0)
    hint:SetJustifyH("RIGHT")
    hint:SetTextColor(1, 0.82, 0)
    hint:Hide()
    btn.keyHint = hint

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
    btn:HookScript("PreClick", function(self, mouseButton) TM:OnBarClick(mouseButton, self) end)

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

-- Aggro sound choices. SOUNDKIT names are looked up first; the numbers are fallbacks.
TM.AGGRO_SOUNDS = {
    -- Each sound lists fallbacks (sound kit names, then IDs); the first one the
    -- game can play is used. Not every modern sound exists in Forever.
    { key = "raidwarning", label = "Raid Warning", try = { "RAID_WARNING", 8959 } },
    { key = "readycheck",  label = "Ready Check",  try = { "READY_CHECK", 8960 } },
    { key = "alarm",       label = "Alarm Clock",  try = { "ALARM_CLOCK_WARNING_3", 12889 } },
    { key = "bosswarning", label = "Boss Warning",
      try = { "RAID_BOSS_EMOTE_WARNING", 12197, "UI_RAID_BOSS_WHISPER_WARNING", 37666, "RAID_WARNING", 8959 } },
}
TM.AGGRO_SOUND_KEYS, TM.AGGRO_SOUND_LABELS = {}, {}
for _, s in ipairs(TM.AGGRO_SOUNDS) do
    table.insert(TM.AGGRO_SOUND_KEYS, s.key)
    TM.AGGRO_SOUND_LABELS[s.key] = s.label
end
TM.AGGRO_LEVEL_KEYS = { 1, 2, 3 }
TM.AGGRO_LEVEL_LABELS = { "Close to pulling (yellow)", "Has aggro (orange/red)", "Firmly has aggro (red)" }
TM.SOUND_CHANNEL_KEYS = { "Master", "SFX", "Dialog" }
TM.SOUND_CHANNEL_LABELS = { Master = "Master", SFX = "Sound Effects", Dialog = "Dialog" }

local lastAggroSound = 0
local function PlayAggroSound(force)
    local now = GetTime()
    if not force and now - lastAggroSound < 1.5 then return end
    lastAggroSound = now
    local choice = TM.AGGRO_SOUNDS[1]
    for _, s in ipairs(TM.AGGRO_SOUNDS) do
        if s.key == TM.db.aggroSoundKey then choice = s break end
    end
    local channel = TM.db.aggroSoundChannel or "Master"
    for _, k in ipairs(choice.try) do
        local id = k
        if type(k) == "string" then id = SOUNDKIT and SOUNDKIT[k] end
        if id then
            local ok, willPlay = pcall(PlaySound, id, channel)
            if ok and willPlay then return end
        end
    end
end

-- "Test" button and picking a new sound in the options
function TM:TestAggroSound() PlayAggroSound(true) end

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

-- Can a click on this bar land? Returns two alphas, either of which may be hidden
-- from addons (secret), so they're only ever handed to widgets:
--   barAlpha    1 = your Left Click taunt can reach the player's target, DIM = it can't
--               (out of range, or they have no enemy targeted)
--   markerAlpha 1 = show the "no enemy targeted" marker, 0 = hide it
-- If your Left Click spell isn't a targeted taunt you've learned, falls back to the
-- player's own distance from you and never shows the marker.
local DIM = 0.35

-- The result may itself be hidden, so callers pass a fallback here instead of
-- using "or" on it (testing a hidden value is an error).
local function BoolAlpha(b, whenTrue, whenFalse, fallback)
    if IsSecret(b) then
        if C_CurveUtil and C_CurveUtil.EvaluateColorValueFromBoolean then
            local ok, a = pcall(C_CurveUtil.EvaluateColorValueFromBoolean, b, whenTrue, whenFalse)
            if ok then return a end
        end
        return fallback
    end
    if b then return whenTrue end
    return whenFalse
end

-- Whether you've learned a spell: true, false, or nil when the game can't say
local function SpellKnown(spellID)
    if IsPlayerSpell then return IsPlayerSpell(spellID) end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then return C_SpellBook.IsSpellInSpellBook(spellID) end
    return nil
end
TM.SpellKnown = SpellKnown

local function IsKnownSpell(name)
    local info = TM:GetSpellInfo(name)
    if not info then return false end
    if not (IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellInSpellBook)) then return true end
    return SpellKnown(info.spellID)
end

-- The enemy a click on this bar taunts. With the backup option on, when the
-- player's target is friendly (a healer targeting someone they heal), it's
-- what that friend is targeting instead. Matches the click macro.
function TM:EnemyUnitFor(btn)
    if btn.isToT then return "target" end
    local unit = btn.unit .. "target"
    if self.db.tauntFallback then
        local hostile = UnitCanAttack("player", unit)
        if not IsSecret(hostile) and not hostile then return unit .. "target" end
    end
    return unit
end

function TM:RangeState(btn)
    local unit = btn.unit
    local isMe = UnitIsUnit(unit, "player")
    if not IsSecret(isMe) and isMe then return 1, 0 end

    local bind = self:GetBindings()["1"]
    if bind and bind.kind == "enemy" and bind.text and bind.text ~= "" and C_Spell and C_Spell.IsSpellInRange
        and IsKnownSpell(bind.text) then
        local target = self:EnemyUnitFor(btn)
        local r = C_Spell.IsSpellInRange(bind.text, target)
        if IsSecret(r) then
            local marker = 0
            if not btn.isToT then
                -- Whether their target is an enemy decides the marker
                marker = BoolAlpha(UnitCanAttack("player", target), 0, 1, 0)
            end
            return BoolAlpha(r, 1, DIM, 1), marker
        end
        if r == nil then
            -- The taunt can't be cast on their target at all: no target, friendly, or dead
            return DIM, btn.isToT and 0 or 1
        end
        return r and 1 or DIM, 0
    end

    -- Fallback: the player's own distance from you
    local inRange, checked = UnitInRange(unit)
    if not IsSecret(checked) and not checked then return 1, 0 end
    return BoolAlpha(inRange, 1, DIM, 1), 0
end

-- The health bar. Health may be secret on Forever; widgets accept it, math does not.
local function SetHealthBar(btn)
    pcall(btn.bar.SetMinMaxValues, btn.bar, 0, UnitHealthMax(btn.unit))
    pcall(btn.bar.SetValue, btn.bar, UnitHealth(btn.unit))
end

-- "Dead" or "Off" for a unit that's down, else nil
local function DownStatus(unit)
    local dead = UnitIsDeadOrGhost(unit)
    local connected = UnitIsConnected(unit)
    if not IsSecret(dead) and dead then return "Dead" end
    if not IsSecret(connected) and connected == false then return "Off" end
    return nil
end

-- A health change: only the bar and the health % move, unless the unit just
-- died, went offline or came back (then the whole bar is redrawn)
function TM:UpdateHealth(btn)
    if not btn:IsVisible() then return end
    SetHealthBar(btn)
    local down = DownStatus(btn.unit)
    if down ~= btn.down then return self:UpdateButton(btn) end
    if not down and self.db.healthText then SetHealthText(btn.statusText, btn.unit) end
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

    -- Role icon. The name is re-anchored only when the icon appears, changes or goes.
    local role = self:GetRole(unit)
    local atlas = db.roleIcons and role and ROLE_ATLAS[role] or nil
    if atlas ~= btn.roleAtlas then
        btn.roleAtlas = atlas
        btn.nameText:ClearAllPoints()
        if atlas then
            btn.roleIcon:SetAtlas(atlas)
            btn.roleIcon:Show()
            btn.nameText:SetPoint("LEFT", btn.roleIcon, "RIGHT", 2, 0)
        else
            btn.roleIcon:Hide()
            btn.nameText:SetPoint("LEFT", 4, 0)
        end
        btn.nameText:SetPoint("RIGHT", -34, 0)
    end

    SetHealthBar(btn)

    -- Range fade (bar only; the secure button itself is never touched in combat).
    -- The alpha may be secret, so it's never truth-tested.
    local alpha, marker = 1, 0
    if db.rangeFade then alpha, marker = self:RangeState(btn) end
    pcall(btn.bar.SetAlpha, btn.bar, alpha)
    pcall(btn.bg.SetAlpha, btn.bg, alpha)
    if not pcall(btn.noTarget.SetAlpha, btn.noTarget, marker) then btn.noTarget:SetAlpha(0) end

    btn.down = DownStatus(unit)
    if btn.down then
        btn.bar:SetStatusBarColor(0.25, 0.25, 0.25)
        btn.statusText:SetText(btn.down)
        btn.noTarget:SetAlpha(0)
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
    local watched = not isMe and role ~= "TANK" and not btn.isToT
    SetFlash(btn, db.flashAggro and watched and threat >= 2)
    -- Sound plays once when they cross the chosen level (yellow, orange/red or red)
    local level = db.aggroSoundLevel or 2
    if db.aggroSound and watched and threat >= level and (btn.lastThreat or 0) < level then
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
    self:UpdatePlateMarks()
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

-- The other members of your group: raid1..n in a raid, else party1..4
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

    local anyHealer = IsHealer("player")
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
        b:SetSize(self.db.cdIconSize, self.db.cdIconSize)
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

function TM:UpdateCooldowns()
    if not self.cdIcons then return end
    local db = self.db
    local bindings = self:GetBindings()
    for _, b in ipairs(self.cdIcons) do
        local bind = bindings[b.key]
        local spell = bind and self.SPELL_KINDS[bind.kind] and bind.text ~= "" and bind.text
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
            elseif cd and type(cd.isActive) == "boolean" and not IsSecret(cd.isActive) then
                -- In instances the times are hidden, but "is it on cooldown" isn't.
                -- The global cooldown counts as ready.
                local onGCD = not IsSecret(cd.isOnGCD) and cd.isOnGCD == true
                if cd.isActive and not onGCD then
                    state = "cd"
                    -- The game's own duration object draws the swipe; hidden times are the fallback
                    local drawn = false
                    if C_Spell.GetSpellCooldownDuration and b.cd.SetCooldownFromDurationObject then
                        local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, info.spellID)
                        drawn = ok and pcall(b.cd.SetCooldownFromDurationObject, b.cd, duration)
                    end
                    if not drawn then pcall(b.cd.SetCooldown, b.cd, cd.startTime, cd.duration) end
                else
                    state = "ready"
                    b.cd:Clear()
                end
            else
                -- Nothing readable: still draw the swipe, can't tell ready vs not
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
-- Nameplate marks: the TauntMaster Forever logo over any enemy that's attacking
-- someone other than you or another tank, so you can click it and taunt.
-- Only shows information; you still pick the target. Needs enemy nameplates on.
--
-- In instances the game may hide whether two units are the same (secret). Then
-- each plate gets one stacked logo per group member, and the game sets each
-- one's alpha, so the mark shows if the mob is on any of them.
---------------------------------------------------------------------------
local plates = {}   -- nameplate unit token -> true while shown

local function PlateMark(plate)
    if plate.tmForeverMark then return plate.tmForeverMark end
    local m = CreateFrame("Frame", nil, plate)
    m:SetSize(24, 24)
    m:SetPoint("BOTTOM", plate, "TOP", 0, 2)
    m:SetFrameLevel((plate:GetFrameLevel() or 0) + 20)
    m.layers = {}
    m.name = m:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    m.name:SetPoint("LEFT", m, "RIGHT", 2, 0)
    m.name:SetTextColor(1, 0.35, 0.25)
    m:Hide()
    plate.tmForeverMark = m
    return m
end

-- Layers are made in order (1, 2, 3 ...), so the list never has gaps
local function MarkLayer(m, i)
    for n = #m.layers + 1, i do
        local t = m:CreateTexture(nil, "OVERLAY")
        t:SetAllPoints()
        t:SetTexture(ns.Theme.LOGO)
        t:Hide()
        m.layers[n] = t
    end
    return m.layers[i]
end

local function HideMark(unit)
    local plate = C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit)
    if plate and plate.tmForeverMark then plate.tmForeverMark:Hide() end
end

-- Group members worth protecting: everyone but you and players marked as tanks
local function WatchedMembers()
    local list = {}
    for _, u in ipairs(GroupUnits()) do
        local me = UnitIsUnit(u, "player")
        local role = UnitGroupRolesAssigned and UnitGroupRolesAssigned(u)
        local isTank = not IsSecret(role) and role == "TANK"
        if not (not IsSecret(me) and me) and not isTank then list[#list + 1] = u end
    end
    return list
end

function TM:UpdatePlateMark(unit, members)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate then return end
    local ok, m = pcall(PlateMark, plate)   -- some plates are off limits to addons
    if not ok or not m then return end

    local hostile = UnitCanAttack("player", unit)
    if (not IsSecret(hostile) and not hostile) or #members == 0 then m:Hide() return end

    local mobTarget = unit .. "target"
    local hidden = false
    for i, u in ipairs(members) do
        local same = UnitIsUnit(mobTarget, u)
        if IsSecret(same) then
            hidden = true
            local layer = MarkLayer(m, i)
            if not pcall(layer.SetAlpha, layer, BoolAlpha(same, 1, 0, 0)) then layer:SetAlpha(0) end
            layer:Show()
        elseif same then
            -- Readable: one logo plus who it's hitting
            local first = MarkLayer(m, 1)
            for j, t in ipairs(m.layers) do t:SetShown(j == 1) end
            first:SetAlpha(1)
            m.name:SetText(UnitName(u))
            m:Show()
            return
        elseif m.layers[i] then
            m.layers[i]:Hide()   -- readable, and not on this member
        end
    end
    if hidden then
        for j = #members + 1, #m.layers do m.layers[j]:Hide() end
        m.name:SetText("")
        m:Show()
    else
        m:Hide()
    end
end

-- Every nameplate on screen, or just `only` (one that has just appeared)
function TM:UpdatePlateMarks(only)
    if not (self.db and C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
    local on = self.db.nameplateMarks and (IsInGroup() or IsInRaid())
    local members = on and WatchedMembers()
    local function update(unit)
        if not (on and pcall(self.UpdatePlateMark, self, unit, members)) then pcall(HideMark, unit) end
    end
    if only then update(only) return end
    for unit in pairs(plates) do update(unit) end
end

function TM:OnNamePlateAdded(unit)
    plates[unit] = true
    pcall(self.UpdatePlateMarks, self, unit)
end

function TM:OnNamePlateRemoved(unit)
    plates[unit] = nil
    pcall(HideMark, unit)
end

---------------------------------------------------------------------------
-- Click bindings -> secure attributes
---------------------------------------------------------------------------
TM.ANNOUNCE_CHANNELS = { "none", "SAY", "YELL", "PARTY", "RAID", "INSTANCE", "RAID_WARNING" }
TM.ANNOUNCE_LABELS = { none = "Off", SAY = "Say", YELL = "Yell", PARTY = "Party", RAID = "Raid", INSTANCE = "Instance", RAID_WARNING = "Raid Warning" }

---------------------------------------------------------------------------
-- Taunt announcements: sent only after a taunt you clicked on a bar actually
-- casts. A click records which spell it should cast; if the game reports that
-- spell succeeding within a moment, the message goes out. On cooldown, out of
-- range, wrong form or no target = no cast = no message. Taunts cast from your
-- action bars aren't announced.
---------------------------------------------------------------------------
local CHAT_TYPES = { SAY = "SAY", YELL = "YELL", PARTY = "PARTY", RAID = "RAID",
    INSTANCE = "INSTANCE_CHAT", RAID_WARNING = "RAID_WARNING" }
local BUTTON_SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }
-- Keybinding presses arrive as these made-up mouse buttons (see Bindings.xml)
local KEYBIND_SUFFIX = { TMLeft = "1", TMRight = "2" }
local ANNOUNCE_WINDOW = 1.5 -- seconds; covers the spell queue after a click
local pendingAnnounce

local function ModifierPrefix()
    if SecureButton_GetModifierPrefix then return SecureButton_GetModifierPrefix() end
    local p = ""
    if IsAltKeyDown() then p = p .. "alt-" end
    if IsControlKeyDown() then p = p .. "ctrl-" end
    if IsShiftKeyDown() then p = p .. "shift-" end
    return p
end

-- Names for the announcement, read at click time (after the taunt, the mob targets you).
-- Names the game hides from addons, or missing ones, fall back to plain words.
local function SafeName(unit)
    if not unit then return nil end
    local name = UnitName(unit)
    if IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

-- Which unit the click taunts, and which friendly player it's saving
local function ClickUnits(btn)
    if btn.isToT then return "target", "targettarget" end
    return TM:EnemyUnitFor(btn), btn.unit   -- bars and the "targeted ally" button (unit "target")
end

-- Called just before a bar's click runs its spell
function TM:OnBarClick(mouseButton, btn)
    pendingAnnounce = nil
    if not CHAT_TYPES[self.db.announceChannel] then return end
    local bind
    if KEYBIND_SUFFIX[mouseButton] then
        -- Keybindings always use the plain Left/Right Click spell, whatever modifier is held
        bind = self:GetBindings()[KEYBIND_SUFFIX[mouseButton]]
    else
        local suffix = BUTTON_SUFFIX[mouseButton]
        if not suffix then return end
        bind = self:GetBindings()[ModifierPrefix() .. suffix]
    end
    if bind and (bind.kind == "enemy" or bind.kind == "self") and bind.text ~= "" then
        local mobUnit, allyUnit = nil, nil
        if btn then mobUnit, allyUnit = ClickUnits(btn) end
        pendingAnnounce = {
            spell = bind.text:lower(),
            time = GetTime(),
            -- AoE taunts hit everything around you, not one mob
            target = (bind.kind == "self") and "Everything nearby" or SafeName(mobUnit),
            player = SafeName(allyUnit),
        }
    end
end

-- Called when one of your spells finishes casting successfully
function TM:OnSpellCastSucceeded(spellID)
    local p = pendingAnnounce
    if not p then return end
    if GetTime() - p.time > ANNOUNCE_WINDOW then
        pendingAnnounce = nil
        return
    end
    -- Make sure it's the clicked spell. If the game hides the spell from addons,
    -- trust the timing instead.
    if not IsSecret(spellID) and spellID then
        local info = C_Spell and C_Spell.GetSpellInfo(spellID)
        local name = info and info.name
        if not IsSecret(name) then
            if not name or name:lower() ~= p.spell then return end
        end
    end
    pendingAnnounce = nil
    self:SendAnnounce(p.target, p.player)
end

-- Fills in {target} and {player}; capitalizes the first letter
function TM:FormatAnnounce(text, target, player)
    local out = text:gsub("{target}", function() return target or "the mob" end)
    out = out:gsub("{player}", function() return player or "my ally" end)
    return (out:gsub("^%l", string.upper))
end

function TM:SendAnnounce(target, player)
    local chat = CHAT_TYPES[self.db.announceChannel]
    local text = self.db.announceText
    if not chat or not text or text == "" then return end
    text = self:FormatAnnounce(text, target, player)
    -- Skip channels you can't talk in right now instead of showing an error
    if chat == "PARTY" and not IsInGroup() then return end
    if (chat == "RAID" or chat == "RAID_WARNING") and not IsInRaid() then return end
    if chat == "INSTANCE_CHAT" and not IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return end
    -- Outside instances the game blocks addon Say/Yell that isn't a direct key press
    if (chat == "SAY" or chat == "YELL") and not (IsInInstance and IsInInstance()) then return end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    if send then pcall(send, text, chat) end
end

function TM:BuildMacro(kind, text, unit, enemyUnit, fallback)
    enemyUnit = enemyUnit or (unit .. "target")
    if kind == "enemy" then
        local m = "/cast [@" .. enemyUnit .. ",harm,nodead] " .. text
        if fallback then
            -- Their target isn't an enemy: try what their target is fighting
            m = m .. "; [@" .. enemyUnit .. "target,harm,nodead] " .. text
        end
        return m
    elseif kind == "friend" then
        return "/cast [@" .. unit .. ",help,nodead] " .. text
    elseif kind == "self" then
        return "/cast " .. text
    elseif kind == "macro" then
        local m = text:gsub("{unit}", unit)
        m = m:gsub("\\n", "\n")
        return m
    end
end

-- Secure attributes for one click: clears the old action, then sets the bound one
function TM:SetClickAttributes(btn, typeAttr, macroAttr, bind)
    btn:SetAttribute(typeAttr, nil)
    btn:SetAttribute(macroAttr, nil)
    if not bind or bind.kind == "none" then return end
    if bind.kind == "assist" or bind.kind == "target" then
        btn:SetAttribute(typeAttr, bind.kind)
    elseif bind.text and bind.text ~= "" then
        btn:SetAttribute(typeAttr, "macro")
        btn:SetAttribute(macroAttr, self:BuildMacro(bind.kind, bind.text, btn.unit,
            btn.isToT and "target" or nil, self.db.tauntFallback and not btn.isToT))
    end
end

function TM:ApplyBindingsToButton(btn, bindings)
    for _, click in ipairs(self.CLICKS) do
        self:SetClickAttributes(btn, click.typeAttr, click.macroAttr, bindings[click.key])
    end
    -- Keybindings click with the made-up buttons "TMLeft"/"TMRight". The "*" prefix
    -- matches any modifier, so a controller button bound as e.g. SHIFT-PAD1 still
    -- casts the plain Left/Right Click spell instead of the Shift-click one.
    self:SetClickAttributes(btn, "*type-tmleft", "*macrotext-tmleft", bindings["1"])
    self:SetClickAttributes(btn, "*type-tmright", "*macrotext-tmright", bindings["2"])
end

---------------------------------------------------------------------------
-- Keybindings (Options > Keybindings > TauntMaster Forever).
-- Listed in Bindings.xml; each one presses a bar (or the hidden "targeted ally"
-- button) with the Left or Right Click spell.
---------------------------------------------------------------------------
TM.KEYBIND_UNITS = {
    { unit = "player", label = "You" },
    { unit = "party1", label = "Party 1" },
    { unit = "party2", label = "Party 2" },
    { unit = "party3", label = "Party 3" },
    { unit = "party4", label = "Party 4" },
    { unit = "ally",   label = "Targeted ally" },
}
for _, u in ipairs(TM.KEYBIND_UNITS) do
    _G["BINDING_NAME_CLICK TauntMasterForever_" .. u.unit .. ":TMLeft"] = u.label .. ": Left Click spell"
    _G["BINDING_NAME_CLICK TauntMasterForever_" .. u.unit .. ":TMRight"] = u.label .. ": Right Click spell"
end

local function KeyText(command)
    local key = GetBindingKey and GetBindingKey(command)
    if not key then return nil end
    local ok, text = pcall(GetBindingText, key, true)   -- short form, like action bar hotkeys
    if not ok or type(text) ~= "string" or text == "" then text = key end
    return text
end

-- Shows e.g. "PAD1 / PAD2" beside each party bar that has keybindings
function TM:UpdateKeyHints()
    if not self.partyButtons then return end
    for _, btn in ipairs(self.partyButtons) do
        local cmd = "CLICK TauntMasterForever_" .. btn.unit
        local l, r = KeyText(cmd .. ":TMLeft"), KeyText(cmd .. ":TMRight")
        local text = (l and r) and (l .. " / " .. r) or l or r
        if self.db.keyHints and text then
            btn.keyHint:SetText(text)
            btn.keyHint:Show()
        else
            btn.keyHint:Hide()
        end
    end
end

function TM:ApplyBindings()
    self:RunOutOfCombat("bindings", function()
        local bindings = self:GetBindings()
        for _, btn in ipairs(self.buttons) do
            self:ApplyBindingsToButton(btn, bindings)
        end
        if self.allyButton then self:ApplyBindingsToButton(self.allyButton, bindings) end
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

-- In combat this waits (once) for the fight to end
function TM:Layout()
    self:RunOutOfCombat("layout", function()
        self:LayoutGroup(self.partyButtons, self.partyFrame)
        self:LayoutRaid()
        self.main:SetScale(self.db.scale)
        self.handle:SetWidth(self.db.width)

        -- Target-of-target bar sits above the cooldown icon row
        local tot = self.totButton
        if tot then
            tot:SetSize(self.db.width, self.db.height)
            tot:ClearAllPoints()
            tot:SetPoint("BOTTOMLEFT", self.handle, "TOPLEFT", 0, self.db.cdIconSize + 18)
            if self.db.showToT then
                RegisterUnitWatch(tot)
            else
                UnregisterUnitWatch(tot)
                tot:Hide()
            end
        end
    end)
end

-- Warrior Defensive Stance = stance 2, Druid Bear Form = form 1
local TANK_COND = { WARRIOR = "stance:2", DRUID = "form:1" }

function TM:ApplyVisibility()
    self:RunOutOfCombat("visibility", function()
        local db = self.db
        UnregisterStateDriver(self.main, "visibility")
        UnregisterStateDriver(self.partyFrame, "visibility")
        UnregisterStateDriver(self.raidFrame, "visibility")

        -- Whole addon (header, icons, warning): hidden entirely, or only when solo
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
end

-- The header looks the same locked or unlocked, and stays visible when locked
-- so its right-click menu is always reachable.
function TM:SetLocked(locked)
    self.db.locked = locked
    Print(locked and "locked." or "unlocked — drag the header to move.")
end

function TM:ShowHeaderMenu(owner)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        self:OpenConfig()
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("TauntMaster Forever")
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
        self.handle:FitLogo(self.db.headerFontSize + 6)
        self:RunOutOfCombat("header", function() self.handle:SetHeight(self.db.headerFontSize + 6) end)
    end
    local tex = self:TexturePath()
    local iconSize = math.max(10, math.min(self.db.height - 6, 18))
    for _, btn in ipairs(self.buttons) do
        btn.nameText:SetFont(font, self.db.nameFontSize, flags)
        btn.statusText:SetFont(font, self.db.nameFontSize, flags)
        btn.manaText:SetFont(font, self.db.nameFontSize, flags)
        btn.keyHint:SetFont(font, self.db.nameFontSize, flags)
        btn.bar:SetStatusBarTexture(tex)
        btn.roleIcon:SetSize(iconSize, iconSize)
    end
    -- Taunt cooldown icons (not protected, so this is safe in combat)
    if self.cdIcons then
        for _, b in ipairs(self.cdIcons) do b:SetSize(self.db.cdIconSize, self.db.cdIconSize) end
    end
end

function TM:ApplySettings()
    self:ApplyFonts()
    self:UpdateKeyHints()
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
    ns.Theme.HeaderStrip(handle)   -- logo and name, the same bar as ToppedOff Forever's
    handle:SetScript("OnDragStart", function()
        if TM.db.locked or InCombatLockdown() then return end
        main.isMoving = true
        main:StartMoving()
    end)
    handle:SetScript("OnDragStop", function()
        if not main.isMoving then return end
        main.isMoving = false
        main:StopMovingOrSizing()
        TM:SavePosition()
    end)
    handle:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then TM:ShowHeaderMenu(self) end
    end)
    handle:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("TauntMaster Forever")
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

    -- Hidden button for the "Targeted ally" keybindings: taunts whatever is attacking
    -- the friendly player you have targeted. Works in raids, where per-slot bindings don't.
    local ally = CreateFrame("Button", "TauntMasterForever_ally", UIParent, "SecureUnitButtonTemplate")
    ally.unit = "target"
    ally:SetAttribute("unit", "target")
    ally:RegisterForClicks("AnyUp")
    ally:HookScript("PreClick", function(self, mouseButton) TM:OnBarClick(mouseButton, self) end)
    self.allyButton = ally

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

    -- The round logo, whole, inside the button's ring (as in ToppedOff Forever)
    local icon = b:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(22, 22)
    icon:SetTexture(ns.Theme.LOGO)
    icon:SetPoint("TOPLEFT", 5, -4)
    b.icon = icon

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

-- Calls fn(click, bind) for every click bound to a spell, in menu order
function TM:EachSpellBinding(fn)
    local bindings = self:GetBindings()
    for _, click in ipairs(self.CLICKS) do
        local bind = bindings[click.key]
        if bind and self.SPELL_KINDS[bind.kind] and bind.text ~= "" then fn(click, bind) end
    end
end

function TM:CheckSpells()
    Print("Checking bound spells for " .. (UnitClass("player")) .. ":")
    local any = false
    self:EachSpellBinding(function(click, bind)
        any = true
        local info = self:GetSpellInfo(bind.text)
        if not info then
            print(("  %s: |cffff4040%s — not found. Check spelling or that it exists in Forever.|r"):format(click.label, bind.text))
        elseif SpellKnown(info.spellID) == false then
            print(("  %s: |cffffcc00%s (ID %d) — exists, not learned yet.|r"):format(click.label, bind.text, info.spellID))
        else
            print(("  %s: |cff40ff40%s (ID %d) — OK.|r"):format(click.label, bind.text, info.spellID))
        end
    end)
    if not any then print("  No spells bound. Open /tm spells.") end
end

-- "TauntMaster Forever loaded. Growl assigned to Left Click, Challenging Roar assigned to Right Click."
-- Spells the client can't find are flagged in red, so no manual /tm check is needed.
function TM:PrintLoadMessage()
    local parts = {}
    self:EachSpellBinding(function(click, bind)
        local name = "|cffffd100" .. bind.text .. "|r"
        if C_Spell and not self:GetSpellInfo(bind.text) then
            name = "|cffff4040" .. bind.text .. " (not found)|r"
        end
        parts[#parts + 1] = name .. " assigned to " .. click.label .. " Click"
    end)
    local msg = ns.Theme.CHAT_PREFIX .. " loaded."
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
    print("  /tm spells — jump to Click Bindings in the options")
    print("  /tm check — verify your bound spells exist in Forever")
    print("  /tm news — show the welcome / what's new window")
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
    elseif msg == "news" then
        TM:ToggleSplash()
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
        local bind = TM:GetBindings()["1"]
        local info = bind and TM:GetSpellInfo(bind.text)
        local cd = info and C_Spell.GetSpellCooldown and C_Spell.GetSpellCooldown(info.spellID)
        if cd then
            print("  Left Click cooldown (" .. info.name .. "):")
            show("    start", cd.startTime)
            show("    duration", cd.duration)
            show("    isActive", cd.isActive)
            show("    isOnGCD", cd.isOnGCD)
            show("    duration object API", C_Spell.GetSpellCooldownDuration ~= nil)
        end
    elseif msg == "reset" then
        TM.db.point = { "CENTER", "CENTER", -300, 0 }
        TM:RunOutOfCombat("position", function() TM:RestorePosition() end)
        Print(InCombatLockdown() and "position will reset when combat ends." or "position reset.")
    else
        Help()
    end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Your own successful spell casts, for taunt announcements
local castEvents = CreateFrame("Frame")
castEvents:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
castEvents:SetScript("OnEvent", function(_, _, _, _, spellID)
    if TM.db then TM:OnSpellCastSucceeded(spellID) end
end)

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
events:RegisterEvent("UPDATE_BINDINGS")
events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        TauntMasterForeverDB = TauntMasterForeverDB or {}
        FillDefaults(TauntMasterForeverDB, DEFAULTS)
        TM.db = TauntMasterForeverDB
        -- Settings migrations for installs from earlier versions
        if (TM.db.schema or 0) < 2 then
            TM.db.aggroSound = false -- aggro sound is now off by default
            TM.db.schema = 2
        end
        if TM.db.schema < 3 then
            if TM.db.announceText == "Taunted!" then -- old default: switch to the one with names
                TM.db.announceText = DEFAULTS.announceText
            end
            TM.db.schema = 3
        end
        -- Older versions allowed both cooldown modes at once
        if TM.db.cdShowOnCooldown and TM.db.cdShowWhenReady then
            TM.db.cdShowWhenReady = false
        end
    elseif event == "PLAYER_LOGIN" then
        TM:RunOutOfCombat("build", function() TM:BuildFrames() end)
        TM:PrintLoadMessage()
        TM:MaybeShowSplash()
    elseif event == "PLAYER_REGEN_ENABLED" then
        TM:FlushPending()
    -- Nameplates are tracked from the start, so the ones already up after a
    -- /reload in combat (when the bars are built late) get their marks too
    elseif event == "NAME_PLATE_UNIT_ADDED" then
        TM:OnNamePlateAdded(arg1)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        TM:OnNamePlateRemoved(arg1)
    elseif not TM.built then
        return
    elseif event == "UPDATE_BINDINGS" then
        TM:UpdateKeyHints()
    elseif event == "SPELL_UPDATE_COOLDOWN" then
        TM:UpdateCooldowns()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" then
        if TM.db.sortByRole or IsInRaid() then TM:Layout() end
        TM:RefreshAll()
    elseif arg1 and TM.unitToButton[arg1] then
        if event == "UNIT_THREAT_SITUATION_UPDATE" then
            TM:UpdateButton(TM.unitToButton[arg1])
        else
            TM:UpdateHealth(TM.unitToButton[arg1])   -- UNIT_HEALTH, UNIT_MAXHEALTH
        end
    end
end)
