-- TauntMaster Forever: Settings window (quick options) and Advanced window (all bindings)

local ADDON, ns = ...
local TM = ns.TM

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end
local function RunRefreshers() for _, fn in ipairs(refreshers) do fn() end end

---------------------------------------------------------------------------
-- Widget helpers
---------------------------------------------------------------------------
local function Label(parent, text, x, y, template)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    return fs
end

local function Check(parent, text, x, y, key, template, invert)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(text)
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        if invert then v = not v end
        if key == "locked" then
            TM:SetLocked(v)
        else
            TM.db[key] = v
            TM:ApplySettings()
        end
    end)
    AddRefresher(function()
        local v = TM.db[key] and true or false
        if invert then v = not v end
        cb:SetChecked(v)
    end)
    return cb
end

local function Slider(parent, text, y, key, min, max, suffix, onChange, x)
    suffix = suffix or ""
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if x then
        title:SetPoint("TOP", parent, "TOPLEFT", x, y)
    else
        title:SetPoint("TOP", 0, y)
    end

    local s = CreateFrame("Slider", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(180, 17)
    s:SetPoint("TOP", title, "BOTTOM", 0, -3)
    s:SetHitRectInsets(0, 0, -8, -8)
    if s.SetBackdrop and BACKDROP_SLIDER_8_8 then
        s:SetBackdrop(BACKDROP_SLIDER_8_8)
    else
        local track = s:CreateTexture(nil, "BACKGROUND")
        track:SetColorTexture(0, 0, 0, 0.6)
        track:SetHeight(6)
        track:SetPoint("LEFT")
        track:SetPoint("RIGHT")
    end
    s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    s:SetMinMaxValues(min, max)
    s:SetValueStep(1)
    if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end

    local low = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    low:SetPoint("TOPLEFT", s, "BOTTOMLEFT", 0, 0)
    low:SetText(min)
    local high = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    high:SetPoint("TOPRIGHT", s, "BOTTOMRIGHT", 0, 0)
    high:SetText(max)

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v + 0.5)
        title:SetText(text .. ": |cffffd100" .. v .. suffix .. "|r")
        if TM.db[key] ~= v then
            TM.db[key] = v
            if onChange then
                onChange()
            else
                -- Size/layout sliders: re-layout (once, after combat if needed) and resize role icons
                TM:ApplyFonts()
                TM:RequestLayout()
            end
        end
    end)
    AddRefresher(function()
        s:SetValue(TM.db[key])
        title:SetText(text .. ": |cffffd100" .. TM.db[key] .. suffix .. "|r")
    end)
    return s
end

local function Stepper(parent, text, x, y, key, step, min, max, fmt)
    Label(parent, text, x, y - 4)
    local value = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    value:SetPoint("TOPLEFT", x + 110, y - 4)
    value:SetWidth(40)
    local function set(v)
        v = math.max(min, math.min(max, v))
        v = math.floor(v / step + 0.5) * step
        TM.db[key] = v
        value:SetText(fmt:format(v))
        TM:ApplySettings()
    end
    local minus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    minus:SetSize(24, 20)
    minus:SetPoint("TOPLEFT", x + 155, y)
    minus:SetText("-")
    minus:SetScript("OnClick", function() set(TM.db[key] - step) end)
    local plus = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    plus:SetSize(24, 20)
    plus:SetPoint("LEFT", minus, "RIGHT", 2, 0)
    plus:SetText("+")
    plus:SetScript("OnClick", function() set(TM.db[key] + step) end)
    AddRefresher(function() value:SetText(fmt:format(TM.db[key])) end)
end

