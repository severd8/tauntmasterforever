-- Minimal WoW API stub for exercising TauntMaster Forever outside the game.
-- Methods (CamelCase keys) default to no-ops; lowercase fields read as nil like real frames.

LOG = {}
local function log(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end LOG[#LOG + 1] = table.concat(t, " ") end
print = function(...) log(...) end

ALL_FRAMES = {}
BLOCKED = {}          -- protected actions attempted in combat
COMBAT = false
SECRET_MODE = false

-- Secret values: a marker table that errors on arithmetic, ordering, concatenation
local SecretMT = {}
local function boom() error("attempted to use a secret value", 2) end
SecretMT.__add, SecretMT.__sub, SecretMT.__mul, SecretMT.__div = boom, boom, boom, boom
SecretMT.__lt, SecretMT.__le, SecretMT.__concat, SecretMT.__unm = boom, boom, boom, boom
SecretMT.__tostring = function() return "<secret>" end
local function secret(v) return setmetatable({ v = v }, SecretMT) end
function issecretvalue(v) return type(v) == "table" and getmetatable(v) == SecretMT end
local function maybeSecret(v) if SECRET_MODE then return secret(v) end return v end

local PROTECTED_WHEN_COMBAT = { SetPoint = true, ClearAllPoints = true, SetSize = true, SetWidth = true,
    SetHeight = true, SetAttribute = true, Show = true, Hide = true, SetShown = true, SetScale = true }

local ObjMT = {}
local Methods = {}
ObjMT.__index = function(t, k)
    if Methods[k] then return Methods[k] end
    if type(k) == "string" and k:match("^%u") then
        return function(self, ...)
            for i = 1, select("#", ...) do
                local a = select(i, ...)
                if issecretvalue(a) and not ({ SetText = 1, SetFormattedText = 1, SetValue = 1, SetMinMaxValues = 1,
                        SetAlpha = 1, SetCooldown = 1 })[k] then
                    error("secret passed to " .. k)
                end
            end
            if COMBAT and self.__protected and PROTECTED_WHEN_COMBAT[k] then
                BLOCKED[#BLOCKED + 1] = (self.__name or self.__kind) .. ":" .. k
            end
            return nil
        end
    end
    return nil
end

function newObj(kind, name, parent, template)
    local o = setmetatable({ __kind = kind, __name = name, __parent = parent, __template = template,
        __scripts = {}, __shown = true, __attrs = {}, __children = {} }, ObjMT)
    if template and (template:find("Secure") or template:find("SecureUnitButton")) then o.__protected = true end
    if parent and parent.__children then table.insert(parent.__children, o) end
    ALL_FRAMES[#ALL_FRAMES + 1] = o
    if name then _G[name] = o end
    return o
end

local function protectedCheck(self, what)
    if COMBAT and self.__protected then BLOCKED[#BLOCKED + 1] = (self.__name or self.__kind) .. ":" .. what end
end

function Methods:CreateTexture() return newObj("Texture", nil, self) end
function Methods:CreateFontString() local f = newObj("FontString", nil, self); f.__text = "" return f end
function Methods:CreateAnimationGroup() local g = newObj("AnimationGroup", nil, self); g.__playing = false return g end
function Methods:CreateAnimation() return newObj("Animation", nil, self) end
function Methods:Play() self.__playing = true end
function Methods:Stop() self.__playing = false end
function Methods:IsPlaying() return self.__playing end
function Methods:Show() protectedCheck(self, "Show") self.__shown = true if self.__scripts.OnShow then self.__scripts.OnShow(self) end end
function Methods:Hide() protectedCheck(self, "Hide") self.__shown = false end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self.__shown end
function Methods:IsVisible()
    local f = self
    while f do if f.__shown == false then return false end f = f.__parent end
    return true
end
function Methods:SetScript(k, fn) self.__scripts[k] = fn end
function Methods:GetScript(k) return self.__scripts[k] end
function Methods:HookScript(k, fn)
    local old = self.__scripts[k]
    self.__scripts[k] = function(...) if old then old(...) end fn(...) end
end
function Methods:SetAttribute(k, v) protectedCheck(self, "SetAttribute") self.__attrs[k] = v end
function Methods:GetAttribute(k) return self.__attrs[k] end
function Methods:SetText(t)
    if issecretvalue(t) then self.__text = "<secret>" return end
    self.__text = t
end
function Methods:SetFormattedText(fmt, ...)
    for i = 1, select("#", ...) do if issecretvalue((select(i, ...))) then self.__text = "<secret fmt>" return end end
    self.__text = fmt:format(...)
end
function Methods:GetText() return self.__text end
function Methods:SetChecked(v) self.__checked = v and true or false end
function Methods:GetChecked() return self.__checked end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 10, "" end
function Methods:GetRegions() local r = {} for _, c in ipairs(self.__children) do if c.__kind == "Texture" or c.__kind == "FontString" then r[#r + 1] = c end end return unpack(r) end
function Methods:GetObjectType() return self.__kind end
function Methods:GetHighlightTexture() return nil end
function Methods:GetPoint() return "CENTER", UIParent, "CENTER", 12, 34 end
local oldSetPoint
function Methods:SetPoint(p, rel, rp, x, y)
    if COMBAT and self.__protected then BLOCKED[#BLOCKED + 1] = (self.__name or self.__kind) .. ":SetPoint" end
    if type(rel) == "table" then self.__pos = { x or 0, y or 0 } else self.__pos = { rel or 0, rp or 0 } end
end
function Methods:GetWidth() return 140 end
function Methods:GetCenter() return 0, 0 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetName() return self.__name end
function Methods:SetSize(w, h) protectedCheck(self, "SetSize") self.__size = { w, h } end
function Methods:SetValue(v) self.__value = v if self.__scripts.OnValueChanged then self.__scripts.OnValueChanged(self, issecretvalue(v) and 0 or v) end end
function Methods:SetMinMaxValues(a, b) end
function Methods:RegisterEvent(e) self.__events = self.__events or {} self.__events[e] = true end
function Methods:RegisterUnitEvent(e) self.__events = self.__events or {} self.__events[e] = true end
function Methods:SetAlpha(a) self.__alpha = a end
function Methods:GetFontString() return nil end
function Methods:SetEnabled(v) self.__enabled = v end

function CreateFrame(kind, name, parent, template) return newObj(kind, name, parent, template) end
UIParent = newObj("Frame", "UIParent")
Minimap = newObj("Frame", "Minimap")
GameTooltip = newObj("GameTooltip", "GameTooltip")
GameFontNormalSmall = newObj("Font", "GameFontNormalSmall")
GameFontNormal = newObj("Font", "GameFontNormal")
GameFontDisable = newObj("Font", "GameFontDisable")
GameFontHighlight = newObj("Font", "GameFontHighlight")
function GameTooltip_SetDefaultAnchor() end

-- World state the tests control
STATE = {
    class = "DRUID", inGroup = false, inRaid = false, party = 0,
    roles = {}, threat = {}, mana = { player = 10 }, unitsExist = { player = true },
}
function UnitClass(u) if u == "player" then return "Druid", STATE.class end return maybeSecret("Priest"), maybeSecret("PRIEST") end
function UnitName(u) return maybeSecret(u == "player" and "Visadrix" or ("Name_" .. u)) end
function UnitExists(u) return maybeSecret(STATE.unitsExist[u] and true or false) end
function UnitHealth(u) return maybeSecret(50) end
function UnitHealthMax(u) return maybeSecret(100) end
function UnitHealthPercent(u, pred, curve) return maybeSecret(50) end
function UnitPower(u, t) return maybeSecret(STATE.mana[u] or 100) end
function UnitPowerMax(u, t) if u == "player" then return 542 end return maybeSecret(1000) end
function UnitPowerType(u) return 0 end
function UnitPowerPercent(u, t, pred, curve) return maybeSecret(0.5) end
function UnitThreatSituation(u) local t = STATE.threat[u] if t == nil then return nil end return maybeSecret(t) end
function UnitIsUnit(a, b) return a == b end
function UnitIsDeadOrGhost(u) return false end
function UnitIsConnected(u) return true end
function UnitInRange(u) return maybeSecret(true), true end
function UnitGroupRolesAssigned(u) return STATE.roles[u] or "NONE" end
function IsInGroup() return STATE.inGroup end
function IsInRaid() return STATE.inRaid end
function GetNumGroupMembers() return STATE.inRaid and 10 or (STATE.party + 1) end
function GetNumSubgroupMembers() return STATE.party end
function InCombatLockdown() return COMBAT end
FAKE_TIME = 100
function GetTime() return FAKE_TIME end
MOD_KEYS = {}
function IsShiftKeyDown() return MOD_KEYS.shift end
function IsControlKeyDown() return MOD_KEYS.ctrl end
function IsAltKeyDown() return MOD_KEYS.alt end
CHAT = {}
KEYBINDS = {}   -- command -> key, e.g. ["CLICK TauntMasterForever_party1:TMLeft"] = "PAD1"
function GetBindingKey(cmd) return KEYBINDS[cmd] end
function GetBindingText(key, short) return (short and key:gsub("^SHIFT%-", "s-")) or key end
C_ChatInfo = { SendChatMessage = function(text, chat) CHAT[#CHAT + 1] = chat .. ":" .. text end }
LE_PARTY_CATEGORY_INSTANCE = 2
function PlaySound(k) log("SOUND", k) end
SOUNDKIT = { RAID_WARNING = 8959 }
RAID_CLASS_COLORS = { DRUID = { r = 1, g = 0.49, b = 0.04 }, PRIEST = { r = 1, g = 1, b = 1 } }
function RegisterUnitWatch() end
function UnregisterUnitWatch() end
function RegisterStateDriver(f, k, v) f.__driver = v end
function UnregisterStateDriver(f, k) f.__driver = nil end
TICKERS = {}
C_Timer = { NewTicker = function(_, fn) TICKERS[#TICKERS + 1] = fn end, After = function(_, fn) fn() end }
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
KNOWN = { Growl = { spellID = 6795, iconID = 1 }, ["Challenging Roar"] = { spellID = 5209, iconID = 2 },
    Taunt = { spellID = 355, iconID = 3 }, ["Bear Form"] = { spellID = 5487, iconID = 4 },
    ["Mark of the Wild"] = { spellID = 1126, iconID = 5 } }
for n, info in pairs(KNOWN) do info.name = n end
-- Like the real game: spell lookup by name ignores capitalization
local function lookup(n)
    if type(n) == "number" then   -- the real API takes spell IDs too
        for _, info in pairs(KNOWN) do if info.spellID == n then return info end end
        return nil
    end
    if type(n) ~= "string" then return nil end
    for name, info in pairs(KNOWN) do if name:lower() == n:lower() then return info end end
    return nil
end
-- Spellbook: Druid has learned everything above except Taunt (a Warrior spell)
SPELLBOOK = { "Growl", "Challenging Roar", "Bear Form", "Mark of the Wild" }
C_SpellBook = {
    GetNumSpellBookSkillLines = function() return 1 end,
    GetSpellBookSkillLineInfo = function(i) return { itemIndexOffset = 0, numSpellBookItems = #SPELLBOOK } end,
    GetSpellBookItemInfo = function(j) local n = SPELLBOOK[j] return { name = n, iconID = KNOWN[n].iconID, isPassive = false } end,
}
C_Spell = {
    GetSpellInfo = function(n) return lookup(n) end,
    GetSpellCooldown = function(id) return { startTime = maybeSecret(100), duration = maybeSecret(10) } end,
    -- RANGE[unit] = true / false / "none" (spell can't be cast on it -> nil)
    IsSpellInRange = function(n, u)
        local r = RANGE[u]
        if r == "none" then return SECRET_MODE and maybeSecret(false) or nil end
        if r == nil then r = true end
        return maybeSecret(r)
    end,
}
function IsPlayerSpell(id) return id ~= 355 end   -- Druid hasn't learned Taunt
C_CurveUtil = {
    CreateCurve = function() return newObj("Curve") end,
    EvaluateColorValueFromBoolean = function(b, t, f)
        local v = b
        if issecretvalue(b) then v = b.v end
        return maybeSecret(v and t or f)
    end,
}
RANGE = {}
HOSTILE = {}   -- HOSTILE[unit] = false for a friendly / missing target (default: hostile)
function UnitCanAttack(a, u) return maybeSecret(HOSTILE[u] ~= false) end
CurveConstants = { ScaleTo100 = newObj("Curve") }
Enum = { LuaCurveType = { Step = 1 }, SpellBookSpellBank = { Player = 0 } }
C_AddOns = { GetAddOnMetadata = function() return "test" end }
function GetCursorPosition() return 10, 10 end
UISpecialFrames = {}
StaticPopupDialogs = {}
POPUPS = {}
function StaticPopup_Show(name, a, b, data) POPUPS[#POPUPS + 1] = { name = name, data = data } end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
ACCEPT, CANCEL = "Accept", "Cancel"
SlashCmdList = {}

-- Menu stub: records entries and lets tests "click" them
MENUS = {}
local function menuRoot()
    local root = { entries = {} }
    function root:CreateTitle(t) table.insert(self.entries, { kind = "title", text = t }) end
    function root:CreateDivider() table.insert(self.entries, { kind = "divider" }) end
    function root:CreateButton(t, fn) table.insert(self.entries, { kind = "button", text = t, fn = fn }) end
    function root:CreateCheckbox(t, get, set) table.insert(self.entries, { kind = "check", text = t, get = get, fn = set }) end
    function root:CreateRadio(t, get, set) table.insert(self.entries, { kind = "radio", text = t, get = get, fn = set }) end
    return root
end
MenuUtil = { CreateContextMenu = function(owner, builder) local r = menuRoot() builder(owner, r) MENUS[#MENUS + 1] = r end }

RAID_GROUPS = {}
function GetRaidRosterInfo(i) return "Name" .. i, 0, RAID_GROUPS[i] or math.ceil(i / 5) end
