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







---------------------------------------------------------------------------
-- Shared look (Theme.lua)
---------------------------------------------------------------------------
local T = ns.Theme
local C, Fill, Border, Text, FlatButton = T.C, T.Fill, T.Border, T.Text, T.FlatButton

-- Card: a panel with a small orange uppercase title. Content starts at y = -28.
local function Card(parent, title, x, y, w, h)
    local f = CreateFrame("Frame", nil, parent)
    f:SetPoint("TOPLEFT", x, y)
    f:SetSize(w, h)
    Fill(f, C.card)
    Border(f, C.line)
    local t = Text(f, title and title:upper() or "", "GameFontNormalSmall", C.orange)
    t:SetPoint("TOPLEFT", 12, -10)
    return f
end

local function MutedNote(parent, text, x, y, width)
    local n = Text(parent, text, "GameFontDisableSmall")
    n:SetPoint("TOPLEFT", x, y)
    if width then n:SetWidth(width); n:SetWordWrap(true) end
    return n
end

local function RowLabel(parent, text, x, y)
    local fs = Text(parent, text, "GameFontHighlight", C.muted)
    fs:SetPoint("TOPLEFT", x, y - 4)
    return fs
end

-- On/off switch. invert = the switch shows the opposite of the saved setting.
-- onChange(v) runs after saving; default re-applies all settings.
local function Switch(parent, text, x, y, key, invert, labelWidth, onChange)
    local b = T.SwitchWidget(parent)
    b:SetPoint("TOPLEFT", x, y)
    local label = Text(parent, text, "GameFontHighlight")
    label:SetPoint("TOPLEFT", b, "TOPRIGHT", 8, 1)
    if labelWidth then label:SetWidth(labelWidth); label:SetWordWrap(true) end

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

-- Dropdown: shows the current choice; click for a menu of options.
local function Dropdown(parent, width, keys, labels, getter, setter)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(width, 22)
    Fill(b, C.field)
    Border(b, C.fieldEdge)
    local fs = Text(b, "", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -20, 0)
    b:SetFontString(fs)
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetVertexColor(0.91, 0.63, 0.25)

    local function label(k) return labels[k] or tostring(k) end
    local function refresh() b:SetText(label(getter())) end
    local function choose(k) setter(k); refresh() end
    b:SetScript("OnClick", function(self)
        if MenuUtil and MenuUtil.CreateContextMenu then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, k in ipairs(keys) do
                    root:CreateRadio(label(k), function() return getter() == k end, function() choose(k) end)
                end
            end)
        else
            -- No menu system: step to the next choice
            local cur, nextIdx = getter(), 1
            for i, k in ipairs(keys) do
                if k == cur then nextIdx = (i % #keys) + 1 break end
            end
            choose(keys[nextIdx])
        end
    end)
    b.Refresh = refresh
    b.Choose = choose
    return b
end

-- Flat slider: label on the left, value on the right, thin track with a gold knob
local function FlatSlider(parent, text, x, y, width, key, min, max, suffix, onChange, step, fmt)
    suffix, step, fmt = suffix or "", step or 1, fmt or "%d"
    local title = Text(parent, text, "GameFontHighlight", C.muted)
    title:SetPoint("TOPLEFT", x, y)
    local value = Text(parent, "", "GameFontNormal")
    value:SetPoint("TOPRIGHT", parent, "TOPLEFT", x + width, y)
    value:SetJustifyH("RIGHT")

    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width, 14)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetHitRectInsets(0, 0, -6, -6)
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetHeight(4)
    track:SetPoint("LEFT"); track:SetPoint("RIGHT")
    track:SetColorTexture(unpack(C.offTrack))
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 14)
    thumb:SetColorTexture(unpack(C.gold))
    s:SetThumbTexture(thumb)
    local fill = s:CreateTexture(nil, "ARTWORK")
    fill:SetHeight(4)
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetPoint("RIGHT", thumb, "CENTER")
    fill:SetColorTexture(0.72, 0.2, 0.11, 1)
    s:SetMinMaxValues(min, max)
    s:SetValueStep(step)
    if s.SetObeyStepsOnDrag then s:SetObeyStepsOnDrag(true) end

    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        if step >= 1 then v = math.floor(v + 0.5) end
        value:SetText(fmt:format(v) .. suffix)
        if TM.db[key] ~= v then
            TM.db[key] = v
            if onChange then
                onChange()
            else
                TM:ApplyFonts()
                TM:RequestLayout()
            end
        end
    end)
    AddRefresher(function()
        s:SetValue(TM.db[key])
        value:SetText(fmt:format(TM.db[key]) .. suffix)
    end)
    return s
