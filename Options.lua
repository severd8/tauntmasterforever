-- TauntMaster Forever: the tabbed options window (/tm).

local _, ns = ...
local TM = ns.TM

-- refreshers repaint every control from the settings (window opened, a setting
-- changed elsewhere); states grey out the controls that don't apply right now
local refreshers, states = {}, {}
local function AddRefresher(fn) table.insert(refreshers, fn) end
local function AddState(fn) table.insert(states, fn) end
local function RunStates() for _, fn in ipairs(states) do fn() end end
local function RunRefreshers()
    for _, fn in ipairs(refreshers) do fn() end
    RunStates()
end

---------------------------------------------------------------------------
-- Widget helpers, in the shared look (Theme.lua)
---------------------------------------------------------------------------
local T = ns.Theme
local C, Fill, Border, Text, FlatButton = T.C, T.Fill, T.Border, T.Text, T.FlatButton
local MenuArrow, Card, MutedNote, RowLabel, Dropdown, FlatEditBox = T.MenuArrow, T.Card, T.Note, T.RowLabel, T.Dropdown, T.EditBox
local SpellKnown, SPELL_KINDS = TM.SpellKnown, TM.SPELL_KINDS

-- Page grid: cards fill the page body exactly, two half cards with a gap between
local PAGE_W = T.WINDOW.W - T.WINDOW.SIDE - 32
local GAP = 10
local HALF_W = (PAGE_W - GAP) / 2
local COL2 = HALF_W + 20      -- second column inside a full-width card
local ROW = 26                -- one switch row
local NOTE_X = 50             -- notes line up under a switch's label

-- Hover help on any control (a title line and a wrapped explanation)
local function Tip(widget, title, body)
    if title or body then T.Tooltip(widget, title, body) end
end

local function Clamp(key, v)
    local r = TM.LIMITS[key]
    if r then v = math.max(r[1], math.min(r[2], v)) end
    return v
end

-- On/off switch bound to a saved setting. o.invert = shows the opposite of the
-- setting; o.onChange(v) runs after saving (default: re-apply all settings);
-- o.tip = hover help.
local function Switch(parent, text, x, y, key, o)
    o = o or {}
    local b, label = T.LabeledSwitch(parent, text, x, y, o.width)
    local function shown()
        local v = TM.db[key] and true or false
        if o.invert then v = not v end
        return v
    end
    local function paint() b:SetOn(shown()) end
    b:SetScript("OnClick", function(self)
        if self.disabled then return end
        local stored = not shown()
        if o.invert then stored = not stored end
        if key == "locked" then
            TM:SetLocked(stored, true)
        elseif key == "shown" then
            TM:SetShown(stored, true)
        else
            TM.db[key] = stored
            if o.onChange then o.onChange(stored) else TM:ApplySettings() end
        end
        paint()
        RunStates()
    end)
    Tip(b, o.tipTitle or text, o.tip)
    b.paint = paint
    AddRefresher(paint)
    return b, label
end

-- Slider bound to a number setting; its range comes from TM.LIMITS. o.onChange()
-- runs after saving (default: lay the bars out again); o.tip = hover help.
local function FlatSlider(parent, text, x, y, width, key, o)
    o = o or {}
    local r = TM.LIMITS[key]
    local s = T.Slider(parent, text, x, y, width,
        function() return TM.db[key] end,
        function(v)
            TM.db[key] = Clamp(key, v)
            if o.onChange then
                o.onChange()
            else
                TM:ApplyFonts()
                TM:Layout()
            end
        end, r[1], r[2], o.suffix, o.step, o.fmt)
    Tip(s, text, o.tip)
    AddRefresher(s.Refresh)
    return s
end

-- Dropdown bound to a choice setting. o.onChange(v) runs after saving.
local function Choice(parent, x, y, width, keys, labels, key, o)
    o = o or {}
    local d = Dropdown(parent, width, keys, labels,
        function() return TM.db[key] end,
        function(v)
            TM.db[key] = v
            if o.onChange then o.onChange(v) end
        end)
    d:SetPoint("TOPLEFT", x, y)
    d.menuLabels = o.menuLabels
    Tip(d, o.tipTitle, o.tip)
    AddRefresher(d.Refresh)
    return d
end

-- A small "Reset" button at the top right of a card: puts these settings back to default
local function ResetButton(card, keys, after)
    local b = FlatButton(card, "Reset", 54, 18)
    b:SetPoint("TOPRIGHT", -8, -6)
    b:SetScript("OnClick", function()
        for _, k in ipairs(keys) do TM.db[k] = TM.DEFAULTS[k] end
        after()
        RunRefreshers()
    end)
    Tip(b, "Reset", "Puts the settings in this box back to their defaults.")
    return b
end

---------------------------------------------------------------------------
-- Spell picker (Left / Right Click Spell)
---------------------------------------------------------------------------
-- A class spell's name in the player's language
local function LocalName(s) return TM:LocalSpellName(s.name, s.id) end