local function Cycle(parent, width, list, labels, getter, setter)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    local function refresh() b:SetText(labels[getter()] or getter()) end
    b:SetScript("OnClick", function()
        local cur, nextIdx = getter(), 1
        for i, v in ipairs(list) do
            if v == cur then nextIdx = (i % #list) + 1 break end
        end
        setter(list[nextIdx])
        refresh()
    end)
    b.Refresh = refresh
    return b
end

local function EditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    eb:SetSize(width, 20)
    eb:SetAutoFocus(false)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
end

local function Window(name, title, w, h)
    local f = CreateFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
    f:SetSize(w, h)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    local solid = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    solid:SetPoint("TOPLEFT", 2, -2)
    solid:SetPoint("BOTTOMRIGHT", -2, 2)
    solid:SetColorTexture(0.06, 0.06, 0.06, 1)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetScript("OnShow", RunRefreshers)
    f:Hide()
    table.insert(UISpecialFrames, name)
    local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOP", 0, -5)
    t:SetText(title)
    return f
end

---------------------------------------------------------------------------
-- Spell picker (Left / Right Click Spell)
---------------------------------------------------------------------------
local function SpellKnown(spellID)
    if IsPlayerSpell then return IsPlayerSpell(spellID) end
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then return C_SpellBook.IsSpellInSpellBook(spellID) end
    return nil
end

local function SpellLabel(s)
    local info = C_Spell and C_Spell.GetSpellInfo(s.name)
    local icon = info and info.iconID and ("|T" .. info.iconID .. ":16:16:0:0|t ") or ""
    local label = icon .. s.name
    if s.note then label = label .. " |cff999999(" .. s.note .. ")|r" end
    if not info then
        label = label .. " |cffff4040not found|r"
    elseif SpellKnown(info.spellID) == false then
        label = label .. " |cff808080not learned|r"
    end
    return label
end

local function BindingText(key)
    local b = TM:GetBindings()[key]
    if not b or b.kind == "none" then return "None" end
    if b.kind == "assist" or b.kind == "target" then return TM.KIND_LABELS[b.kind] end
    if b.kind == "macro" then return "Macro" end
    return b.text
end

StaticPopupDialogs["TAUNTMASTERFOREVER_CUSTOM"] = {
    text = "Type a spell name.\nIt will be cast on the clicked member's target:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 64,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self, data)
        local eb = (self.GetEditBox and self:GetEditBox()) or self.editBox or self.EditBox
        local text = eb and strtrim(eb:GetText() or "")
        if text and text ~= "" then
            TM:SetBinding(data or self.data, "enemy", text)
            RunRefreshers()
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self:GetParent()
        StaticPopupDialogs.TAUNTMASTERFOREVER_CUSTOM.OnAccept(popup, popup.data)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

local function ShowSpellMenu(owner, key)
    local spells = TM:GetClassSpells()
    local current = TM:GetBindings()[key]

    local function isSelected(s)
        return current and current.text == s.name and current.kind == s.kind
    end
    local function choose(s)
        TM:SetBinding(key, s.kind, s.name)
        RunRefreshers()
    end

    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- Fallback: cycle through the class list
        local nextIdx = 1
        for i, s in ipairs(spells) do
            if isSelected(s) then nextIdx = (i % #spells) + 1 break end
        end
        if spells[nextIdx] then choose(spells[nextIdx]) end
        return
    end

    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Taunt abilities")
        local hasUtility = false
        for _, s in ipairs(spells) do
            if s.utility then
                hasUtility = true
            else
                root:CreateRadio(SpellLabel(s), function() return isSelected(s) end, function() choose(s) end)
            end
        end
        if #spells == 0 then
            root:CreateTitle("|cff999999No taunts for your class|r")
        end
        if hasUtility then
            root:CreateDivider()
            root:CreateTitle("Utility")
            for _, s in ipairs(spells) do
                if s.utility then
                    root:CreateRadio(SpellLabel(s), function() return isSelected(s) end, function() choose(s) end)
                end
            end
        end
        root:CreateDivider()
        root:CreateButton("Custom spell...", function()
            StaticPopup_Show("TAUNTMASTERFOREVER_CUSTOM", nil, nil, key)
        end)
        root:CreateButton("Target them", function() TM:SetBinding(key, "target"); RunRefreshers() end)
        root:CreateButton("None", function() TM:SetBinding(key, "none"); RunRefreshers() end)
    end)
end

local function SpellButton(parent, text, x, y, key)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetPoint("TOPLEFT", x, y)
    fs:SetText(text)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(220, 24)
    b:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
    b:SetScript("OnClick", function(self) ShowSpellMenu(self, key) end)
    AddRefresher(function() b:SetText(BindingText(key)) end)
    return b
end

---------------------------------------------------------------------------
-- One options window, four tabs: General, Advanced, Click Bindings, Extras
---------------------------------------------------------------------------
local win
local pages = {}
local tabs = {}
local spellRows = {}
local LEFT_COL, RIGHT_COL = 130, 276   -- slider centers / right column start

-- General: the classic TauntMaster options
local function BuildGeneralPage(page)
    Slider(page, "Button Width", -12, "width", 50, 200, nil, nil, LEFT_COL)
    Slider(page, "Button Height", -62, "height", 20, 60, nil, nil, LEFT_COL)
    Slider(page, "Units Per Column", -112, "unitsPerColumn", 1, 20, nil, nil, LEFT_COL)
    Slider(page, "Max Columns", -162, "maxColumns", 1, 8, nil, nil, LEFT_COL)
    Slider(page, "Low Mana Warning At", -212, "manaWarnPct", 5, 50, "%",
        function() TM:UpdateManaWarning() end, LEFT_COL)

    SpellButton(page, "Left Click Spell", RIGHT_COL, -8, "1")
    SpellButton(page, "Right Click Spell", RIGHT_COL, -64, "2")

    local small = "GameFontNormalSmall"
    Check(page, "Show Minimap Icon", RIGHT_COL, -122, "minimap", small)
    Check(page, "Lock Frame", RIGHT_COL, -146, "locked", small)
    Check(page, "Hide When Solo", RIGHT_COL, -170, "showSolo", small, true)
    Check(page, "Hide Low Mana Warning", RIGHT_COL, -194, "hideManaWarning", small)

    Label(page, "Taunt Cooldowns:", RIGHT_COL, -230, "GameFontNormal")
    -- Mutually exclusive: checking one unchecks the other (unchecking both hides the icons)
    local onCd = Check(page, "Show On Cooldown", RIGHT_COL, -248, "cdShowOnCooldown", small)
    local ready = Check(page, "Show When Ready", RIGHT_COL, -272, "cdShowWhenReady", small)
    local function exclusive(cb, key, other, otherKey)
        cb:SetScript("OnClick", function(self)
            TM.db[key] = self:GetChecked() and true or false
            if TM.db[key] then
                TM.db[otherKey] = false
                other:SetChecked(false)
            end
            TM:UpdateCooldowns()
        end)
    end
    exclusive(onCd, "cdShowOnCooldown", ready, "cdShowWhenReady")
    exclusive(ready, "cdShowWhenReady", onCd, "cdShowOnCooldown")
end

-- Advanced: display extras, text size, announce
local function BuildAdvancedPage(page)
    Label(page, "Display", 16, -8, "GameFontNormalLarge")
    Check(page, "Show bars", 16, -30, "shown")
    Check(page, "Show in raids", 16, -56, "showInRaid")
    Check(page, "Include yourself", 16, -82, "showPlayer")
    Check(page, "Use class colors for names", 16, -108, "classColors")

    local reset = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    reset:SetSize(140, 22)
    reset:SetPoint("TOPLEFT", 16, -144)
    reset:SetText("Reset position")
    reset:SetScript("OnClick", function() SlashCmdList.TAUNTMASTERFOREVER("reset") end)

    Stepper(page, "Spacing", 270, -32, "spacing", 1, 0, 10, "%d")
    Stepper(page, "Scale", 270, -58, "scale", 0.05, 0.5, 2, "%.2f")

    Label(page, "Text Size", 270, -94, "GameFontNormalLarge")
    Slider(page, "Header", -118, "headerFontSize", 8, 20, nil, function() TM:ApplyFonts() end, 380)
    Slider(page, "Members", -168, "nameFontSize", 8, 20, nil, function() TM:ApplyFonts() end, 380)

    Label(page, "Announce taunts", 16, -218, "GameFontNormalLarge")
    Label(page, "Channel:", 16, -246)
    local chan = Cycle(page, 120, TM.ANNOUNCE_CHANNELS, TM.ANNOUNCE_LABELS,
        function() return TM.db.announceChannel end,
        function(v) TM.db.announceChannel = v; TM:ApplyBindings() end)
    chan:SetPoint("TOPLEFT", 80, -240)
    AddRefresher(chan.Refresh)

    Label(page, "Message:", 16, -276)
    local msg = EditBox(page, 280)
    msg:SetPoint("TOPLEFT", 86, -270)
    msg:SetScript("OnEditFocusLost", function(self)
        TM.db.announceText = self:GetText()
        TM:ApplyBindings()
    end)
    AddRefresher(function() msg:SetText(TM.db.announceText or "") end)

    local note = Label(page,
        "Announce is added to taunts cast on a target and to AoE taunts.\n" ..
        "Say and Yell only work inside instances when sent from a click.",
        16, -302, "GameFontDisableSmall")
    note:SetJustifyH("LEFT")
end

-- Click Bindings: every mouse button + modifier
local function RefreshSpellRows()
    local bindings = TM:GetBindings()
    for _, row in ipairs(spellRows) do
        local bind = bindings[row.key]
        row.kind = bind and bind.kind or "none"
        row.edit:SetText(bind and bind.text or "")
        row.cycle.Refresh()
        local needsText = not (row.kind == "none" or row.kind == "assist" or row.kind == "target")
        row.edit:SetEnabled(needsText)
        row.edit:SetAlpha(needsText and 1 or 0.4)
    end
end

local function SaveSpellRows()
    local bindings = TM:GetBindings()
    for _, row in ipairs(spellRows) do
        if row.kind == "none" then
            bindings[row.key] = nil
        else
            bindings[row.key] = { kind = row.kind, text = row.edit:GetText() or "" }
        end
    end
    TM:ApplyBindings()
    RunRefreshers()
    TM.Print("click bindings saved.")
end

local function BuildBindingsPage(page)
    local header = Label(page, "", 16, -8, "GameFontNormalLarge")
    AddRefresher(function() header:SetText("Click bindings for your " .. (UnitClass("player"))) end)

    Label(page, "Click", 16, -34, "GameFontNormalSmall")
    Label(page, "Action", 110, -34, "GameFontNormalSmall")
    Label(page, "Spell name or macro (use {unit} for the member)", 290, -34, "GameFontNormalSmall")

    local y = -52
    for _, mod in ipairs(TM.MODS) do
        for _, b in ipairs(TM.BUTTONS) do
            local row = { key = mod .. b.id, kind = "none" }
            Label(page, TM.MOD_LABELS[mod] .. b.label, 16, y - 4)
            row.cycle = Cycle(page, 170, TM.KINDS, TM.KIND_LABELS,
                function() return row.kind end,
                function(v)
                    row.kind = v
                    local needsText = not (v == "none" or v == "assist" or v == "target")
                    row.edit:SetEnabled(needsText)
                    row.edit:SetAlpha(needsText and 1 or 0.4)
                end)
            row.cycle:SetPoint("TOPLEFT", 110, y)
            row.edit = EditBox(page, 200)
            row.edit:SetPoint("TOPLEFT", 294, y - 1)
            table.insert(spellRows, row)
            y = y - 25
        end
    end

    local save = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    save:SetSize(100, 22)
    save:SetPoint("TOPLEFT", 16, y - 8)
    save:SetText("Save")
    save:SetScript("OnClick", SaveSpellRows)

    local defaults = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    defaults:SetSize(130, 22)
    defaults:SetPoint("LEFT", save, "RIGHT", 8, 0)
    defaults:SetText("Class defaults")
    defaults:SetScript("OnClick", function()
        TM.db.bindings[TM:PlayerClass()] = TM:DefaultBindings()
        TM:ApplyBindings()
        RunRefreshers()
        TM.Print("click bindings reset to class defaults.")
    end)

    local check = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
    check:SetSize(110, 22)
    check:SetPoint("LEFT", defaults, "RIGHT", 8, 0)
    check:SetText("Check spells")
    check:SetScript("OnClick", function() TM:CheckSpells() end)

    AddRefresher(RefreshSpellRows)
end

-- Extras
local function BuildExtrasPage(page)
    Label(page, "Aggro", 16, -8, "GameFontNormalLarge")
    Check(page, "Play a sound when someone else pulls aggro", 16, -30, "aggroSound")
    Check(page, "Flash their bar while they have aggro", 16, -56, "flashAggro")

    Label(page, "Bars", 16, -94, "GameFontNormalLarge")
    Check(page, "Show health % (replaces the aggro words)", 16, -116, "healthText")
    Check(page, "Fade members out of taunt range", 16, -142, "rangeFade")
    Check(page, "Show role icons", 16, -168, "roleIcons")
    Check(page, "Sort by role: tanks, healers, then damage", 16, -194, "sortByRole")
    local sortNote = Label(page, "Sorting only updates out of combat. In raids, sorts within each group.", 44, -216, "GameFontDisableSmall")
    sortNote:SetJustifyH("LEFT")

    Label(page, "Bar texture:", 16, -242)
    local tex = Cycle(page, 120, TM.TEXTURE_KEYS, TM.TEXTURE_LABELS,
        function() return TM.db.barTexture end,
        function(v) TM.db.barTexture = v; TM:ApplyFonts() end)
    tex:SetPoint("TOPLEFT", 110, -236)
    AddRefresher(tex.Refresh)

    Label(page, "Tanking", 16, -278, "GameFontNormalLarge")
    Check(page, "Show your target's target (click it to taunt your target)", 16, -300, "showToT")
    Check(page, "Only show in Defensive Stance / Bear Form", 16, -326, "tankOnly")
    local tankNote = Label(page, "Paladins have no tank stance, so this does nothing for them.", 44, -348, "GameFontDisableSmall")
    tankNote:SetJustifyH("LEFT")
end

local TAB_ORDER = {
    { key = "general",  label = "General",        build = BuildGeneralPage },
    { key = "advanced", label = "Advanced",       build = BuildAdvancedPage },
    { key = "bindings", label = "Click Bindings", build = BuildBindingsPage },
    { key = "extras",   label = "Extras",         build = BuildExtrasPage },
}

-- Selected tab: normal red button with gold text. Others: greyed-out art and grey text (still clickable).
local function StyleTab(tab, selected)
    local hl = tab:GetHighlightTexture()
    for _, r in ipairs({ tab:GetRegions() }) do
        if r ~= hl and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetDesaturated then
            r:SetDesaturated(not selected)
        end
    end
    tab:SetNormalFontObject(selected and GameFontNormal or GameFontDisable)
    tab:SetHighlightFontObject(GameFontHighlight)
end

local function ShowPage(name)
    for k, p in pairs(pages) do p:SetShown(k == name) end
    for k, t in pairs(tabs) do StyleTab(t, k == name) end
end

local function BuildWindow()
    win = Window("TauntMasterForeverConfig", "TauntMaster Forever Options", 520, 500)

    local prev
    for _, t in ipairs(TAB_ORDER) do
        local tab = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
        tab:SetSize(118, 22)
        if prev then
            tab:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            tab:SetPoint("TOPLEFT", 12, -30)
        end
        tab:SetText(t.label)
        tab:SetScript("OnClick", function() ShowPage(t.key) end)
        tabs[t.key] = tab
        prev = tab

        local p = CreateFrame("Frame", nil, win)
        p:SetPoint("TOPLEFT", 4, -58)
        p:SetPoint("BOTTOMRIGHT", -4, 40)
        pages[t.key] = p
        t.build(p)
    end

    local close = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    close:SetSize(100, 22)
    close:SetPoint("BOTTOMRIGHT", -14, 12)
    close:SetText("Close")
    close:SetScript("OnClick", function() win:Hide() end)

    ShowPage("general")
end

---------------------------------------------------------------------------
-- Entry point: /tm, minimap, header menu
--   nil toggles the window; "display"/"general", "advanced", "spells"/"bindings", "extras" open a tab
---------------------------------------------------------------------------
local PAGE_ALIASES = { display = "general", general = "general", advanced = "advanced",
    spells = "bindings", bindings = "bindings", extras = "extras" }

function TM:OpenConfig(page)
    if not win then BuildWindow() end
    if not page then
        if win:IsShown() then win:Hide() else win:Show() end
        return
    end
    win:Show()
    win:Raise()
    ShowPage(PAGE_ALIASES[page] or "general")
end