end

-- Flat text box
local function FlatEditBox(parent, width)
    local eb = CreateFrame("EditBox", nil, parent)
    eb:SetSize(width, 22)
    eb:SetAutoFocus(false)
    eb:SetFontObject(GameFontHighlightSmall)
    eb:SetTextInsets(6, 6, 0, 0)
    Fill(eb, C.field)
    Border(eb, C.fieldEdge)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    return eb
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

---------------------------------------------------------------------------
-- Spell name validation and autocomplete
---------------------------------------------------------------------------
local SPELL_KINDS = { enemy = true, friend = true, self = true }

-- Returns "ok", "unlearned" or "missing" (nil if the box is empty), plus the
-- game's exact spelling of the name when it was found.
local function ValidateSpell(text)
    text = strtrim(text or "")
    if text == "" then return nil end
    local info = C_Spell and C_Spell.GetSpellInfo(text)
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
        local info = C_Spell and C_Spell.GetSpellInfo(s.name)
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
        row.kind = bind and bind.kind or "none"
        row.edit:SetText(bind and bind.text or "")
        row.cycle.Refresh()
        local needsText = not (row.kind == "none" or row.kind == "assist" or row.kind == "target")
        row.edit:SetEnabled(needsText)
        row.edit:SetAlpha(needsText and 1 or 0.4)
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
    for _, mod in ipairs(TM.MODS) do
        for _, b in ipairs(TM.BUTTONS) do
            local row = { key = mod .. b.id, kind = "none", label = TM.MOD_LABELS[mod] .. b.label }
            RowLabel(page, TM.MOD_LABELS[mod] .. b.label, 0, y)
            row.cycle = Dropdown(page, 172, TM.KINDS, TM.KIND_LABELS,
                function() return row.kind end,
                function(v)
                    row.kind = v
                    local needsText = not (v == "none" or v == "assist" or v == "target")
                    row.edit:SetEnabled(needsText)
                    row.edit:SetAlpha(needsText and 1 or 0.4)
                    UpdateRowStatus(row)
                    HideSuggest()
                end)
            row.cycle:SetPoint("TOPLEFT", 96, y)
            row.page = page
            row.edit = FlatEditBox(page, 200)
            row.edit:SetPoint("TOPLEFT", 280, y)
            row.status = StatusIcon(page)
            row.status:SetPoint("LEFT", row.edit, "RIGHT", 6, 0)
            WireSpellBox(row)
            table.insert(spellRows, row)
            y = y - 25
        end
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
    local arrow = b:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetVertexColor(0.91, 0.63, 0.25)
    b:SetScript("OnClick", function(self) ShowSpellMenu(self, key) end)
    AddRefresher(function()
        b:SetText(BindingText(key))
        local bind = TM:GetBindings()[key]
        local info = bind and bind.text ~= "" and C_Spell and C_Spell.GetSpellInfo(bind.text)
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
    msg:SetScript("OnEditFocusLost", function(self) TM.db.announceText = self:GetText() end)
    AddRefresher(function() msg:SetText(TM.db.announceText or "") end)
    MutedNote(ann, "{target} = the mob, {player} = the player you saved. Sent only when the taunt casts.", 120, -84, PAGE_W - 132)

    local tot = Card(p, "Target's target", 0, -238, PAGE_W, 76)
    Switch(tot, "Show your target's target bar", 12, -30, "showToT")
    MutedNote(tot, "Shows who your target is hitting. Click it to taunt your own target.", 50, -52)
end

local function BuildBindingsTab(p)
    BuildBindingsSection(p, 0)
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
        "|cff8fd3ff/tm news|r  what's new      |cff8fd3ff/tm reset|r  move the bars back to the center",
    }
    for i, l in ipairs(lines) do
        local fs = Text(cmds, l, "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 12, -26 - (i - 1) * 17)
    end
end

local TABS = {
    { key = "taunts",     label = "Taunts",         icon = "Interface\\Icons\\Ability_Physical_Taunt",     build = BuildTauntsTab },
    { key = "bindings",   label = "Click Bindings", icon = "Interface\\Icons\\INV_Misc_Note_01",           build = BuildBindingsTab },
    { key = "layout",     label = "Layout",         icon = "Interface\\Icons\\INV_Misc_Spyglass_03",       build = BuildLayoutTab },
    { key = "appearance", label = "Appearance",     icon = "Interface\\Icons\\INV_Fabric_Silk_02",         build = BuildAppearanceTab },
    { key = "alerts",     label = "Alerts",         icon = "Interface\\Icons\\Ability_Warrior_BattleShout", build = BuildAlertsTab },
    { key = "general",    label = "General",        icon = "Interface\\Icons\\INV_Misc_Gear_01",           build = BuildGeneralTab },
}

local pages, tabButtons = {}, {}
local currentTab

local function ShowTab(key)
    currentTab = key
    for k, page in pairs(pages) do page:SetShown(k == key) end
    for k, b in pairs(tabButtons) do
        local sel = (k == key)
        b.selBg:SetShown(sel)
        b.accent:SetShown(sel)
        b.icon:SetDesaturated(not sel)
        b.icon:SetAlpha(sel and 1 or 0.7)
        local c = sel and C.gold or C.muted
        b.label:SetTextColor(c[1], c[2], c[3])
    end
    HideSuggest()
end

local function BuildWindow()
    local W, H, HEADER, FOOTER, SIDE = 740, 540, 52, 40, 170
    win = CreateFrame("Frame", "TauntMasterForeverConfig", UIParent)
    win:SetSize(W, H)
    win:SetPoint("CENTER")
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:SetScript("OnShow", RunRefreshers)
    win:SetScript("OnHide", HideSuggest)
    win:Hide()
    table.insert(UISpecialFrames, "TauntMasterForeverConfig")
    Fill(win, C.win)
    Border(win, C.edge)

    -- Header: drag to move
    local header = CreateFrame("Frame", nil, win)
    header:SetPoint("TOPLEFT", 1, -1)
    header:SetPoint("TOPRIGHT", -1, -1)
    header:SetHeight(HEADER)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() win:StartMoving() end)
    header:SetScript("OnDragStop", function() win:StopMovingOrSizing() end)
    local hbg = header:CreateTexture(nil, "BACKGROUND")
    hbg:SetAllPoints()
    T.HeaderGradient(hbg)
    local hline = header:CreateTexture(nil, "BORDER")
    hline:SetPoint("BOTTOMLEFT"); hline:SetPoint("BOTTOMRIGHT"); hline:SetHeight(1)
    hline:SetColorTexture(unpack(C.edge))
    local logo = header:CreateTexture(nil, "ARTWORK")
    logo:SetSize(36, 36)
    logo:SetPoint("LEFT", 14, 0)
    logo:SetTexture(T.LOGO)
    local title = Text(header, T.NAME, "GameFontNormalLarge", { 0.95, 0.9, 0.78 }, 18)
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    local ver = Text(header, "", "GameFontNormalSmall", { 0.85, 0.65, 0.35 })
    ver:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 8, 1)
    AddRefresher(function()
        local v = TM.CurrentNewsVersion and TM:CurrentNewsVersion()
        ver:SetText(v and ("v" .. v) or "")
    end)
    local x = FlatButton(header, "X", 24, 24)
    x:SetPoint("RIGHT", -12, 0)
    x:SetScript("OnClick", function() win:Hide() end)

    -- Sidebar tabs
    local side = CreateFrame("Frame", nil, win)
    side:SetPoint("TOPLEFT", 1, -(HEADER + 1))
    side:SetPoint("BOTTOMLEFT", 1, FOOTER + 1)
    side:SetWidth(SIDE)
    Fill(side, C.side)
    local sline = side:CreateTexture(nil, "BORDER")
    sline:SetPoint("TOPRIGHT"); sline:SetPoint("BOTTOMRIGHT"); sline:SetWidth(1)
    sline:SetColorTexture(unpack(C.line))
    for i, t in ipairs(TABS) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDE - 1, 36)
        b:SetPoint("TOPLEFT", 0, -8 - (i - 1) * 36)
        b.selBg = b:CreateTexture(nil, "BACKGROUND")
        b.selBg:SetAllPoints()
        b.selBg:SetColorTexture(0.23, 0.06, 0.04, 1)
        b.accent = b:CreateTexture(nil, "ARTWORK")
        b.accent:SetPoint("TOPLEFT"); b.accent:SetPoint("BOTTOMLEFT"); b.accent:SetWidth(3)
        b.accent:SetColorTexture(0.89, 0.23, 0.13, 1)
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.05)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(18, 18)
        b.icon:SetPoint("LEFT", 16, 0)
        b.icon:SetTexture(t.icon)
        b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        local fs = Text(b, "", "GameFontHighlight")
        fs:SetPoint("LEFT", b.icon, "RIGHT", 10, 0)
        b:SetFontString(fs)
        b.label = fs
        b:SetText(t.label)
        b:SetScript("OnClick", function() ShowTab(t.key) end)
        tabButtons[t.key] = b
    end

    -- Pages
    for _, t in ipairs(TABS) do
        local page = CreateFrame("Frame", nil, win)
        page:SetPoint("TOPLEFT", SIDE + 16, -(HEADER + 14))
        page:SetPoint("BOTTOMRIGHT", -16, FOOTER + 10)
        local pt = Text(page, t.label, "GameFontNormalLarge", C.gold, 17)
        pt:SetPoint("TOPLEFT", 0, 0)
        local body = CreateFrame("Frame", nil, page)
        body:SetPoint("TOPLEFT", 0, -30)
        body:SetPoint("BOTTOMRIGHT")
        t.build(body)
        pages[t.key] = page
    end

    -- Footer
    local foot = CreateFrame("Frame", nil, win)
    foot:SetPoint("BOTTOMLEFT", 1, 1)
    foot:SetPoint("BOTTOMRIGHT", -1, 1)
    foot:SetHeight(FOOTER)
    Fill(foot, C.side)
    local fline = foot:CreateTexture(nil, "BORDER")
    fline:SetPoint("TOPLEFT"); fline:SetPoint("TOPRIGHT"); fline:SetHeight(1)
    fline:SetColorTexture(unpack(C.line))
    local hint = Text(foot, "/tm to open  -  /tm news for what's new", "GameFontDisableSmall")
    hint:SetPoint("LEFT", 14, 0)
    local close = FlatButton(foot, "Close", 90)
    close:SetPoint("RIGHT", -14, 0)
    close:SetScript("OnClick", function() win:Hide() end)

    ShowTab("taunts")
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
    if pages[key] then ShowTab(key) end
end

TM._spellRows = spellRows
TM._suggest = function() return suggest end
TM._tabs = { show = ShowTab, current = function() return currentTab end, pages = pages, buttons = tabButtons }