local function SpellLabel(s)
    local name = LocalName(s)
    local info = TM:GetSpellInfo(name)
    local icon = info and info.iconID and ("|T" .. info.iconID .. ":16:16:0:0|t ") or ""
    local label = icon .. name
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
        local info = TM:GetSpellInfo(LocalName(s))
        add(info and info.name or LocalName(s), info and info.iconID)
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

local EditCustomSpell   -- defined with the Click Bindings tab

local function ShowSpellMenu(owner, key)
    local spells = TM:GetClassSpells()
    local current = TM:GetBindings()[key]

    local function isSelected(s)
        return current and current.text == LocalName(s) and current.kind == s.kind
    end
    local function choose(s)
        TM:SetBinding(key, s.kind, LocalName(s))
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
        root:CreateButton("Custom spell...", function() EditCustomSpell(key) end)
        root:CreateButton("Target them", function() TM:SetBinding(key, "target"); RunRefreshers() end)
        root:CreateButton("None", function() TM:SetBinding(key, "none"); RunRefreshers() end)
    end)
end


---------------------------------------------------------------------------
-- Options window state
---------------------------------------------------------------------------
local win
local spellRows = {}
local selectorRefreshers = {}   -- the Taunts tab's spell pickers, repainted when a binding is saved

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

-- Message line beside the Class defaults button: explains the spell box you're
-- working in, lists the boxes that need attention, or gives the macro tips.
local STATUS_MSG = {
    ok = "|cff40ff40%s: %s. Spell found.|r",
    unlearned = "|cffffcc00%s: %s. You haven't learned this spell yet.|r",
    missing = "|cffff4040%s: %s. No spell with this name. Check the spelling.|r",
}
local BINDINGS_HINT = "Changes are saved as you make them. In a macro, {unit} is the clicked player and \\n starts a new line."
local bindingsMsg

local function ShowRowMessage(row)
    if not bindingsMsg then return end
    local status = row.statusState
    if status then
        bindingsMsg:SetText(STATUS_MSG[status]:format(row.label, strtrim(row.edit:GetText() or "")))
    else
        bindingsMsg:SetText(BINDINGS_HINT)
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
        bindingsMsg:SetText(BINDINGS_HINT)
    end
end

