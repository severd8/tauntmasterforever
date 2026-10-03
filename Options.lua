-- TauntMaster Forever: the tabbed options window (/tm).

local _, ns = ...
local TM = ns.TM

local refreshers = {}
local function AddRefresher(fn) table.insert(refreshers, fn) end
local function RunRefreshers() for _, fn in ipairs(refreshers) do fn() end end

---------------------------------------------------------------------------
-- Widget helpers, in the shared look (Theme.lua)
---------------------------------------------------------------------------
local T = ns.Theme
local C, Fill, Border, Text, FlatButton = T.C, T.Fill, T.Border, T.Text, T.FlatButton
local MenuArrow, Card, MutedNote, RowLabel, Dropdown, FlatEditBox = T.MenuArrow, T.Card, T.Note, T.RowLabel, T.Dropdown, T.EditBox
local SpellKnown, SPELL_KINDS = TM.SpellKnown, TM.SPELL_KINDS

-- On/off switch. invert = the switch shows the opposite of the saved setting.
-- onChange(v) runs after saving; default re-applies all settings.
local function Switch(parent, text, x, y, key, invert, labelWidth, onChange)
    local b, label = T.LabeledSwitch(parent, text, x, y, labelWidth)

    local function shown()
        local v = TM.db[key] and true or false
        if invert then v = not v end
        return v
    end
    local function paint() b:SetOn(shown()) end
    b:SetScript("OnClick", function()
        local on = not shown()
        local stored = on
        if invert then stored = not on end
        if key == "locked" then
            TM:SetLocked(stored)
        else
            TM.db[key] = stored
            if onChange then onChange(stored) else TM:ApplySettings() end
        end
        paint()
    end)
    b.paint = paint
    AddRefresher(paint)
    return b, label
end

-- Slider bound to a saved setting. onChange() runs after saving; by default the
-- bars are laid out again.
local function FlatSlider(parent, text, x, y, width, key, min, max, suffix, onChange, step, fmt)
    local s = T.Slider(parent, text, x, y, width,
        function() return TM.db[key] end,
        function(v)
            TM.db[key] = v
            if onChange then
                onChange()
            else
                TM:ApplyFonts()
                TM:Layout()
            end
        end, min, max, suffix, step, fmt)
    AddRefresher(s.Refresh)
    return s
end

---------------------------------------------------------------------------
-- Spell picker (Left / Right Click Spell)
---------------------------------------------------------------------------
local function SpellLabel(s)
    local info = TM:GetSpellInfo(s.name)
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

---------------------------------------------------------------------------
-- Spell name validation and autocomplete
---------------------------------------------------------------------------
-- Returns "ok", "unlearned" or "missing" (nil if the box is empty), plus the
-- game's exact spelling of the name when it was found.
local function ValidateSpell(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local info = TM:GetSpellInfo(text)
    if not info then return "missing" end
    if SpellKnown(info.spellID) == false then return "unlearned", info.name end
    return "ok", info.name
end

-- Every castable spell in your spellbook, plus your class's taunts (even if not
-- learned yet), used for suggestions. Rebuilt whenever a spell box gains focus.
local spellCache = {}
local function CollectPlayerSpells()
    local list, seen = {}, {}
    local function add(name, icon)
        if type(name) == "string" and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = { name = name, icon = icon }
        end
    end
    for _, s in ipairs(TM:GetClassSpells()) do
        local info = TM:GetSpellInfo(s.name)
        add(info and info.name or s.name, info and info.iconID)
    end
    pcall(function()
        if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
            local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
            local flyout = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Flyout
            for i = 1, C_SpellBook.GetNumSpellBookSkillLines() do
                local line = C_SpellBook.GetSpellBookSkillLineInfo(i)
                if line then
                    for j = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                        local item = C_SpellBook.GetSpellBookItemInfo(j, bank)
                        if item and not item.isPassive and (not flyout or item.itemType ~= flyout) then
                            add(item.name, item.iconID)
                        end
                    end
                end
            end
        elseif GetNumSpellTabs then
            for t = 1, GetNumSpellTabs() do
                local _, _, offset, num = GetSpellTabInfo(t)
                for i = offset + 1, offset + num do
                    if not (IsPassiveSpell and IsPassiveSpell(i, "spell")) then
                        add(GetSpellBookItemName(i, "spell"), GetSpellBookItemTexture(i, "spell"))
                    end
                end
            end
        end
    end)
    return list
