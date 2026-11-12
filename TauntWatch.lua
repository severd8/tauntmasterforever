-- TauntMaster Forever: taunt alerts. A popup (and an optional sound) when someone
-- in your group, a group member's pet, you or your pet uses a taunt.
--
-- Forever can hide other players' casts from addons (the spell comes back as a
-- secret value, most likely in dungeons and raids). A cast that can't be read
-- shows nothing: the popup never guesses.

local _, ns = ...
local TM = ns.TM

local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

---------------------------------------------------------------------------
-- Which spells are taunts. Matched by name (every rank of a spell shares it), in
-- the game's language: the IDs give the local names, the English ones are a fallback.
---------------------------------------------------------------------------
local TAUNT_SPELLS = {
    { name = "Taunt", id = 355 },                  -- Warrior
    { name = "Mocking Blow", id = 694 },           -- Warrior
    { name = "Challenging Shout", id = 1161, aoe = true },
    { name = "Growl", id = 6795 },                 -- Druid (Bear Form); hunter pets share the name
    { name = "Challenging Roar", id = 5209, aoe = true },
    { name = "Growl", id = 2649 },                 -- Hunter pet
    { name = "Torment", id = 3716 },               -- Warlock Voidwalker
    { name = "Suffering", id = 17735, aoe = true },-- Warlock Voidwalker
}
TM.TAUNT_SPELLS = TAUNT_SPELLS

local tauntNames   -- lower-case name -> { aoe = bool }, built on first use

local function TauntInfo(spellID)
    if not tauntNames then
        tauntNames = {}
        for _, s in ipairs(TAUNT_SPELLS) do
            tauntNames[s.name:lower()] = { aoe = s.aoe }
            local loc = TM:LocalSpellName(s.name, s.id)
            tauntNames[loc:lower()] = { aoe = s.aoe }
        end
    end
    local name = C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)
    if IsSecret(name) or type(name) ~= "string" then return nil end
    local info = tauntNames[name:lower()]
    if info then return name, info.aoe end
    return nil
end

---------------------------------------------------------------------------
-- Group units whose casts count, and who owns each pet
---------------------------------------------------------------------------
local OWNER = { player = false, pet = "player" }
for i = 1, 4 do OWNER["party" .. i] = false; OWNER["partypet" .. i] = "party" .. i end
for i = 1, 40 do OWNER["raid" .. i] = false; OWNER["raidpet" .. i] = "raid" .. i end

local function IsUnit(a, b)
    local same = UnitIsUnit(a, b)
    return not IsSecret(same) and same == true
end

---------------------------------------------------------------------------
-- The popup: up to three lines, newest at the top, each fading after a few seconds
---------------------------------------------------------------------------
local LINES, SHOW_FOR, FADE_FOR = 3, 4, 1
local OWN_COLOR = { 1, 0.82, 0 }         -- gold, like the addon's other text
local GROUP_COLOR = { 1, 0.5, 0.25 }     -- orange-red, like a raid warning
local popup

local function PlacePopup()
    local p = TM.db.tauntPopupPoint
    popup:ClearAllPoints()
    popup:SetPoint(p[1], UIParent, p[2], p[3], p[4])
end

local function SizeLines()
    local font, _, flags = GameFontNormalHuge:GetFont()
    for _, line in ipairs(popup.lines) do
        line:SetFont(font, TM.db.tauntPopupSize, flags or "OUTLINE")
    end
    popup:SetHeight(LINES * (TM.db.tauntPopupSize + 6))
end

local function BuildPopup()
    popup = CreateFrame("Frame", nil, UIParent)
    popup:SetSize(640, 80)
    popup:SetFrameStrata("HIGH")
    popup:SetClampedToScreen(true)
    popup:SetMovable(true)
    popup:RegisterForDrag("LeftButton")
    popup.lines = {}
    for i = 1, LINES do
        local fs = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        if i == 1 then
            fs:SetPoint("TOP", popup, "TOP", 0, 0)
        else
            fs:SetPoint("TOP", popup.lines[i - 1], "BOTTOM", 0, -4)
        end
        fs:SetJustifyH("CENTER")
        fs:SetText("")
        fs.expires = 0
        popup.lines[i] = fs
    end
    -- Shown only while the popup is being moved
    popup.anchor = popup:CreateTexture(nil, "BACKGROUND")
    popup.anchor:SetAllPoints()
    popup.anchor:SetColorTexture(0.48, 0.11, 0.06, 0.5)
    popup.anchor:Hide()
    popup:SetScript("OnDragStart", function(self) if TM.tauntPopupMoving then self:StartMoving() end end)
    popup:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        TM.db.tauntPopupPoint = { point, relPoint, x, y }
    end)
    -- Fading runs only while a line is showing
    popup:SetScript("OnUpdate", function(self)
        if TM.tauntPopupMoving then return end
        local now, any = GetTime(), false
        for _, line in ipairs(self.lines) do
            local left = line.expires - now
            if left > 0 then
                any = true
                line:SetAlpha(math.min(1, left / FADE_FOR))
            else
                line:SetText("")
            end
        end
        if not any then self:Hide() end
    end)
    PlacePopup()
    SizeLines()
    popup:Hide()
end