-- Saves one row as soon as it changes (no Save button, like every other setting).
-- A spell is saved with the game's exact spelling ("growl" becomes "Growl").
local function SaveRow(row)
    local bindings = TM:GetBindings()
    local new
    if row.kind ~= "none" then
        local text = strtrim(row.edit:GetText() or "")
        if SPELL_KINDS[row.kind] then
            local _, exact = ValidateSpell(text)
            text = exact or text
        end
        new = { kind = row.kind, text = text }
    end
    -- The box shows what was saved (trimmed, the game's spelling) once you've left it
    if new and not row.edit:HasFocus() and row.edit:GetText() ~= new.text then row.edit:SetText(new.text) end
    local old = bindings[row.key]
    local same = (old == nil and new == nil)
        or (old and new and old.kind == new.kind and old.text == new.text)
    if same then return end
    bindings[row.key] = new
    TM:ApplyBindings()
    for _, fn in ipairs(selectorRefreshers) do fn() end
    RunStates()
end

local function SaveAllRows()
    for _, row in ipairs(spellRows) do SaveRow(row) end
end

-- Suggestion list: one shared dropdown that follows whichever spell box you're typing in
local MAX_SUGGEST = 8
local ROW_H = 20
local EDIT_W = 210
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
    SaveRow(row)
end

local function BuildSuggest(parent)
    suggest = CreateFrame("Frame", nil, parent)
    suggest:SetFrameStrata("FULLSCREEN_DIALOG")
    suggest:SetSize(EDIT_W, ROW_H)
    Fill(suggest, C.field)
    Border(suggest, C.fieldEdge)
    suggest.buttons = {}
    for i = 1, MAX_SUGGEST do
        local b = CreateFrame("Button", nil, suggest)
        b:SetSize(EDIT_W - 4, ROW_H)
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
    -- The lower rows open the list upward, so it stays inside the window
    if row.index > #TM.CLICKS / 2 then
        suggest:SetPoint("BOTTOMLEFT", row.edit, "TOPLEFT", 0, 2)
    else
        suggest:SetPoint("TOPLEFT", row.edit, "BOTTOMLEFT", 0, -2)
    end
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

-- Wires a Click Bindings spell box: live status icon + suggestions + keyboard
-- control, and saves when you press Enter or leave the box
local function WireSpellBox(row)
    local eb = row.edit
    eb:SetMaxLetters(255)   -- the game's limit for a macro
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
        if not SuggestOpenFor(row) then SaveRow(row) end
    end)
    eb:SetScript("OnTabPressed", function()
        if SuggestOpenFor(row) then AcceptSuggestion(suggest.matches[suggest.selected]) end
    end)
    eb:SetScript("OnEnterPressed", function(self)
        if SuggestOpenFor(row) then
            AcceptSuggestion(suggest.matches[suggest.selected])
        else
            SaveRow(row)
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
    Tip(eb, row.label .. " click",
        "A spell name, or the macro text for Macro. In a macro, {unit} is the clicked player "
        .. "and \\n starts a new line. Saved when you press Enter or click elsewhere.")
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

local KIND_TIPS = "Spell on their target: the enemy the clicked player has targeted. "
    .. "Spell on them: cast on the clicked player. Spell (no target): AoE taunts and the like. "
    .. "Assist / Target them: no spell needed."

local function BuildBindingsTab(page)
    local card = Card(page, "Mouse buttons and modifiers", 0, 0, PAGE_W, 386)
    local top = -28
    Text(card, "CLICK", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 12, top)
    Text(card, "ACTION", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 100, top)
    Text(card, "SPELL OR MACRO", "GameFontNormalSmall", C.orange):SetPoint("TOPLEFT", 284, top)

    local y = top - 18
    for i, click in ipairs(TM.CLICKS) do
        local row = { key = click.key, kind = "none", label = click.label, page = card, index = i }
        RowLabel(card, click.label, 12, y)
        row.cycle = Dropdown(card, 172, TM.KINDS, TM.KIND_LABELS,
            function() return row.kind end,
            function(v)
                SetRowKind(row, v)
                UpdateRowStatus(row)
                HideSuggest()
                SaveRow(row)
                ShowRowMessage(row)
            end)
        row.cycle:SetPoint("TOPLEFT", 100, y)
        Tip(row.cycle, row.label .. " click", KIND_TIPS)
        row.edit = FlatEditBox(card, EDIT_W)
        row.edit:SetPoint("TOPLEFT", 284, y)
        row.status = StatusIcon(card)
        row.status:SetPoint("LEFT", row.edit, "RIGHT", 6, 0)
        WireSpellBox(row)
        table.insert(spellRows, row)
        y = y - 25
    end

    -- Class defaults asks for a second click, so one stray click can't wipe your bindings
    local defaults = FlatButton(card, "Class defaults", 130)
    defaults:SetPoint("TOPLEFT", 12, y - 8)
    defaults:SetScript("OnClick", function(self)
        if self.armed then
            self.armed = nil
            self:SetText("Class defaults")
            TM.db.bindings[TM:PlayerClass()] = TM:DefaultBindings()
            TM:ApplyBindings()
            RunRefreshers()
            TM.Print("click bindings reset to class defaults.")
        else
            -- Armed for 4 seconds; the token makes sure only the latest timer disarms it
            local token = {}
            self.armed = token
            self:SetText("Click again")
            C_Timer.After(4, function()
                if self.armed == token then
                    self.armed = nil
                    self:SetText("Class defaults")
                end
            end)
        end
    end)
    Tip(defaults, "Class defaults", "Replaces all twelve clicks with your class's defaults. Click twice to confirm.")

    bindingsMsg = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bindingsMsg:SetPoint("LEFT", defaults, "RIGHT", 12, 0)
    bindingsMsg:SetPoint("RIGHT", card, "RIGHT", -12, 0)
    bindingsMsg:SetJustifyH("LEFT")
    bindingsMsg:SetText(BINDINGS_HINT)
    TM._bindingsMsg = bindingsMsg

    AddRefresher(RefreshSpellRows)
end

---------------------------------------------------------------------------
-- Tabs. Each builds its page from cards on the page grid (PAGE_W wide,
-- T.WINDOW.BODY_H tall).
---------------------------------------------------------------------------
-- What a Left / Right Click choice does, shown under its picker
local KIND_NOTES = {
    enemy = "Cast on the clicked player's target.",
    friend = "Cast on the clicked player.",
    self = "Cast with no target.",
    macro = "Runs your macro.",
    assist = "Assists the clicked player.",
    target = "Targets the clicked player.",
    none = "Does nothing.",
}

-- Spell picker styled like a dropdown, with the spell's icon and a note
-- saying what the click does
local function SpellSelector(card, key, title)
    local b = CreateFrame("Button", nil, card)
    b:SetSize(HALF_W - 24, 32)
    b:SetPoint("TOPLEFT", 12, -30)
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
    Tip(b, title, "Pick a taunt, another spell, or Target them. "
        .. "Shift, Ctrl, Alt and middle clicks are on the Click Bindings tab.")
    local note = MutedNote(card, "", 12, -70, HALF_W - 24)
    local function refresh()
        b:SetText(BindingText(key))
        local bind = TM:GetBindings()[key]
        local info = bind and TM:GetSpellInfo(bind.text)
        icon:SetTexture(info and info.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
        note:SetText(KIND_NOTES[bind and bind.kind or "none"] or "")
    end
    AddRefresher(refresh)
    table.insert(selectorRefreshers, refresh)
    return b
end

-- Whether the Right Click spell can back up the Left Click one: both cast on
-- the player's target, and they're different spells
local function CanBackUp()
    local b = TM:GetBindings()
    local l, r = b["1"], b["2"]
    return l and r and l.kind == "enemy" and r.kind == "enemy" and l.text ~= "" and r.text ~= ""
        and l.text:lower() ~= r.text:lower() or false
end

local function BuildTauntsTab(p)
    SpellSelector(Card(p, "Left click", 0, 0, HALF_W, 118), "1", "Left click")
    local right = Card(p, "Right click", HALF_W + GAP, 0, HALF_W, 118)
    SpellSelector(right, "2", "Right click")
    local backup = Switch(right, "Backup when Left is on cooldown", 12, -90, "backupOnCooldown",
        { onChange = function() TM:ApplyBindings(); TM:UpdateCooldowns() end,
          tip = "When the Left Click taunt can't be cast (on cooldown, or out of its range), a Left Click "
            .. "casts this spell instead. Both clicks must be a spell on their target, like Taunt and Mocking Blow." })
    AddState(function() backup:SetDisabled(not CanBackUp()) end)

    local ann = Card(p, "Announcements", 0, -128, PAGE_W, 124)
    RowLabel(ann, "Channel", 12, -30)
    Choice(ann, 120, -28, 170, TM.ANNOUNCE_CHANNELS, TM.ANNOUNCE_LABELS, "announceChannel",
        { tipTitle = "Channel", tip = "Where to say it when your taunt lands. Off sends nothing." })
    local test = FlatButton(ann, "Test", 60)
    test:SetPoint("TOPLEFT", 300, -28)
    test:SetScript("OnClick", function()
        if TM.db.announceChannel == "none" then
            TM.Print("announcements are off. Pick a channel first.")
            return
        end
        local text = TM:FormatAnnounce(TM.db.announceText, "Defias Thug", "Aeri")
        TM.Print("in " .. (TM.ANNOUNCE_LABELS[TM.db.announceChannel] or "chat") .. " this would say: " .. text)
    end)
    Tip(test, "Test", "Shows the message in your own chat window, with sample names. Nothing is sent.")
    RowLabel(ann, "Message", 12, -58)
    local msg = FlatEditBox(ann, PAGE_W - 132)
    msg:SetPoint("TOPLEFT", 120, -56)
    msg:SetMaxLetters(200)
    -- Saved as you type, so closing the window mid-edit keeps the text; an empty
    -- message goes back to the default when you leave the box
    msg:SetScript("OnTextChanged", function(self, userInput)
        if userInput then TM.db.announceText = self:GetText() end
    end)
    local function restoreIfEmpty(self)
        if (self:GetText() or ""):match("^%s*$") then
            TM.db.announceText = TM.DEFAULTS.announceText
            self:SetText(TM.db.announceText)
        end
    end
    msg:SetScript("OnEditFocusLost", restoreIfEmpty)
    msg:SetScript("OnEnterPressed", function(self) restoreIfEmpty(self); self:ClearFocus() end)
    Tip(msg, "Message", "{target} is the mob, {player} the player you saved. Leave it empty to go back to the default.")
    AddRefresher(function() msg:SetText(TM.db.announceText or "") end)
    MutedNote(ann, "Sent only when a taunt you clicked on a bar lands. Say and Yell only work inside "
        .. "instances. Raid Warning needs leader or assist; otherwise it goes to Raid.", 120, -84, PAGE_W - 132)

    local more = Card(p, "More ways to taunt", 0, -262, PAGE_W, 130)
    Switch(more, "Show your target's target bar", 12, -30, "showToT",
        { tip = "A bar for whoever your target is attacking, above the cooldown icons." })
    MutedNote(more, "Shows who your target is hitting. Click it to taunt your own target.", NOTE_X, -52)
    Switch(more, "Backup taunt when they have no enemy targeted", 12, -78, "tauntFallback",
        { tip = "Healers often target the player they heal, so there's no enemy to taunt off them." })
    MutedNote(more, "If they're targeting a friend (like a healer targeting who they heal), taunts what "
        .. "that friend is fighting instead. Not always the mob that's on them.", NOTE_X, -100, PAGE_W - NOTE_X - 12)
end

local function BuildLayoutTab(p)
    local size = Card(p, "Size", 0, 0, PAGE_W, 184)
    local lx, rx, sw = 12, COL2, HALF_W - 20
    FlatSlider(size, "Bar width", lx, -30, sw, "width")
    FlatSlider(size, "Bar height", lx, -76, sw, "height")
    FlatSlider(size, "Bars per column", lx, -122, sw, "unitsPerColumn", { tip = "Party bars start a new column after "
        .. "this many. In a raid, each raid group is its own column; under 5 turns the groups into rows." })
    FlatSlider(size, "Raid groups shown", rx, -30, sw, "maxColumns",
        { tip = "How many raid groups get bars, from group 1 up. Party bars are never cut off." })
    FlatSlider(size, "Spacing", rx, -76, sw, "spacing", { tip = "The gap between bars." })
    -- Scale is saved as a factor (1.25) and shown as a percentage (125%)
    local scale = T.Slider(size, "Scale", rx, -122, sw,
        function() return math.floor(TM.db.scale * 100 + 0.5) end,
        function(v)
            TM.db.scale = Clamp("scale", v / 100)
            TM:Layout()
        end, TM.LIMITS.scale[1] * 100, TM.LIMITS.scale[2] * 100, "%", 5)
    Tip(scale, "Scale", "The size of the whole bar group, header and icons included.")
    AddRefresher(scale.Refresh)
    MutedNote(size, "Changes made during a fight apply when it ends.", 12, -162)
    ResetButton(size, { "width", "height", "unitsPerColumn", "maxColumns", "spacing", "scale" }, function()
        TM:ApplyFonts(); TM:Layout()
    end)

    local vis = Card(p, "Visibility & order", 0, -194, PAGE_W, 180)
    Switch(vis, "Show the bars", 12, -30, "shown",
        { tip = "Same as /tm show and /tm hide, or right-clicking the minimap button." })
    Switch(vis, "Lock bars", 12, -30 - ROW, "locked",
        { tip = "Stops the header from being dragged. Right-click the header to lock or unlock too." })
    Switch(vis, "Include yourself", 12, -30 - 2 * ROW, "showPlayer", { tip = "Shows a bar for you, in a party and in a raid." })
    Switch(vis, "Show raid bars", 12, -30 - 3 * ROW, "showInRaid",
        { tip = "Off: in a raid you see only the bars of your own party (your raid group)." })
    Switch(vis, "Hide when solo", COL2, -30, "showSolo", { invert = true, tip = "Hides everything until you join a group." })
    local tank = Switch(vis, "Only in tank stance or form", COL2, -30 - ROW, "tankOnly",
        { tip = "Shows the bars only in Defensive Stance (Warriors) or Bear Form (Druids). Other classes have no tank stance." })
    AddState(function() tank:SetDisabled(not TM:HasTankStance()) end)
    Switch(vis, "Sort by role", COL2, -30 - 2 * ROW, "sortByRole",
        { tip = "Tanks first, then healers, then damage, when the game has given out roles." })
    Switch(vis, "Pet bars", COL2, -30 - 3 * ROW, "showPets",
        { tip = "Bars for your pet and your party's pets, in a column after the party bars. Click one to taunt "
            .. "what the pet is fighting. Pets often hold mobs on purpose, so their bars don't flash." })
    local reset = FlatButton(vis, "Reset position", 130)
    reset:SetPoint("TOPLEFT", 12, -142)
    reset:SetScript("OnClick", function() SlashCmdList.TAUNTMASTERFOREVER("reset") end)
    Tip(reset, "Reset position", "Moves the bars back to where they start. Same as /tm reset.")
    local preview = FlatButton(vis, "Preview bars", 130)
    preview:SetPoint("LEFT", reset, "RIGHT", 8, 0)
    preview:SetScript("OnClick", function(self)
        TM:SetPreview(not TM.previewOn)
        self:SetText(TM.previewOn and "Hide preview" or "Preview bars")
    end)
    Tip(preview, "Preview bars", "Shows sample party bars where yours go, so you can set their size while solo. "
        .. "They go away when you close the options.")
    AddRefresher(function() preview:SetText(TM.previewOn and "Hide preview" or "Preview bars") end)
end

-- Sample aggro words in each palette's colors, for the Aggro colors menu
local PALETTE_MENU = {
    standard = "Standard   |cffffe600High|r  |cffff8000Aggro|r  |cffe60d0dAGGRO|r",
    colorblind = "Colorblind-friendly   |cff57b5e8High|r  |cffe69900Aggro|r  |cffcc4dbfAGGRO|r",
}

local function BuildAppearanceTab(p)
    local bars = Card(p, "Bars", 0, 0, PAGE_W, 186)
    Switch(bars, "Class colors for names", 12, -30, "classColors")
    Switch(bars, "Role icons", 12, -30 - ROW, "roleIcons",
        { tip = "Tank, healer or damage icon before the name, when the game has given out roles." })
    Switch(bars, "Health % instead of aggro words", 12, -30 - 2 * ROW, "healthText",
        { tip = "The right side of a bar shows the player's health instead of High / Aggro / AGGRO." })
    local word = Switch(bars, "Aggro word with the health %", 12, -30 - 3 * ROW, "aggroWithHealth",
        { tip = "Like \"AGGRO 64%\". Needs \"Health % instead of aggro words\"." })
    AddState(function() word:SetDisabled(not TM.db.healthText) end)
    Switch(bars, "Fade bars your taunt can't reach", 12, -30 - 4 * ROW, "rangeFade",
        { tip = "A bar fades when your Left Click taunt can't reach the player's target." })
    Switch(bars, "Red X when they have no enemy targeted", 12, -30 - 5 * ROW, "noTargetMark",
        { tip = "A red X beside a bar means there's nothing for a click to taunt." })
    RowLabel(bars, "Bar texture", COL2, -30)
    Choice(bars, COL2 + 100, -28, 142, TM.TEXTURE_KEYS, TM.TEXTURE_LABELS, "barTexture",
        { onChange = function() TM:ApplyFonts(); TM:UpdatePreview() end, tipTitle = "Bar texture",
          tip = "The look of the colored bars." })
    RowLabel(bars, "Aggro colors", COL2, -62)
    Choice(bars, COL2 + 100, -60, 142, TM.THREAT_PALETTE_KEYS, TM.THREAT_PALETTE_LABELS, "threatColors",
        { onChange = function() TM:RefreshAll(); TM:UpdatePreview() end, menuLabels = PALETTE_MENU,
          tipTitle = "Aggro colors", tip = "Standard: yellow, orange, red. Colorblind-friendly: sky blue, orange, purple." })
    Switch(bars, "Mob count", COL2, -96, "mobCount",
        { onChange = function() TM:UpdateMobCounts() end,
          tip = "\"x3\" on a player's bar when three enemies are attacking them. Counts enemies whose nameplates "
            .. "are on screen (V key). Inside dungeons the game often hides who a mob is attacking." })

    local text = Card(p, "Text size", 0, -196, PAGE_W, 80)
    FlatSlider(text, "Header", 12, -30, HALF_W - 20, "headerFontSize",
        { onChange = function() TM:ApplyFonts() end, tip = "The name in the red header above the bars." })
    FlatSlider(text, "Bar text", COL2, -30, HALF_W - 20, "nameFontSize",
        { onChange = function() TM:ApplyFonts() end, tip = "Names, aggro words, health %, low mana and keybinding hints." })
    ResetButton(text, { "headerFontSize", "nameFontSize" }, function() TM:ApplyFonts() end)

    local cd = Card(p, "Taunt cooldowns", 0, -286, PAGE_W, 92)
    RowLabel(cd, "Icons", 12, -30)
    Choice(cd, 120, -28, 150, TM.CD_MODE_KEYS, TM.CD_MODE_LABELS, "cdMode",
        { onChange = function() TM:UpdateCooldowns() end, tipTitle = "Taunt cooldown icons",
          tip = "Icons for your Left and Right Click spells, above the header." })
    FlatSlider(cd, "Icon size", COL2, -30, HALF_W - 20, "cdIconSize")
    Switch(cd, "Dim the bars while it's on cooldown", 12, -62, "cdOnBars",
        { onChange = function() TM:UpdateCooldowns() end,
          tip = "While your Left Click taunt is on cooldown, the bars darken and say CD, so you know a click "
            .. "won't land. With the Right Click backup on, only when both are on cooldown." })
end

local function BuildAlertsTab(p)
    local aggro = Card(p, "Aggro", 0, 0, PAGE_W, 222)
    Switch(aggro, "Flash a player's bar when they pull aggro", 12, -30, "flashAggro",
        { tip = "For anyone but you and other tanks, from orange (being attacked)." })
    Switch(aggro, "Warn when you lose aggro on your target", 12, -30 - ROW, "lostAggro",
        { onChange = function() TM:CheckLostAggro() end,
          tip = "When a mob you were tanking turns to someone else, the header flashes and names who has it "
            .. "now, like \"Lost aggro: Aeri\", and their bar gets a gold outline." })
    Switch(aggro, "Warn when you're out of tank stance, form or seal", 12, -30 - 2 * ROW, "stanceWarn",
        { onChange = function() TM:UpdateHeader() end,
          tip = "In a group, the header says \"No Defensive Stance\", \"No Bear Form\" or \"No Seal of Fury\" "
            .. "(Judgement only taunts with it) until you fix it." })
    Switch(aggro, "Play a sound", 12, -30 - 3 * ROW, "aggroSound",
        { tip = "When a player pulls aggro (see below), and with the lost aggro warning." })
    RowLabel(aggro, "Sound", 12, -138)
    Choice(aggro, 150, -136, 150, TM.AGGRO_SOUND_KEYS, TM.AGGRO_SOUND_LABELS, "aggroSoundKey",
        { onChange = function() TM:TestAggroSound() end, tipTitle = "Sound", tip = "Picking one plays it." })
    local test = FlatButton(aggro, "Test", 60)
    test:SetPoint("TOPLEFT", 306, -136)
    test:SetScript("OnClick", function() TM:TestAggroSound() end)
    Tip(test, "Test", "Plays the sound.")
    RowLabel(aggro, "Play it when", 12, -166)
    Choice(aggro, 150, -164, 216, TM.AGGRO_LEVEL_KEYS, TM.AGGRO_LEVEL_LABELS, "aggroSoundLevel",
        { tipTitle = "Play it when", tip = "How much aggro a player needs before the sound plays. The flash always starts at orange." })
    RowLabel(aggro, "Sound channel", 12, -194)
    Choice(aggro, 150, -192, 150, TM.SOUND_CHANNEL_KEYS, TM.SOUND_CHANNEL_LABELS, "aggroSoundChannel",
        { onChange = function() TM:TestAggroSound() end, tipTitle = "Sound channel",
          tip = "Which of the game's volume sliders the sound follows." })

    local mana = Card(p, "Low mana", 0, -232, PAGE_W, 72)
    Switch(mana, "Show a low mana warning", 12, -30, "hideManaWarning",
        { invert = true, onChange = function() TM:UpdateManaWarning() end,
          tip = "Shown beside the bar of a player who's low on mana." })
    MutedNote(mana, "For you, and your healers (everyone with mana when no one has the healer role).", NOTE_X, -52)
    local warnAt = FlatSlider(mana, "Warn at", COL2, -30, HALF_W - 20, "manaWarnPct",
        { suffix = "%", onChange = function() TM:UpdateManaWarning() end })
    AddState(function() warnAt:SetDisabled(TM.db.hideManaWarning) end)

    local plates = Card(p, "Nameplates", 0, -314, PAGE_W, 72)
    Switch(plates, "Mark mobs attacking your healers and damage dealers", 12, -30, "nameplateMarks",
        { onChange = function() TM:UpdatePlateMarks() end,
          tip = "The logo over an enemy that's attacking anyone in your group but you and other tanks." })
    MutedNote(plates, "Target the marked mob, then taunt it. Enemy nameplates must be on (V key).", NOTE_X, -52)
end

local function BuildGeneralTab(p)
    local keys = Card(p, "Controller & keybindings", 0, 0, PAGE_W, 90)
    Switch(keys, "Show keybinding hints beside party bars", 12, -30, "keyHints")
    MutedNote(keys, "Set keys or controller buttons in Options > Keybindings > TauntMaster Forever. "
        .. "In raids, use Mouseover or Targeted ally.", NOTE_X, -52, PAGE_W - NOTE_X - 12)

    local other = Card(p, "Other", 0, -100, PAGE_W, 136)
    Switch(other, "Show minimap button", 12, -30, "minimap",
        { tip = "Left-click it for these options, right-click to show or hide the bars." })
    Switch(other, "Show welcome screen after updates", 12, -30 - ROW, "showSplash",
        { onChange = function() end, tip = "What's new, once after each update. /tm news shows it anytime." })
    -- Not a saved setting itself: it picks which settings this character uses
    local own = T.LabeledSwitch(other, "This character uses its own settings", 12, -30 - 2 * ROW)
    own:SetScript("OnClick", function()
        TM:SetOwnSettings(not TM:UsesOwnSettings())
        RunRefreshers()
    end)
    Tip(own, "This character uses its own settings", "Off: all your characters share one set of settings.")
    AddRefresher(function() own:SetOn(TM:UsesOwnSettings()) end)
    MutedNote(other, "Starts as a copy of your shared settings. Click bindings are kept for each class either way.",
        NOTE_X, -104, PAGE_W - NOTE_X - 12)

    local cmds = Card(p, "Commands", 0, -246, PAGE_W, 134)
    local half = math.ceil(#TM.COMMANDS / 2)
    for i, c in ipairs(TM.COMMANDS) do
        local col, row = (i <= half) and 0 or 1, (i - 1) % half
        local fs = Text(cmds, "|cff8fd3ff" .. c[1] .. "|r  " .. c[2], "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12 + col * (COL2 - 12), -28 - row * 17)
    end
end

-- Share: your settings as one line of text, and back
local function BuildShareTab(p)
    local out = Card(p, "Copy your settings", 0, 0, PAGE_W, 116)
    MutedNote(out, "Your settings and click bindings (for every class) as one line of text. Click Select, "
        .. "press Ctrl+C, then paste it on another character or send it to a friend.", 12, -28, PAGE_W - 24)
    local outBox = FlatEditBox(out, PAGE_W - 24 - 98)
    outBox:SetPoint("TOPLEFT", 12, -68)
    outBox:SetMaxLetters(0)
    Tip(outBox, "Settings text", "Press Ctrl+C to copy it once it's selected.")
    local copy = FlatButton(out, "Select", 90)
    copy:SetPoint("LEFT", outBox, "RIGHT", 8, 0)
    copy:SetScript("OnClick", function()
        outBox:SetText(TM:ExportSettings())
        outBox:SetFocus()
        outBox:HighlightText()
    end)
    Tip(copy, "Select", "Selects the text, ready for Ctrl+C.")
    outBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    -- The box always shows your current settings: typing in it changes nothing
    outBox:SetScript("OnTextChanged", function(self, userInput)
        if userInput then self:SetText(TM:ExportSettings()); self:HighlightText() end
    end)
    AddRefresher(function() outBox:SetText(TM:ExportSettings()) end)

    local inCard = Card(p, "Use shared settings", 0, -126, PAGE_W, 136)
    MutedNote(inCard, "Paste the text (Ctrl+V), then click Use twice. It replaces your settings and the click "
        .. "bindings it has. Where the bars sit stays as it is.", 12, -28, PAGE_W - 24)
    local inBox = FlatEditBox(inCard, PAGE_W - 24 - 98)
    inBox:SetPoint("TOPLEFT", 12, -68)
    inBox:SetMaxLetters(0)
    Tip(inBox, "Shared settings", "Paste settings text from TauntMaster Forever here.")
    local msg = MutedNote(inCard, "", 12, -100, PAGE_W - 24)
    local use = FlatButton(inCard, "Use", 90)
    use:SetPoint("LEFT", inBox, "RIGHT", 8, 0)
    -- Asks for a second click, like Class defaults
    use:SetScript("OnClick", function(self)
        local text = inBox:GetText() or ""
        if text:match("^%s*$") then
            msg:SetText("|cffffcc00Paste settings text in the box first.|r")
            return
        end
        if not self.armed then
            local token = {}
            self.armed = token
            self:SetText("Click again")
            msg:SetText("This replaces your settings. Click again to use them.")
            C_Timer.After(4, function()
                if self.armed == token then self.armed = nil; self:SetText("Use") end
            end)
            return
        end
        self.armed = nil
        self:SetText("Use")
        local ok, err = TM:ImportSettings(text)
        if ok then
            inBox:SetText("")
            RunRefreshers()
            msg:SetText("|cff40ff40Settings applied.|r")
            TM.Print("shared settings applied.")
        else
            msg:SetText("|cffff4040" .. err .. "|r")
        end
    end)
    Tip(use, "Use", "Replaces your settings with the pasted ones. Click twice to confirm.")
    AddRefresher(function() msg:SetText("") end)
    TM._share = { outBox = outBox, copy = copy, inBox = inBox, use = use, msg = msg }
end

local TABS = {
    { key = "taunts",     label = "Taunts",         icon = "Interface\\Icons\\Ability_Physical_Taunt",     build = BuildTauntsTab },
    { key = "bindings",   label = "Click Bindings", icon = "Interface\\Icons\\INV_Misc_Note_01",           build = BuildBindingsTab },
    { key = "layout",     label = "Layout",         icon = "Interface\\Icons\\INV_Misc_Spyglass_03",       build = BuildLayoutTab },
    { key = "appearance", label = "Appearance",     icon = "Interface\\Icons\\INV_Fabric_Silk_02",         build = BuildAppearanceTab },
    { key = "alerts",     label = "Alerts",         icon = "Interface\\Icons\\Ability_Warrior_BattleShout", build = BuildAlertsTab },
    { key = "general",    label = "General",        icon = "Interface\\Icons\\INV_Misc_Gear_01",           build = BuildGeneralTab },
    { key = "share",      label = "Share",          icon = "Interface\\Icons\\INV_Scroll_03",              build = BuildShareTab },
}

local pages, tabButtons = {}, {}   -- filled when the window is built

local function BuildWindow()
    win = T.Window({
        name = "TauntMasterForeverConfig",
        tabs = TABS,
        hint = "/tm opens these options. /tm news shows what's new.",
        version = function() return TM.CurrentNewsVersion and TM:CurrentNewsVersion() end,
        onShow = RunRefreshers,
        onHide = function()
            HideSuggest()
            SaveAllRows()        -- a spell box still being typed in
            TM:SetPreview(false)
        end,
        onTab = HideSuggest,
    })
    for key, page in pairs(win.pages) do pages[key] = page end
    for key, button in pairs(win.tabButtons) do tabButtons[key] = button end
end

-- A setting changed from a command or a menu: repaint the window if it's open
TM.optionsRefresh = function()
    if win and win:IsShown() then RunRefreshers() end
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

-- "Custom spell..." in the spell picker: opens that click's row on the Click
-- Bindings tab, ready to type in, with the same autocomplete and spell check
EditCustomSpell = function(key)
    TM:OpenConfig("bindings")
    for _, row in ipairs(spellRows) do
        if row.key == key then
            if not SPELL_KINDS[row.kind] then
                SetRowKind(row, "enemy")
                row.cycle.Refresh()
                UpdateRowStatus(row)
            end
            row.edit:SetFocus()
            if bindingsMsg then
                bindingsMsg:SetText("Type a spell for " .. row.label .. " and press Enter.")
            end
        end
    end
end

TM._spellRows = spellRows
TM._suggest = function() return suggest end
TM._tabs = { show = function(key) win:ShowTab(key) end, current = function() return win.currentTab end,
    pages = pages, buttons = tabButtons }