end

-- Names starting with what you typed come first, then names containing it.
local function FindMatches(text, max)
    text = strtrim(text or ""):lower()
    if text == "" then return {} end
    local starts, contains = {}, {}
    for _, s in ipairs(spellCache) do
        local n = s.name:lower()
        if n:sub(1, #text) == text then
            starts[#starts + 1] = s
        elseif n:find(text, 1, true) then
            contains[#contains + 1] = s
        end
    end
    local byName = function(a, b) return a.name < b.name end
    table.sort(starts, byName)
    table.sort(contains, byName)
    local out = {}
    for _, s in ipairs(starts) do if #out < max then out[#out + 1] = s end end
    for _, s in ipairs(contains) do if #out < max then out[#out + 1] = s end end
    return out
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
            local _, exact = ValidateSpell(text)
            TM:SetBinding(data or self.data, "enemy", exact or text)
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
        -- Radio buttons for the taunts, or for the utility spells; true if there were any
        local function radios(utility)
            local any = false
            for _, s in ipairs(spells) do
                if (s.utility or false) == utility then
                    if utility and not any then
                        root:CreateDivider()
                        root:CreateTitle("Utility")
                    end
                    any = true
                    root:CreateRadio(SpellLabel(s), function() return isSelected(s) end, function() choose(s) end)
                end
            end
            return any
        end
        root:CreateTitle("Taunt abilities")
        radios(false)
        if #spells == 0 then
            root:CreateTitle("|cff999999No taunts for your class|r")
        end
        radios(true)
        root:CreateDivider()
        root:CreateButton("Custom spell...", function()
            StaticPopup_Show("TAUNTMASTERFOREVER_CUSTOM", nil, nil, key)
        end)
        root:CreateButton("Target them", function() TM:SetBinding(key, "target"); RunRefreshers() end)
        root:CreateButton("None", function() TM:SetBinding(key, "none"); RunRefreshers() end)
    end)
end


---------------------------------------------------------------------------
-- Options window state
---------------------------------------------------------------------------
local win
local spellRows = {}

-- Click Bindings: every mouse button + modifier
local STATUS_TEX = {
    ok = "Interface\\RaidFrame\\ReadyCheck-Ready",
    unlearned = "Interface\\RaidFrame\\ReadyCheck-Waiting",
    missing = "Interface\\RaidFrame\\ReadyCheck-NotReady",
}
local STATUS_TIP = {
    ok = "Spell found.",
    unlearned = "This spell exists, but you haven't learned it yet.",
    missing = "No spell with this name. Check the spelling.",
}

local function StatusIcon(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(16, 16)
    f.tex = f:CreateTexture(nil, "ARTWORK")
    f.tex:SetAllPoints()
    f:SetScript("OnEnter", function(self)
        if not self.tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    f:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f:Hide()
    return f
end

-- Assist, Target and Nothing need no spell or macro: their text box is greyed out
local function SetRowKind(row, kind)
    row.kind = kind
    local needsText = not TM.NO_TEXT_KINDS[kind]
    row.edit:SetEnabled(needsText)
    row.edit:SetAlpha(needsText and 1 or 0.4)
end

local function UpdateRowStatus(row)
    local status
    if SPELL_KINDS[row.kind] then status = ValidateSpell(row.edit:GetText()) end
    row.statusState = status
    if status then
        row.status.tex:SetTexture(STATUS_TEX[status])
        row.status.tip = STATUS_TIP[status]
        row.status:Show()
    else
        row.status:Hide()
    end
end

-- Message line under the Save button: explains the spell box you're working in,
-- or lists the boxes that need attention when the tab opens.
local STATUS_MSG = {
    ok = "|cff40ff40%s: %s. Spell found.|r",
    unlearned = "|cffffcc00%s: %s. You haven't learned this spell yet.|r",
    missing = "|cffff4040%s: %s. No spell with this name. Check the spelling.|r",
}
local bindingsMsg

local function ShowRowMessage(row)
    if not bindingsMsg then return end
    local status = row.statusState
    if status then
        bindingsMsg:SetText(STATUS_MSG[status]:format(row.label, strtrim(row.edit:GetText() or "")))
    else
        bindingsMsg:SetText("")
    end
end

local function ShowProblemSummary()
    if not bindingsMsg then return end
    local problems = {}
    for _, row in ipairs(spellRows) do
        if row.statusState == "missing" then
            problems[#problems + 1] = row.label .. " (not found)"
        elseif row.statusState == "unlearned" then
            problems[#problems + 1] = row.label .. " (not learned)"
        end
    end
    if #problems > 0 then
        bindingsMsg:SetText("|cffffcc00Check these spells: " .. table.concat(problems, ", ") .. "|r")
    else
        bindingsMsg:SetText("")
    end
end

-- Suggestion list: one shared dropdown that follows whichever spell box you're typing in
local MAX_SUGGEST = 8
local ROW_H = 20
local suggest

local function HideSuggest()
    if suggest then
        suggest:Hide()
        suggest.row = nil
    end
end

local function SuggestOpenFor(row)
    return suggest and suggest:IsShown() and suggest.row == row
end

local function HighlightSuggestion()
    for i, b in ipairs(suggest.buttons) do b.sel:SetShown(i == suggest.selected) end
end

local function AcceptSuggestion(spell)
    local row = suggest and suggest.row
    if not (row and spell) then return end
    row.edit:SetText(spell.name)
    row.edit:SetCursorPosition(#spell.name)
    HideSuggest()
    UpdateRowStatus(row)
    ShowRowMessage(row)
end

local function BuildSuggest(parent)
    suggest = CreateFrame("Frame", nil, parent)
    suggest:SetFrameStrata("FULLSCREEN_DIALOG")
    suggest:SetSize(224, ROW_H)
    Fill(suggest, C.field)
    Border(suggest, C.fieldEdge)
    suggest.buttons = {}
    for i = 1, MAX_SUGGEST do
        local b = CreateFrame("Button", nil, suggest)
        b:SetSize(220, ROW_H)
        b:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
        b.sel = b:CreateTexture(nil, "BACKGROUND")
        b.sel:SetAllPoints()
        b.sel:SetColorTexture(0.55, 0.14, 0.08, 0.6)
        b.sel:Hide()
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.06)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(16, 16)
        b.icon:SetPoint("LEFT", 2, 0)
        b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.text:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
        b.text:SetPoint("RIGHT", -2, 0)
        b.text:SetJustifyH("LEFT")
        b:SetScript("OnClick", function(self) AcceptSuggestion(self.spell) end)
        suggest.buttons[i] = b
    end
    suggest:Hide()
end

local function ShowSuggestions(row)
    if not SPELL_KINDS[row.kind] then HideSuggest() return end
    local text = row.edit:GetText() or ""
    local matches = FindMatches(text, MAX_SUGGEST)
    if #matches == 0 or (#matches == 1 and matches[1].name:lower() == strtrim(text):lower()) then
        HideSuggest()
        return
    end
    if not suggest then BuildSuggest(row.page) end
    suggest.row, suggest.matches, suggest.selected = row, matches, 1
    suggest:ClearAllPoints()
    suggest:SetPoint("TOPLEFT", row.edit, "BOTTOMLEFT", -6, -2)
    for i, b in ipairs(suggest.buttons) do
        local s = matches[i]
        if s then
            b.spell = s
            b.icon:SetTexture(s.icon)
            b.text:SetText(s.name)
            b:Show()
        else
            b.spell = nil
            b:Hide()
        end
    end
    suggest:SetHeight(#matches * ROW_H + 4)
    HighlightSuggestion()
    suggest:Show()
end

-- Wires a Click Bindings spell box: live status icon + suggestions + keyboard control
local function WireSpellBox(row)
    local eb = row.edit
    eb:HookScript("OnTextChanged", function(_, userInput)
        UpdateRowStatus(row)
        if userInput then
            ShowSuggestions(row)
            ShowRowMessage(row)
        end
    end)
    eb:HookScript("OnEditFocusGained", function()
        spellCache = CollectPlayerSpells()
        ShowRowMessage(row)
    end)
    eb:HookScript("OnEditFocusLost", function()
        if SuggestOpenFor(row) and not suggest:IsMouseOver() then HideSuggest() end
    end)
    eb:SetScript("OnTabPressed", function()
        if SuggestOpenFor(row) then AcceptSuggestion(suggest.matches[suggest.selected]) end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        if SuggestOpenFor(row) then
            AcceptSuggestion(suggest.matches[suggest.selected])
        else
            self:ClearFocus()
        end
    end)
    eb:SetScript("OnEscapePressed", function(self)
        if SuggestOpenFor(row) then HideSuggest() else self:ClearFocus() end
    end)
    eb:SetScript("OnArrowPressed", function(_, key)
        if not SuggestOpenFor(row) then return end
        if key == "DOWN" then
            suggest.selected = math.min(#suggest.matches, suggest.selected + 1)
        elseif key == "UP" then
            suggest.selected = math.max(1, suggest.selected - 1)
        end
        HighlightSuggestion()
    end)
end

local function RefreshSpellRows()
    local bindings = TM:GetBindings()
    for _, row in ipairs(spellRows) do
        local bind = bindings[row.key]
        SetRowKind(row, bind and bind.kind or "none")
        row.edit:SetText(bind and bind.text or "")
        row.cycle.Refresh()
        UpdateRowStatus(row)
    end
    HideSuggest()
    ShowProblemSummary()
end

local function SaveSpellRows()
    local bindings = TM:GetBindings()
    for _, row in ipairs(spellRows) do
        if row.kind == "none" then
            bindings[row.key] = nil
        else
            local text = strtrim(row.edit:GetText() or "")
            if SPELL_KINDS[row.kind] then
                -- Save the game's exact spelling ("growl" becomes "Growl")
                local _, exact = ValidateSpell(text)
                text = exact or text
            end
            bindings[row.key] = { kind = row.kind, text = text }
        end
    end
    TM:ApplyBindings()
    RunRefreshers()
    TM.Print("click bindings saved.")
end

local function BuildBindingsSection(page, top)
    Text(page, "CLICK", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 0, top)
    Text(page, "ACTION", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 96, top)
    Text(page, "SPELL NAME OR MACRO  ({unit} = the player)", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 280, top)

    local y = top - 18
    for _, click in ipairs(TM.CLICKS) do
        local row = { key = click.key, kind = "none", label = click.label, page = page }
        RowLabel(page, click.label, 0, y)
        row.cycle = Dropdown(page, 172, TM.KINDS, TM.KIND_LABELS,
            function() return row.kind end,
            function(v)
                SetRowKind(row, v)
                UpdateRowStatus(row)
                HideSuggest()
            end)
        row.cycle:SetPoint("TOPLEFT", 96, y)
        row.edit = FlatEditBox(page, 200)
        row.edit:SetPoint("TOPLEFT", 280, y)
        row.status = StatusIcon(page)
        row.status:SetPoint("LEFT", row.edit, "RIGHT", 6, 0)
        WireSpellBox(row)
        table.insert(spellRows, row)
        y = y - 25
    end

    local save = FlatButton(page, "Save", 100)
    save:SetPoint("TOPLEFT", 0, y - 8)
    save:SetScript("OnClick", SaveSpellRows)

    local defaults = FlatButton(page, "Class defaults", 130)
    defaults:SetPoint("LEFT", save, "RIGHT", 8, 0)
    defaults:SetScript("OnClick", function()
        TM.db.bindings[TM:PlayerClass()] = TM:DefaultBindings()
        TM:ApplyBindings()
        RunRefreshers()
        TM.Print("click bindings reset to class defaults.")
    end)

    local check = FlatButton(page, "Check spells", 110)
    check:SetPoint("LEFT", defaults, "RIGHT", 8, 0)
    check:SetScript("OnClick", function() TM:CheckSpells() end)

    bindingsMsg = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindingsMsg:SetPoint("TOPLEFT", save, "BOTTOMLEFT", 0, -8)
    bindingsMsg:SetPoint("RIGHT", page, "RIGHT", 0, 0)
    bindingsMsg:SetJustifyH("LEFT")
    bindingsMsg:SetText("")
    TM._bindingsMsg = bindingsMsg

    AddRefresher(RefreshSpellRows)
end

---------------------------------------------------------------------------
-- Tabs. Each builds its page and positions cards inside it.
-- Page content area is about 540 x 420.
---------------------------------------------------------------------------
local PAGE_W = 540
local HALF_W = 265

-- Spell picker styled like a dropdown, with the spell's icon
local function SpellSelector(parent, x, y, w, key)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, 32)
    b:SetPoint("TOPLEFT", x, y)
    Fill(b, C.field)
    Border(b, C.fieldEdge)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 22)
    icon:SetPoint("LEFT", 6, 0)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local fs = Text(b, "", "GameFontHighlight")
    fs:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    fs:SetPoint("RIGHT", -20, 0)
    b:SetFontString(fs)
    MenuArrow(b, 8)
    b:SetScript("OnClick", function(self) ShowSpellMenu(self, key) end)
    AddRefresher(function()
        b:SetText(BindingText(key))
        local bind = TM:GetBindings()[key]
        local info = bind and TM:GetSpellInfo(bind.text)
        icon:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
    end)
    return b
end

local function BuildTauntsTab(p)
    local left = Card(p, "Left click", 0, 0, HALF_W, 96)
    SpellSelector(left, 12, -30, HALF_W - 24, "1")
    MutedNote(left, "Taunts the clicked player's target", 12, -70, HALF_W - 24)
    local right = Card(p, "Right click", HALF_W + 10, 0, HALF_W, 96)
    SpellSelector(right, 12, -30, HALF_W - 24, "2")
    MutedNote(right, "More buttons and modifiers: Click Bindings tab", 12, -70, HALF_W - 24)

    local ann = Card(p, "Announcements", 0, -106, PAGE_W, 122)
    RowLabel(ann, "Channel", 12, -30)
    local chan = Dropdown(ann, 170, TM.ANNOUNCE_CHANNELS, TM.ANNOUNCE_LABELS,
        function() return TM.db.announceChannel end,
        function(v) TM.db.announceChannel = v end)
    chan:SetPoint("TOPLEFT", 120, -28)
    AddRefresher(chan.Refresh)
    RowLabel(ann, "Message", 12, -58)
    local msg = FlatEditBox(ann, PAGE_W - 132)
    msg:SetPoint("TOPLEFT", 120, -56)
    -- Saved as you type, so closing the window mid-edit keeps the text
    msg:SetScript("OnTextChanged", function(self, userInput)
        if userInput then TM.db.announceText = self:GetText() end
    end)
    AddRefresher(function() msg:SetText(TM.db.announceText or "") end)
    MutedNote(ann, "{target} = the mob, {player} = the player you saved. Sent only when the taunt casts.", 120, -84, PAGE_W - 132)

    local more = Card(p, "More ways to taunt", 0, -238, PAGE_W, 130)
    Switch(more, "Show your target's target bar", 12, -30, "showToT")
    MutedNote(more, "Shows who your target is hitting. Click it to taunt your own target.", 50, -52)
    Switch(more, "Backup taunt when they have no enemy targeted", 12, -76, "tauntFallback")
    MutedNote(more, "If they're targeting a friend (like a healer targeting who they heal), "
        .. "taunts what that friend is fighting instead. Not always the mob that's on them.", 50, -98, PAGE_W - 62)
end

local function BuildLayoutTab(p)
    local size = Card(p, "Size", 0, 0, PAGE_W, 170)
    local lx, rx, sw = 12, 284, 244
    FlatSlider(size, "Button width", lx, -30, sw, "width", 50, 200)
    FlatSlider(size, "Button height", lx, -76, sw, "height", 20, 60)
    FlatSlider(size, "Units per column", lx, -122, sw, "unitsPerColumn", 1, 20)
    FlatSlider(size, "Max columns", rx, -30, sw, "maxColumns", 1, 8)
    FlatSlider(size, "Spacing", rx, -76, sw, "spacing", 0, 10)
    FlatSlider(size, "Scale", rx, -122, sw, "scale", 0.5, 2, nil, nil, 0.05, "%.2f")

    local vis = Card(p, "Visibility & order", 0, -180, PAGE_W, 150)
    Switch(vis, "Lock frame", 12, -30, "locked")
    Switch(vis, "Include yourself", 12, -56, "showPlayer")
    Switch(vis, "Show in raids", 12, -82, "showInRaid")
    Switch(vis, "Hide when solo", 284, -30, "showSolo", true)
    Switch(vis, "Only in Defensive Stance / Bear Form", 284, -56, "tankOnly", false, 210)
    Switch(vis, "Sort by role", 284, -90, "sortByRole")
    local reset = FlatButton(vis, "Reset position", 130)
    reset:SetPoint("TOPLEFT", 12, -114)
    reset:SetScript("OnClick", function() SlashCmdList.TAUNTMASTERFOREVER("reset") end)
    MutedNote(vis, "Size and position changes wait until combat ends.", 154, -119)
end

local function BuildAppearanceTab(p)
    local names = Card(p, "Bars & names", 0, 0, PAGE_W, 120)
    Switch(names, "Class colors for names", 12, -30, "classColors")
    Switch(names, "Role icons", 12, -56, "roleIcons")
    Switch(names, "Health % instead of aggro words", 12, -82, "healthText")
    RowLabel(names, "Bar texture", 284, -28)
    local tex = Dropdown(names, 140, TM.TEXTURE_KEYS, TM.TEXTURE_LABELS,
        function() return TM.db.barTexture end,
        function(v) TM.db.barTexture = v; TM:ApplyFonts() end)
    tex:SetPoint("TOPLEFT", 380, -28)
    AddRefresher(tex.Refresh)

    local text = Card(p, "Text size", 0, -130, PAGE_W, 80)
    FlatSlider(text, "Header", 12, -30, 244, "headerFontSize", 8, 20, nil, function() TM:ApplyFonts() end)
    FlatSlider(text, "Members", 284, -30, 244, "nameFontSize", 8, 20, nil, function() TM:ApplyFonts() end)
end

local function BuildAlertsTab(p)
    local aggro = Card(p, "Aggro", 0, 0, 330, 170)
    Switch(aggro, "Flash bar while they have aggro", 12, -30, "flashAggro")
    Switch(aggro, "Play a sound", 12, -56, "aggroSound")
    RowLabel(aggro, "Sound", 12, -84)
    local snd = Dropdown(aggro, 130, TM.AGGRO_SOUND_KEYS, TM.AGGRO_SOUND_LABELS,
        function() return TM.db.aggroSoundKey end,
        function(v) TM.db.aggroSoundKey = v; TM:TestAggroSound() end)
    snd:SetPoint("TOPLEFT", 120, -82)
    AddRefresher(snd.Refresh)
    local test = FlatButton(aggro, "Test", 52)
    test:SetPoint("LEFT", snd, "RIGHT", 6, 0)
    test:SetScript("OnClick", function() TM:TestAggroSound() end)
    RowLabel(aggro, "Alert when", 12, -112)
    local lvl = Dropdown(aggro, 188, TM.AGGRO_LEVEL_KEYS, TM.AGGRO_LEVEL_LABELS,
        function() return TM.db.aggroSoundLevel end,
        function(v) TM.db.aggroSoundLevel = v end)
    lvl:SetPoint("TOPLEFT", 120, -110)
    AddRefresher(lvl.Refresh)
    RowLabel(aggro, "Sound channel", 12, -140)
    local ch = Dropdown(aggro, 130, TM.SOUND_CHANNEL_KEYS, TM.SOUND_CHANNEL_LABELS,
        function() return TM.db.aggroSoundChannel end,
        function(v) TM.db.aggroSoundChannel = v; TM:TestAggroSound() end)
    ch:SetPoint("TOPLEFT", 120, -138)
    AddRefresher(ch.Refresh)

    local reach = Card(p, "Reach", 340, 0, 200, 90)
    Switch(reach, "Fade bars your taunt can't reach", 12, -30, "rangeFade", false, 140)
    MutedNote(reach, "Red X = no enemy targeted", 12, -68)

    local mana = Card(p, "Low mana", 340, -100, 200, 70 + 20)
    Switch(mana, "Show warning", 12, -30, "hideManaWarning", true, 140,
        function() TM:UpdateManaWarning() end)
    FlatSlider(mana, "Warn at", 12, -52, 176, "manaWarnPct", 5, 50, "%", function() TM:UpdateManaWarning() end)

    local cd = Card(p, "Taunt cooldown icons", 0, -200, PAGE_W, 84)
    -- Mutually exclusive: turning one on turns the other off (both off hides the icons)
    local onCd, ready
    onCd = Switch(cd, "Show on cooldown", 12, -30, "cdShowOnCooldown", false, nil, function(v)
        if v then TM.db.cdShowWhenReady = false; ready.paint() end
        TM:UpdateCooldowns()
    end)
    ready = Switch(cd, "Show when ready", 12, -56, "cdShowWhenReady", false, nil, function(v)
        if v then TM.db.cdShowOnCooldown = false; onCd.paint() end
        TM:UpdateCooldowns()
    end)
    FlatSlider(cd, "Icon size", 284, -30, 244, "cdIconSize", 16, 64)

    local plates = Card(p, "Nameplates", 0, -294, PAGE_W, 76)
    Switch(plates, "Mark mobs attacking your party on their nameplates", 12, -30, "nameplateMarks",
        false, nil, function() TM:UpdatePlateMarks() end)
    MutedNote(plates, "Target the marked mob, then taunt it. Enemy nameplates must be on (V key).", 50, -52)
end

local function BuildGeneralTab(p)
    local keys = Card(p, "Controller & keybindings", 0, 0, PAGE_W, 76)
    Switch(keys, "Show keybinding hints beside party bars", 12, -30, "keyHints")
    MutedNote(keys, "Set keys or controller buttons in Options > Keybindings > TauntMaster Forever.", 50, -52)

    local other = Card(p, "Other", 0, -86, PAGE_W, 84)
    Switch(other, "Show minimap icon", 12, -30, "minimap")
    Switch(other, "Show welcome screen after updates", 12, -56, "showSplash", false, nil, function() end)

    local cmds = Card(p, "Commands", 0, -180, PAGE_W, 116)
    local lines = {
        "|cff8fd3ff/tm|r  open or close these options",
        "|cff8fd3ff/tm toggle|r  show or hide the bars",
        "|cff8fd3ff/tm lock|r / |cff8fd3ff/tm unlock|r  lock or unlock the bars",
        "|cff8fd3ff/tm check|r  check your bound spells",
        "|cff8fd3ff/tm news|r  what's new      |cff8fd3ff/tm reset|r  reset the bars' position",
    }
    for i, l in ipairs(lines) do
        local fs = Text(cmds, l, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 17)
    end
end

local TABS = {
    { key = "taunts",     label = "Taunts",         icon = "Interface\\Icons\\Ability_Physical_Taunt",     build = BuildTauntsTab },
    { key = "bindings",   label = "Click Bindings", icon = "Interface\\Icons\\INV_Misc_Note_01",           build = function(p) BuildBindingsSection(p, 0) end },
    { key = "layout",     label = "Layout",         icon = "Interface\\Icons\\INV_Misc_Spyglass_03",       build = BuildLayoutTab },
    { key = "appearance", label = "Appearance",     icon = "Interface\\Icons\\INV_Fabric_Silk_02",         build = BuildAppearanceTab },
    { key = "alerts",     label = "Alerts",         icon = "Interface\\Icons\\Ability_Warrior_BattleShout", build = BuildAlertsTab },
    { key = "general",    label = "General",        icon = "Interface\\Icons\\INV_Misc_Gear_01",           build = BuildGeneralTab },
}

local pages, tabButtons = {}, {}   -- filled when the window is built

local function BuildWindow()
    win = T.Window({
        name = "TauntMasterForeverConfig",
        tabs = TABS,
        hint = "/tm to open  -  /tm news for what's new",
        version = function() return TM.CurrentNewsVersion and TM:CurrentNewsVersion() end,
        onShow = RunRefreshers,
        onHide = HideSuggest,
        onTab = HideSuggest,
    })
    for key, page in pairs(win.pages) do pages[key] = page end
    for key, button in pairs(win.tabButtons) do tabButtons[key] = button end
end

---------------------------------------------------------------------------
-- Entry point: /tm, minimap, header menu
--   nil toggles the window; a name opens that tab (older names still work)
---------------------------------------------------------------------------
local TAB_ALIASES = { display = "taunts", spells = "bindings", advanced = "appearance", extras = "alerts" }

function TM:OpenConfig(page)
    if not win then BuildWindow() end
    if not page then
        if win:IsShown() then win:Hide() else win:Show() end
        return
    end
    win:Show()
    win:Raise()
    local key = TAB_ALIASES[page] or page
    if pages[key] then win:ShowTab(key) end
end

TM._spellRows = spellRows
TM._suggest = function() return suggest end
TM._tabs = { show = function(key) win:ShowTab(key) end, current = function() return win.currentTab end,
    pages = pages, buttons = tabButtons }