-- Moves every line down one and returns the top one, ready for new text
local function NewLine(color)
    if not popup then BuildPopup() end
    local lines = popup.lines
    for i = LINES, 2, -1 do
        local from, to = lines[i - 1], lines[i]
        to.expires = from.expires
        if from.expires > GetTime() then
            to:SetText(from:GetText())
            to:SetTextColor(from:GetTextColor())
        else
            to:SetText("")
        end
    end
    local top = lines[1]
    top.expires = GetTime() + SHOW_FOR
    top:SetTextColor(color[1], color[2], color[3])
    top:SetAlpha(1)
    popup:Show()
    return top
end

---------------------------------------------------------------------------
-- A taunt was cast: say who, on what, with which spell. Names may be hidden
-- from addons, so they only ever go straight into the text (SetFormattedText).
---------------------------------------------------------------------------
local lastSound = { own = 0, group = 0 }

local function PlayTauntSound(kind)
    local key = kind == "own" and TM.db.ownTauntSound or TM.db.groupTauntSound
    if key == "none" then return end
    local now = GetTime()
    if now - lastSound[kind] < 0.5 then return end   -- one sound for a burst of taunts
    lastSound[kind] = now
    TM:PlaySoundChoice(TM.TAUNT_SOUNDS, key, TM.db.tauntSoundChannel)
end

local function TargetName(unit, aoe)
    if aoe then return nil end
    local name = UnitName(unit .. "target")
    if not IsSecret(name) and (type(name) ~= "string" or name == "") then return nil end
    return name
end

function TM:ShowTaunt(unit, spellName, aoe)
    local owner = OWNER[unit]
    local own = unit == "player" or unit == "pet" or IsUnit(unit, "player") or IsUnit(unit, "pet")
    if own and not self.db.ownTauntPopup then return end
    if not own and not self.db.groupTauntPopup then return end

    local line = NewLine(own and OWN_COLOR or GROUP_COLOR)
    local target = TargetName(unit, aoe)
    local name = UnitName(unit)
    local onWhat = aoe and " on everything nearby" or ""
    if own and owner then
        if target then line:SetFormattedText("Your pet %s taunted %s with %s", name, target, spellName)
        else line:SetFormattedText("Your pet %s used %s" .. onWhat, name, spellName) end
    elseif own then
        if target then line:SetFormattedText("You taunted %s with %s", target, spellName)
        else line:SetFormattedText("You used %s" .. onWhat, spellName) end
    elseif owner then
        local ownerName = UnitName(owner)
        if target then line:SetFormattedText("%s (%s's pet) taunted %s with %s", name, ownerName, target, spellName)
        else line:SetFormattedText("%s (%s's pet) used %s" .. onWhat, name, ownerName, spellName) end
    else
        if target then line:SetFormattedText("%s taunted %s with %s", name, target, spellName)
        else line:SetFormattedText("%s used %s" .. onWhat, name, spellName) end
    end
    PlayTauntSound(own and "own" or "group")
end

-- The same cast can arrive under two names (raid3 and party1, player and raid5)
local seenCasts, seenCount = {}, 0

local function OnCast(unit, castGUID, spellID)
    if OWNER[unit] == nil then return end                   -- not a group member or pet
    if IsSecret(spellID) or type(spellID) ~= "number" then return end
    local spellName, aoe = TauntInfo(spellID)
    if not spellName then return end
    if not IsSecret(castGUID) and castGUID then
        if seenCasts[castGUID] then return end
        seenCount = seenCount + 1
        if seenCount > 50 then seenCasts, seenCount = {}, 1 end
        seenCasts[castGUID] = true
    end
    TM:ShowTaunt(unit, spellName, aoe)
end

---------------------------------------------------------------------------
-- Listening only while a popup is wanted: every unit's casts arrive on this
-- event, which is a lot in a raid
---------------------------------------------------------------------------
local watcher = CreateFrame("Frame")
watcher:SetScript("OnEvent", function(_, _, unit, castGUID, spellID) OnCast(unit, castGUID, spellID) end)

function TM:UpdateTauntWatch()
    local on = self.db.groupTauntPopup or self.db.ownTauntPopup
    if on then
        watcher:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    else
        watcher:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
    if popup then
        PlacePopup()
        SizeLines()
    end
end

---------------------------------------------------------------------------
-- Options: test, move, reset
---------------------------------------------------------------------------
function TM:TestTauntPopup()
    local line = NewLine(GROUP_COLOR)
    line:SetText("Fluffy (Aeri's pet) taunted Defias Thug with Growl")
    line = NewLine(OWN_COLOR)
    line:SetText("You taunted Defias Pillager with " .. self:LocalSpellName("Taunt", 355))
end

function TM:TestTauntSound(kind)
    lastSound[kind] = 0
    PlayTauntSound(kind)
end

function TM:SetTauntPopupMoving(on)
    if not popup then BuildPopup() end
    self.tauntPopupMoving = on and true or false
    popup:EnableMouse(self.tauntPopupMoving)
    popup.anchor:SetShown(self.tauntPopupMoving)
    if self.tauntPopupMoving then
        popup.lines[1]:SetText("Taunt alerts show here. Drag to move.")
        popup.lines[1]:SetTextColor(GROUP_COLOR[1], GROUP_COLOR[2], GROUP_COLOR[3])
        popup.lines[1]:SetAlpha(1)
        popup.lines[1].expires = GetTime() + 3600
        popup:Show()
    else
        for _, line in ipairs(popup.lines) do line.expires = 0; line:SetText("") end
        popup:Hide()
    end
end

function TM:ResetTauntPopupPosition()
    self.db.tauntPopupPoint = { "TOP", "TOP", 0, -190 }
    if popup then PlacePopup() end
end

TM._tauntPopup = function() return popup end
TM._onTauntCast = OnCast
