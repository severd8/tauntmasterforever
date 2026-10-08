-- Test scenarios for TauntMaster Forever. Run via tests/run.lua (see DEVNOTES.md).
-- Drives TauntMaster Forever through its features. Any Lua error aborts with a traceback.
local ADDON = "TauntMasterForever"
local ns = {}
local function load_file(path)
    local f = assert(io.open(path)) local src = f:read("*a") f:close()
    local chunk = assert(loadstring(src, "@" .. path))
    chunk(ADDON, ns)
end
-- Load files in the same order as the .toc
local tocFile = assert(io.open(ADDON_DIR .. "/TauntMasterForever.toc"))
for line in tocFile:lines() do
    local file = line:match("^([%w_/]+%.lua)%s*$")
    if file then load_file(ADDON_DIR .. "/" .. file) end
end
tocFile:close()
local TM = ns.TM

local function fire(event, ...)
    for _, f in ipairs(ALL_FRAMES) do
        if f.__events and f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
    end
end
local function tick() for _, fn in ipairs(TICKERS) do fn() end end
local function step(name) print("STEP " .. name) end
local function assertEq(a, b, msg) if a ~= b then error(("ASSERT %s: got %s expected %s"):format(msg, tostring(a), tostring(b)), 2) end end

step("load + login")
fire("ADDON_LOADED", ADDON)
fire("PLAYER_LOGIN")
assert(TM.built, "frames not built")
TM.main.__protected = true      -- the game treats these as protected once secure frames hang off them
TM.handle.__protected = true
tick()

-- Login message
local loginMsg
for _, l in ipairs(LOG) do if l:find("loaded%.") then loginMsg = l end end
assert(loginMsg and loginMsg:find("Growl") and loginMsg:find("Left Click") and loginMsg:find("Challenging Roar"), "login message: " .. tostring(loginMsg))

assertEq(TM.db.aggroSound, false, "aggro sound off by default")
TM.db.aggroSound = true
step("macros")
local pb = TM.unitToButton.party1
assertEq(pb.__attrs.type1, "macro", "party1 type1")
assertEq(pb.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "party1 macro1")
assertEq(pb.__attrs.macrotext2, "/cast Challenging Roar", "party1 macro2")
assertEq(pb.__attrs["ctrl-type1"], "assist", "ctrl assist")
assertEq(pb.__attrs.type3, "target", "middle target")
local tot = TM.totButton
assertEq(tot.__attrs.macrotext1, "/cast [@target,harm,nodead] Growl", "ToT macro taunts your own target")

step("visibility drivers")
assertEq(TM.main.__driver, "show", "main driver default")
TM.db.showSolo = false; TM:ApplySettings()
assertEq(TM.main.__driver, "[group] show; hide", "hide when solo")
TM.db.tankOnly = true; TM:ApplySettings()
assertEq(TM.main.__driver, "[group,form:1] show; hide", "druid tank only")
TM.db.showSolo = true; TM:ApplySettings()
assertEq(TM.main.__driver, "[form:1] show; hide", "tank only solo")
TM.db.tankOnly = false; TM:ApplySettings()
TM.db.shown = false; TM:ApplySettings(); assertEq(TM.main.__driver, "hide", "hidden")
TM.db.shown = true; TM:ApplySettings()

local function runScenario(label)
    step("scenario " .. label)
    STATE.inGroup, STATE.party = true, 2
    STATE.unitsExist = { player = true, party1 = true, party2 = true }
    STATE.roles = { player = "TANK", party1 = "HEALER", party2 = "DAMAGER" }
    STATE.threat = { player = 3, party1 = 0, party2 = 3 }  -- party2 stole aggro
    STATE.mana = { player = 10, party1 = 5 }
    fire("GROUP_ROSTER_UPDATE")
    tick()
    local p2 = TM.unitToButton.party2
    if not SECRET_MODE then
        assert(p2.flashAnim.__playing, "party2 should flash")
        assertEq(TM.unitToButton.player.flashAnim.__playing, false, "no flash for yourself")
        local sounds = 0 for _, l in ipairs(LOG) do if l:find("^SOUND") then sounds = sounds + 1 end end
        assert(sounds >= 1, "aggro sound")
        assertEq(TM.unitToButton.party1.manaText.__shown, true, "healer low mana shown")
        assertEq(TM.unitToButton.party2.manaText.__shown, false, "dps mana not shown when a healer exists")
    end
    -- Every extra on
    TM.db.healthText, TM.db.roleIcons, TM.db.rangeFade, TM.db.sortByRole, TM.db.showToT = true, true, true, true, true
    TM.db.barTexture = "flat"
    TM:ApplySettings(); tick()
    STATE.threat.party2 = 0; tick()
    assertEq(p2.flashAnim.__playing, false, "flash stops")
    -- Cooldown modes
    TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = false, true; tick()
    TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = true, false; tick()
    -- Raid
    STATE.inRaid = true
    for i = 1, 10 do STATE.unitsExist["raid" .. i] = true; STATE.roles["raid" .. i] = (i == 3) and "HEALER" or "DAMAGER" end
    fire("GROUP_ROSTER_UPDATE"); tick()
    STATE.inRaid = false
    TM.db.healthText, TM.db.sortByRole, TM.db.showToT = false, false, false
    TM:ApplySettings(); tick()
end

runScenario("readable values")

step("combat safety")
BLOCKED = {}
COMBAT = true
fire("PLAYER_REGEN_DISABLED")
TM.db.width = 150
TM:ApplySettings()                       -- should queue, not touch protected frames
TM.db.headerFontSize = 14
TM:ApplyFonts()
TM:SetBinding("1", "enemy", "Taunt")
TM.db.sortByRole = true
fire("GROUP_ROSTER_UPDATE")
tick()
SlashCmdList.TAUNTMASTERFOREVER("hide")
SlashCmdList.TAUNTMASTERFOREVER("show")
SlashCmdList.TAUNTMASTERFOREVER("reset")
assertEq(#BLOCKED, 0, "blocked actions in combat: " .. table.concat(BLOCKED, ", "))
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
assertEq(TM.unitToButton.party1.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Taunt", "binding applied after combat")
TM:SetBinding("1", "enemy", "Growl")
TM.db.sortByRole = false; TM.db.width = 120; TM.db.headerFontSize = 10; TM:ApplySettings()

step("raid groups")
STATE.inGroup, STATE.inRaid = true, true
STATE.unitsExist = { player = true }
-- 7 people: raid1-3 in group 1, raid4-5 in group 3, raid6-7 in group 2
RAID_GROUPS = { 1, 1, 1, 3, 3, 2, 2 }
for i = 1, 7 do STATE.unitsExist["raid" .. i] = true end
fire("GROUP_ROSTER_UPDATE")
local function pos(u) local p = TM.unitToButton[u].__pos return p[1], p[2] end
local w, h, s = TM.db.width, TM.db.height, TM.db.spacing
local x1 = pos("raid1"); local x6 = pos("raid6"); local x4 = pos("raid4")
assertEq(x1, 0, "group 1 first column")
assertEq(x6, 1 * (w + s), "group 2 second column")
assertEq(x4, 2 * (w + s), "group 3 third column")
local _, y5 = pos("raid5")
assertEq(y5, -1 * (h + s), "second member of group 3 is row 2")
-- Horizontal: groups become rows
TM.db.unitsPerColumn = 1; TM:Layout()
local hx, hy = pos("raid4")
assertEq(hy, -2 * (h + s), "horizontal: group 3 is third row")
TM.db.unitsPerColumn = 5; TM:Layout()
-- Max Columns caps groups
TM.db.maxColumns = 2; TM:Layout()
assertEq(TM.unitToButton.raid4.__shown, false, "group 3 hidden when Max Columns is 2")
TM.db.maxColumns = 8; TM:Layout()
-- Moving someone mid-combat waits for combat to end
COMBAT = true; BLOCKED = {}
RAID_GROUPS[1] = 2
fire("GROUP_ROSTER_UPDATE")
assertEq(#BLOCKED, 0, "no re-layout in combat")
COMBAT = false; fire("PLAYER_REGEN_ENABLED")
assertEq((pos("raid1")), 1 * (w + s), "raid1 moved to group 2 after combat")
STATE.inRaid = false; RAID_GROUPS = {}

step("cooldown icon size")
TM.db.showToT = true
TM.db.cdIconSize = 40
TM:ApplySettings()
assertEq(TM.cdIcons[1].__size[1], 40, "icon 1 resized")
assertEq(TM.cdIcons[2].__size[2], 40, "icon 2 resized")
assertEq(TM.totButton.__pos[2], 58, "target's-target bar moves above bigger icons")
-- Resizing in combat: icons update right away, protected bar waits
COMBAT = true; BLOCKED = {}
TM.db.cdIconSize = 20
TM:ApplyFonts(); TM:Layout()
assertEq(TM.cdIcons[1].__size[1], 20, "icons resize in combat")
assertEq(#BLOCKED, 0, "nothing protected touched in combat")
COMBAT = false; fire("PLAYER_REGEN_ENABLED")
assertEq(TM.totButton.__pos[2], 38, "bar repositioned after combat")
TM.db.cdIconSize = 26; TM.db.showToT = false; TM:ApplySettings()

step("secret mode")
SECRET_MODE = true
runScenario("hidden values")
SECRET_MODE = false

step("options window: every tab, switch, slider, dropdown, button")
TM:OpenConfig()
local win = TauntMasterForeverConfig
assert(win and win.__shown, "window open")
for _, page in ipairs({ "general", "advanced", "spells", "extras", "display", "bindings", "layout", "alerts", "taunts", "appearance" }) do TM:OpenConfig(page) end
local function walk(f, fn) fn(f) for _, c in ipairs(f.__children or {}) do walk(c, fn) end end
local clicked, slid = 0, 0
walk(win, function(f)
    if f.isSwitch then
        -- flip and flip back, so settings end where they started
        f.__scripts.OnClick(f); f.__scripts.OnClick(f); clicked = clicked + 1
    elseif f.__kind == "CheckButton" and f.__scripts.OnClick then
        f:SetChecked(not f:GetChecked()); f.__scripts.OnClick(f); clicked = clicked + 1
        f:SetChecked(not f:GetChecked()); f.__scripts.OnClick(f)
    elseif f.__kind == "Slider" and f.__scripts.OnValueChanged then
        f.__scripts.OnValueChanged(f, 17); f.__scripts.OnValueChanged(f, 12); slid = slid + 1
    elseif f.__kind == "Button" and f.__scripts.OnClick and f.__text ~= "Close" and f.__text ~= "X" then
        f.__scripts.OnClick(f, "LeftButton"); clicked = clicked + 1
    elseif f.__kind == "EditBox" and f.__scripts.OnEditFocusLost then
        f.__scripts.OnEditFocusLost(f)
    end
end)
print("clicked", clicked, "slid", slid)
assert(clicked > 40 and slid >= 7, "expected all controls to be exercised")

-- Cooldown options stay exclusive
TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = true, false
walk(win, function(f)
    if f.__kind == "CheckButton" then
        for _, r in ipairs(f.__parent.__children) do
            if r.__kind == "FontString" and r.__text == "Show When Ready" and r.__parent == f.__parent then end
        end
    end
end)

step("spell picker menu")
MENUS = {}
walk(win, function(f) if f.__kind == "Button" and f.__text == "Growl" then f.__scripts.OnClick(f) end end)
assert(#MENUS >= 1, "spell menu opened")
local menu = MENUS[#MENUS]
local sawGrowl, sawRoar
for _, e in ipairs(menu.entries) do
    if e.text and e.text:find("Growl") then sawGrowl = e end
    if e.text and e.text:find("Challenging Roar") then sawRoar = e end
end
assert(sawGrowl and sawRoar, "druid taunts listed")
sawRoar.fn()
assertEq(TM:GetBindings()["1"].text, "Challenging Roar", "picked from menu")
assertEq(TM:GetBindings()["1"].kind, "self", "kind carried over")
-- "Custom spell..." opens that click's row on the Click Bindings tab (no Blizzard popup)
TM:SetBinding("1", "target")
for _, e in ipairs(menu.entries) do if e.text == "Custom spell..." then e.fn() end end
assertEq(#POPUPS, 0, "no Blizzard popup")
assertEq(TM._tabs.current(), "bindings", "custom spell opens Click Bindings")
local customRow
for _, row in ipairs(TM._spellRows) do if row.key == "1" then customRow = row end end
assertEq(customRow.kind, "enemy", "row switched to a spell on their target")
assertEq(customRow.edit.__focus, true, "spell box focused")
assert(TM._bindingsMsg:GetText():find("then click Save"), "tells you to save")
customRow.edit:SetText("  Taunt  ")
walk(win, function(f) if f.__kind == "Button" and f.__text == "Save" then f.__scripts.OnClick(f) end end)
assertEq(TM:GetBindings()["1"].text, "Taunt", "custom spell trimmed and saved")
assertEq(TM:GetBindings()["1"].kind, "enemy", "custom spell cast on their target")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()
-- A class with a utility spell lists it under its own heading, after the taunts
STATE.class = "PALADIN"; MENUS = {}
TauntMasterForeverConfig.__scripts.OnShow(TauntMasterForeverConfig)
walk(win, function(f) if f.__kind == "Button" and f.__text == "Judgement" then f.__scripts.OnClick(f) end end)
local order = {}
for _, e in ipairs(MENUS[#MENUS].entries) do
    order[#order + 1] = e.kind .. ":" .. tostring(e.text or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t ", "")
end
assertEq(table.concat(order, " / "), "title:Taunt abilities / radio:Judgement (needs Seal of Fury) not found / divider: / "
    .. "title:Utility / radio:Blessing of Protection not found / divider: / button:Custom spell... / button:Target them / button:None",
    "paladin spell menu")
STATE.class = "DRUID"; MENUS = {}
TauntMasterForeverConfig.__scripts.OnShow(TauntMasterForeverConfig)

step("click bindings: validation and autocomplete")
TM:OpenConfig("spells")
local rows = TM._spellRows
for _, row in ipairs(rows) do
    local needsText = row.kind == "enemy" or row.kind == "friend" or row.kind == "self" or row.kind == "macro"
    assertEq(row.edit.__enabled, needsText, row.label .. ": text box is usable only for spells and macros")
end
assertEq(rows[1].kind, "enemy", "Left click casts a spell"); assertEq(rows[3].kind, "target", "Middle click targets")
local left = rows[1]                      -- Left click, bound to Growl (enemy)
local function type_(row, text) row.edit:SetText(text); row.edit.__scripts.OnTextChanged(row.edit, true) end
left.edit.__scripts.OnEditFocusGained(left.edit)   -- focusing a box loads your spellbook
-- Existing binding shows a green check
TM:OpenConfig("spells"); TauntMasterForeverConfig.__scripts.OnShow(TauntMasterForeverConfig)
assertEq(left.statusState, "ok", "Growl validates")
-- Typing a partial name suggests matches, prefix matches first
type_(left, "c")
local sug = TM._suggest()
assert(sug and sug.__shown, "suggestions shown")
assertEq(sug.matches[1].name, "Challenging Roar", "prefix match first")
type_(left, "gr")
assertEq(sug.matches[1].name, "Growl", "Growl suggested for 'gr'")
assertEq(left.statusState, "missing", "partial name is not a spell")
-- Tab accepts the highlighted suggestion
left.edit.__scripts.OnTabPressed(left.edit)
assertEq(left.edit:GetText(), "Growl", "Tab fills in the suggestion")
assertEq(left.statusState, "ok", "accepted suggestion validates")
assertEq(sug.__shown, false, "list closes after accepting")
-- Arrow keys move the selection; Enter accepts it
type_(left, "o")                         -- contains: Growl, Bear Form, Mark of the Wild ...
local n = #sug.matches
left.edit.__scripts.OnArrowPressed(left.edit, "DOWN")
assertEq(sug.selected, math.min(2, n), "down arrow moves selection")
local pick = sug.matches[sug.selected].name
left.edit.__scripts.OnEnterPressed(left.edit)
assertEq(left.edit:GetText(), pick, "Enter accepts the selected suggestion")
-- Clicking a suggestion works too
type_(left, "mark")
sug.buttons[1].__scripts.OnClick(sug.buttons[1])
assertEq(left.edit:GetText(), "Mark of the Wild", "click accepts suggestion")
-- Escape closes the list without clearing the text
type_(left, "gro")
left.edit.__scripts.OnEscapePressed(left.edit)
assertEq(sug.__shown, false, "Escape closes the list")
assertEq(left.edit:GetText(), "gro", "Escape keeps what you typed")
-- Status icons: not learned, and misspelled
type_(left, "Taunt")
assertEq(left.statusState, "unlearned", "Taunt exists but isn't learned by a Druid")
type_(left, "Growll")
assertEq(left.statusState, "missing", "misspelling flagged")
local msg = TM._bindingsMsg:GetText()
assert(msg:find("Left: Growll") and msg:find("No spell with this name"), "message explains the problem: " .. msg)
type_(left, "Taunt")
assert(TM._bindingsMsg:GetText():find("haven't learned"), "message for unlearned spell")
type_(left, "Growl")
assert(TM._bindingsMsg:GetText():find("Spell found"), "message for a good spell")
-- Opening the tab with a bad saved binding lists it
TM:GetBindings()["2"] = { kind = "enemy", text = "Growll" }
TauntMasterForeverConfig.__scripts.OnShow(TauntMasterForeverConfig)
assert(TM._bindingsMsg:GetText():find("Right %(not found%)"), "summary lists bad bindings: " .. TM._bindingsMsg:GetText())
TM.db.bindings.DRUID = TM:DefaultBindings()
TauntMasterForeverConfig.__scripts.OnShow(TauntMasterForeverConfig)
assertEq(TM._bindingsMsg:GetText(), "", "no message when everything is fine")
-- Saving fixes capitalization
type_(left, "growl")
assertEq(left.statusState, "ok", "lowercase name still validates")
for _, f in ipairs(ALL_FRAMES) do
    if f.__kind == "Button" and f.__text == "Save" and f.__scripts.OnClick then f.__scripts.OnClick(f) end
end
assertEq(TM:GetBindings()["1"].text, "Growl", "saved with the game's spelling")
-- Macro rows get no status icon or suggestions
local macroRow = rows[2]
macroRow.cycle.__scripts.OnClick(macroRow.cycle)  -- cycle kind forward
macroRow.kind = "macro"; type_(macroRow, "/cast Gro")
assertEq(macroRow.statusState, nil, "macros aren't validated")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()

step("taunt announcements")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
TM.db.announceChannel, TM.db.announceText = "PARTY", "Taunted!"
TM:ApplyBindings()
local bar = TM.unitToButton.party1
assertEq(bar.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "announce no longer in the click macro")
local function click(b, mouse) b.__scripts.PreClick(b, mouse or "LeftButton") end
local function cast(id) fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-guid", id) end
-- Clicked taunt that casts: announced once
CHAT = {}
click(bar); cast(6795)
assertEq(#CHAT, 1, "announce after a successful taunt"); assertEq(CHAT[1], "PARTY:Taunted!", "right channel and text")
cast(6795)
assertEq(#CHAT, 1, "only one message per click")
-- Clicked but the spell never cast (cooldown, range): nothing
CHAT = {}
click(bar); FAKE_TIME = FAKE_TIME + 3; cast(6795)
assertEq(#CHAT, 0, "no announce when the cast doesn't happen right away")
-- A different spell cast after the click: nothing
click(bar); cast(1126)
assertEq(#CHAT, 0, "other spells aren't announced")
-- Growl from the action bar, no bar click: nothing
FAKE_TIME = FAKE_TIME + 3; cast(6795)
assertEq(#CHAT, 0, "action-bar taunts aren't announced")
-- Right click (Challenging Roar, AoE) announces too
click(bar, "RightButton"); cast(5209)
assertEq(#CHAT, 1, "AoE taunt announced")
-- Middle click (target) sets nothing up
CHAT = {}
click(bar, "MiddleButton"); cast(6795)
assertEq(#CHAT, 0, "non-spell clicks aren't announced")
-- Modifier keys pick the right binding
TM:GetBindings()["shift-1"] = { kind = "enemy", text = "Taunt" }
MOD_KEYS.shift = true; click(bar); MOD_KEYS.shift = false
cast(6795); assertEq(#CHAT, 0, "shift-click expects its own spell")
FAKE_TIME = FAKE_TIME + 3
MOD_KEYS.shift = true; click(bar); MOD_KEYS.shift = false
cast(355); assertEq(#CHAT, 1, "shift-click spell announced")
TM:GetBindings()["shift-1"] = nil
-- Hidden spell ID: timing is trusted
CHAT = {}
SECRET_MODE = true; click(bar); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", setmetatable({}, getmetatable(UnitHealth("player")))); SECRET_MODE = false
assertEq(#CHAT, 1, "hidden spell ID still announces")
-- Solo with Party chosen: skipped quietly
CHAT = {}; STATE.inGroup = false
click(bar); cast(6795)
assertEq(#CHAT, 0, "no party message when solo")
-- Off: nothing
STATE.inGroup = true; TM.db.announceChannel = "none"
click(bar); cast(6795)
assertEq(#CHAT, 0, "announcements off")
-- Say/Yell: only inside instances (the game blocks them elsewhere)
TM.db.announceChannel = "SAY"; CHAT = {}; FAKE_TIME = FAKE_TIME + 3
click(bar); cast(6795)
assertEq(#CHAT, 0, "no Say outside instances")
INSTANCE = true; FAKE_TIME = FAKE_TIME + 3
click(bar); cast(6795)
assertEq(#CHAT, 1, "Say inside instances")
INSTANCE = false; TM.db.announceChannel = "none"; CHAT = {}
FAKE_TIME = FAKE_TIME + 3

step("keybindings and controller support")
-- Every binding in Bindings.xml has a readable name
local f = assert(io.open(ADDON_DIR .. "/Bindings.xml")); local xml = f:read("*a"); f:close()
local count = 0
for name in xml:gmatch('name="([^"]+)"') do
    count = count + 1
    assert(_G["BINDING_NAME_" .. name], "missing binding name for " .. name)
end
assertEq(count, 14, "14 keybindings")
-- Own section in the Keybindings menu, like other addons
local cats = {}
for c in xml:gmatch('category="([^"]+)"') do cats[#cats + 1] = c end
assertEq(#cats, 14, "every binding has a category")
for _, c in ipairs(cats) do assertEq(c, "TauntMaster Forever", "category is the addon's own section") end
-- Keybinding presses use the plain Left/Right Click spell, whatever modifier is held
TM:GetBindings()["shift-1"] = { kind = "enemy", text = "Taunt" }
TM:ApplyBindings()
local p1 = TM.unitToButton.party1
assertEq(p1.__attrs["*macrotext-tmleft"], "/cast [@party1target,harm,nodead] Growl", "party1 left keybind")
assertEq(p1.__attrs["*macrotext-tmright"], "/cast Challenging Roar", "party1 right keybind")
assertEq(p1.__attrs["shift-macrotext1"], "/cast [@party1target,harm,nodead] Taunt", "mouse shift-click unchanged")
-- Targeted ally button taunts what's attacking your friendly target
local ally = TauntMasterForever_ally
assertEq(ally.__attrs["*macrotext-tmleft"], "/cast [@targettarget,harm,nodead] Growl", "ally keybind macro")
-- Mouseover button taunts what's attacking the player under your mouse (raid frames, the world)
local mo = TauntMasterForever_mouseover
assertEq(mo.__attrs["*macrotext-tmleft"], "/cast [@mouseovertarget,harm,nodead] Growl", "mouseover keybind macro")
assertEq(mo.__attrs["*macrotext-tmright"], "/cast Challenging Roar", "mouseover right keybind")
-- Middle-click style bindings map to the secure type
TM:GetBindings()["2"] = { kind = "target", text = "" }; TM:ApplyBindings()
assertEq(p1.__attrs["*type-tmright"], "target", "non-spell keybind type")
assertEq(p1.__attrs["*macrotext-tmright"], nil, "no leftover macro")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()
-- Announcements work from keybindings, ignoring held modifiers
TM.db.announceChannel = "PARTY"; STATE.inGroup = true; CHAT = {}
MOD_KEYS.shift = true; p1.__scripts.PreClick(p1, "TMLeft"); MOD_KEYS.shift = false
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 6795)
assertEq(#CHAT, 1, "keybind taunt announced")
FAKE_TIME = FAKE_TIME + 3; CHAT = {}
ally.__scripts.PreClick(ally, "TMLeft"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 6795)
assertEq(#CHAT, 1, "ally keybind announced")
TM.db.announceChannel = "none"; FAKE_TIME = FAKE_TIME + 3
-- Hints beside bars
KEYBINDS["CLICK TauntMasterForever_party1:TMLeft"] = "PAD1"
KEYBINDS["CLICK TauntMasterForever_party1:TMRight"] = "SHIFT-PAD1"
KEYBINDS["CLICK TauntMasterForever_party2:TMRight"] = "PAD2"
fire("UPDATE_BINDINGS")
assertEq(p1.keyHint:GetText(), "PAD1 / s-PAD1", "hint shows both keys, short form")
assertEq(p1.keyHint.__shown, true, "hint visible")
assertEq(TM.unitToButton.party2.keyHint:GetText(), "PAD2", "single binding hint")
assertEq(TM.unitToButton.party3.keyHint.__shown, false, "no hint without bindings")
TM.db.keyHints = false; TM:ApplySettings()
assertEq(p1.keyHint.__shown, false, "hints can be turned off")
TM.db.keyHints = true; KEYBINDS = {}; TM:ApplySettings()
assertEq(p1.keyHint.__shown, false, "hint gone when unbound")
-- Nothing protected changes when bindings update mid-fight
COMBAT = true; BLOCKED = {}
KEYBINDS["CLICK TauntMasterForever_player:TMLeft"] = "PAD3"; fire("UPDATE_BINDINGS")
assertEq(#BLOCKED, 0, "hint update is combat-safe")
COMBAT = false; KEYBINDS = {}; fire("UPDATE_BINDINGS")

step("no-target marker and reachability")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
STATE.unitsExist = { player = true, party1 = true, party2 = true }
TM.db.rangeFade = true
local p1, p2, me = TM.unitToButton.party1, TM.unitToButton.party2, TM.unitToButton.player
local function refresh() tick() end
-- Hostile target in range: bright, no marker
RANGE = {}; HOSTILE = {}; refresh()
assertEq(p1.bar.__alpha, 1, "in range: bright"); assertEq(p1.noTarget.__alpha, 0, "in range: no marker")
-- Out of range: dim, no marker
RANGE.party1target = false; refresh()
assertEq(p1.bar.__alpha, 0.35, "out of range: dim"); assertEq(p1.noTarget.__alpha, 0, "out of range: still no marker")
-- No enemy targeted (e.g. healer targeting the tank): dim + marker
RANGE.party1target = "none"; HOSTILE.party1target = false; refresh()
assertEq(p1.bar.__alpha, 0.35, "no enemy target: dim"); assertEq(p1.noTarget.__alpha, 1, "no enemy target: marker")
assertEq(p2.noTarget.__alpha, 0, "other bars unaffected")
-- Your own bar never dims or shows the marker
RANGE.playertarget = "none"; refresh()
assertEq(me.bar.__alpha, 1, "own bar bright"); assertEq(me.noTarget.__alpha, 0, "own bar no marker")
-- Hidden values: the game decides, through the same widgets
SECRET_MODE = true; refresh()
assert(issecretvalue(p1.noTarget.__alpha) and p1.noTarget.__alpha.v == 1, "secret marker shown")
assert(issecretvalue(p1.bar.__alpha) and p1.bar.__alpha.v == 0.35, "secret dim")
assert(issecretvalue(p2.noTarget.__alpha) and p2.noTarget.__alpha.v == 0, "secret marker hidden")
SECRET_MODE = false
-- Turning the option off clears both
TM.db.rangeFade = false; refresh()
assertEq(p1.bar.__alpha, 1, "option off: bright"); assertEq(p1.noTarget.__alpha, 0, "option off: no marker")
-- Left Click not a learned targeted taunt: falls back to distance, no marker
TM.db.rangeFade = true; TM:GetBindings()["1"] = { kind = "enemy", text = "Taunt" }; refresh()
assertEq(p1.noTarget.__alpha, 0, "unlearned taunt: no marker")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()
RANGE = {}; HOSTILE = {}; refresh()

step("announcements with names")
TM.db.announceChannel = "PARTY"; TM.db.announceText = DEFAULT_TEXT or "{target} has been taunted off of {player}!"
local function clickCast(b, mouse, id) CHAT = {}; b.__scripts.PreClick(b, mouse or "LeftButton"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", id or 6795); FAKE_TIME = FAKE_TIME + 3 end
clickCast(p1)
assertEq(CHAT[1], "PARTY:Name_party1target has been taunted off of Name_party1!", "names filled in")
clickCast(p1, "RightButton", 5209)
assertEq(CHAT[1], "PARTY:Everything nearby has been taunted off of Name_party1!", "AoE taunt wording")
clickCast(TauntMasterForever_ally, "TMLeft")
assertEq(CHAT[1], "PARTY:Name_targettarget has been taunted off of Name_target!", "targeted ally names")
SECRET_MODE = true; clickCast(p1); SECRET_MODE = false
assertEq(CHAT[1], "PARTY:The mob has been taunted off of my ally!", "hidden names fall back to plain words")
TM.db.announceText = "Taunted {target}! {player} is safe, 100%"
clickCast(p1)
assertEq(CHAT[1], "PARTY:Taunted Name_party1target! Name_party1 is safe, 100%", "custom text with both tokens and a % sign")
TM.db.announceText = "Taunted!"; clickCast(p1)
assertEq(CHAT[1], "PARTY:Taunted!", "text without tokens unchanged")
TM.db.announceChannel = "none"

step("settings migration")
local savedDB = TauntMasterForeverDB
TauntMasterForeverDB = { announceText = "Taunted!", schema = 2 }
fire("ADDON_LOADED", "TauntMasterForever")
assertEq(TM.db.announceText, "{target} has been taunted off of {player}!", "old default message upgraded")
TauntMasterForeverDB = { announceText = "My own text", schema = 2 }
fire("ADDON_LOADED", "TauntMasterForever")
assertEq(TM.db.announceText, "My own text", "custom message kept")
TauntMasterForeverDB = savedDB; TM.db = savedDB

step("splash screen")
local splash = TM._splash
-- Fresh install: shown at login
assert(splash and splash.__shown, "splash shown on first login")
assertEq(TM.db.lastSeenVersion, TM:CurrentNewsVersion(), "version remembered")
local txt = splash.text:GetText()
assert(txt:find("Quick start") and txt:find("What's new") and txt:find("/tm news"), "splash has quick start and news")
local newsLines = 0
for _ in txt:gmatch("\n%- |cffffd100v") do newsLines = newsLines + 1 end
assertEq(newsLines, 6, "six latest changes listed")
splash:Hide()
-- Same version next login: not shown
TM:MaybeShowSplash(); assertEq(splash.__shown, false, "not shown again for the same version")
-- New version: shown again
TM.db.lastSeenVersion = "1.0.0"; TM:MaybeShowSplash()
assertEq(splash.__shown, true, "shown after an update"); splash:Hide()
-- Turned off: not shown after updates
TM.db.lastSeenVersion = "1.0.0"; TM.db.showSplash = false; TM:MaybeShowSplash()
assertEq(splash.__shown, false, "respects the checkbox")
-- /tm news toggles it regardless
SlashCmdList.TAUNTMASTERFOREVER("news"); assertEq(splash.__shown, true, "/tm news opens it")
assertEq(splash.check:IsOn(), false, "switch reflects setting")
splash.check.__scripts.OnClick(splash.check)
assertEq(TM.db.showSplash, true, "switch turns it back on")
assertEq(splash.check:IsOn(), true, "switch repaints")
SlashCmdList.TAUNTMASTERFOREVER("news"); assertEq(splash.__shown, false, "/tm news closes it")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "TauntMasterForeverSplash" then esc = true end end
assert(esc, "Escape closes the splash")
-- News list stays in sync with the changelog
local cf = assert(io.open(ADDON_DIR .. "/CHANGELOG.md")); local topVersion = cf:read("*a"):match("## ([%d%.]+)"); cf:close()
assertEq(TM:CurrentNewsVersion(), topVersion, "News.lua top version matches CHANGELOG.md")
for _, e in ipairs(TM.NEWS) do assert(e.version and e.date and #e.items > 0, "news entry complete") end

step("tabbed settings")
TM:OpenConfig(); TM:OpenConfig()          -- close then reopen
local cfg = TauntMasterForeverConfig
assert(cfg.__shown, "options open")
local tabs = TM._tabs
for _, k in ipairs({ "taunts", "bindings", "layout", "appearance", "alerts", "general" }) do
    assert(tabs.pages[k] and tabs.buttons[k], "tab exists: " .. k)
    tabs.buttons[k].__scripts.OnClick(tabs.buttons[k])
    assertEq(tabs.current(), k, "clicking tab shows it: " .. k)
    for other, page in pairs(tabs.pages) do assertEq(page.__shown, other == k, "only one page visible") end
    assertEq(tabs.buttons[k].selBg.__shown, true, "selected tab highlighted")
end
-- Old names still open the right tab
TM:OpenConfig("spells"); assertEq(tabs.current(), "bindings", "/tm spells -> Click Bindings")
TM:OpenConfig("extras"); assertEq(tabs.current(), "alerts", "extras -> Alerts")
TM:OpenConfig("advanced"); assertEq(tabs.current(), "appearance", "advanced -> Appearance")
TM:OpenConfig("display"); assertEq(tabs.current(), "taunts", "display -> Taunts")
local function walk(f, fn) fn(f) for _, c in ipairs(f.__children or {}) do walk(c, fn) end end
-- Switches save and repaint; inverted ones show the opposite of the saved value
local soloSwitch
walk(cfg, function(f) if f.isSwitch and not soloSwitch then
    local before = TM.db.showSolo
    f.__scripts.OnClick(f)
    if TM.db.showSolo ~= before then soloSwitch = f else f.__scripts.OnClick(f) end
end end)
assert(soloSwitch, "Hide when solo switch found")
soloSwitch.__scripts.OnClick(soloSwitch)
-- Cooldown switches stay exclusive
TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = true, false
local cdSwitches = {}
walk(cfg, function(f) if f.isSwitch then cdSwitches[#cdSwitches + 1] = f end end)
for _, f in ipairs(cdSwitches) do
    local a, b = TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady
    f.__scripts.OnClick(f)
    if TM.db.cdShowWhenReady and not b then
        assertEq(TM.db.cdShowOnCooldown, false, "turning on 'when ready' turns off 'on cooldown'")
        f.__scripts.OnClick(f)                 -- off again
        TM.db.cdShowOnCooldown = true
    elseif (TM.db.cdShowOnCooldown ~= a) or (TM.db.cdShowWhenReady ~= b) then
        f.__scripts.OnClick(f)                 -- not a cooldown switch here; put it back
    else
        f.__scripts.OnClick(f)
    end
end
-- Dropdowns open a menu; picking an item saves it
MENUS = {}
local chanDropdown
walk(cfg, function(f) if f.__kind == "Button" and f.Choose and f.__text == "Master" then chanDropdown = f end end)
assert(chanDropdown, "sound channel dropdown found")
chanDropdown.__scripts.OnClick(chanDropdown)
local menu = MENUS[#MENUS]
assertEq(#menu.entries, 3, "three sound channels offered")
menu.entries[2].fn()
assertEq(TM.db.aggroSoundChannel, "SFX", "picking from the menu saves it")
assertEq(chanDropdown.__text, "Sound Effects", "dropdown shows the choice")
TM.db.aggroSoundChannel = "Master"
-- Labels: "Sound channel", not "Volume slider"
local labels = {}
walk(cfg, function(f) if f.__kind == "FontString" and f.__text then labels[f.__text] = true end end)
assert(labels["Sound channel"] and not labels["Volume slider"], "sound channel label")
assert(labels["Show welcome screen after updates"], "welcome screen switch present")
-- Scale slider moves in 0.05 steps
local scaleOk = false
walk(cfg, function(f) if f.__kind == "Slider" then
    f.__scripts.OnValueChanged(f, 1.23)
    if TM.db.scale and math.abs(TM.db.scale - 1.25) < 0.001 then scaleOk = true end
end end)
assert(scaleOk, "scale slider rounds to 0.05")
TM.db.scale = 1; TM.db.width = 120; TM.db.height = 24; TM.db.unitsPerColumn = 5; TM.db.maxColumns = 8
TM.db.spacing = 2; TM.db.headerFontSize = 10; TM.db.nameFontSize = 10; TM.db.cdIconSize = 26; TM.db.manaWarnPct = 20
TM:ApplySettings()
for _, b in ipairs(TM.partyButtons) do b:Show() end   -- the game's unit watcher re-shows these

step("aggro sound options")
local function soundsSince(n) local out = {} for i = n + 1, #LOG do if LOG[i]:find("^SOUND") then out[#out + 1] = LOG[i] end end return out end
STATE.inGroup, STATE.party = true, 2
STATE.unitsExist = { player = true, party1 = true, party2 = true }
STATE.roles = { player = "TANK", party1 = "HEALER", party2 = "DAMAGER" }
TM.db.aggroSound = true
TM.db.aggroSoundLevel, TM.db.aggroSoundKey, TM.db.aggroSoundChannel = 2, "raidwarning", "Master"
local function threatTo(t) STATE.threat.party2 = t; FAKE_TIME = FAKE_TIME + 2; tick() end
-- Default: orange/red, Raid Warning, Master
threatTo(0); local n = #LOG
threatTo(1); assertEq(#soundsSince(n), 0, "no sound at yellow by default")
threatTo(2); local s = soundsSince(n); assertEq(#s, 1, "sound at orange"); assertEq(s[1], "SOUND 8959 Master", "raid warning on master")
-- Yellow level
TM.db.aggroSoundLevel = 1; threatTo(0); n = #LOG
threatTo(1); assertEq(#soundsSince(n), 1, "yellow level alerts at yellow")
threatTo(3); assertEq(#soundsSince(n), 1, "no repeat while it stays high")
-- Red-only level
TM.db.aggroSoundLevel = 3; threatTo(0); n = #LOG
threatTo(2); assertEq(#soundsSince(n), 0, "red-only ignores orange")
threatTo(3); assertEq(#soundsSince(n), 1, "red-only alerts at red")
-- Sound and channel choices
TM.db.aggroSoundKey = "readycheck"; TM.db.aggroSoundChannel = "SFX"; TM.db.aggroSoundLevel = 2
threatTo(0); n = #LOG; threatTo(2)
assertEq(soundsSince(n)[1], "SOUND 8960 SFX", "picked sound and channel")
-- Test button plays even right after an alert
n = #LOG; TM:TestAggroSound(); TM:TestAggroSound()
assertEq(#soundsSince(n), 2, "test ignores the 1.5s limit")
-- Tanks and you never trigger it
STATE.roles.party2 = "TANK"; threatTo(0); n = #LOG; threatTo(3)
assertEq(#soundsSince(n), 0, "other tanks don't trigger it")
STATE.roles.party2 = "DAMAGER"; STATE.threat.party2 = 0; tick()
TM.db.aggroSound = false; TM.db.aggroSoundKey = "raidwarning"; TM.db.aggroSoundChannel = "Master"

step("name and look consistency")
-- Every user-facing name is "TauntMaster Forever". The header bar, where room is
-- tight, shows the logo and "TauntMaster" (the same bar as ToppedOff Forever's).
assertEq(TM.handle.text:GetText(), "TauntMaster", "bar header name")
assertEq(TM.handle.logo.__texture, "Interface\\AddOns\\TauntMasterForever\\Media\\logo", "bar header shows the logo")
local chatLine
for _, l in ipairs(LOG) do if l:find("TauntMaster") then chatLine = l end end
assert(chatLine and chatLine:find("TauntMaster Forever"), "chat uses full name: " .. tostring(chatLine))
for _, l in ipairs(LOG) do
    assert(not l:find("TauntMaster|r"), "old short chat prefix: " .. l)
end
for _, file in ipairs({ "Core.lua", "Options.lua", "Splash.lua", "Theme.lua", "News.lua", "README.md", "TauntMasterForever.toc", "Bindings.xml" }) do
    local f = assert(io.open(ADDON_DIR .. "/" .. file)); local src = f:read("*a"); f:close()
    assert(not src:find("Taunt Master"), "'Taunt Master' (with a space) in " .. file)
    assert(not src:find("Spell_Nature_Reincarnation"), "old icon in " .. file)
    assert(not src:find("UIPanelButtonTemplate") and not src:find("UICheckButtonTemplate")
        and not src:find("UIPanelScrollFrameTemplate") and not src:find("BasicFrameTemplate"),
        "Blizzard-style widget left in " .. file)
end
local tf = assert(io.open(ADDON_DIR .. "/TauntMasterForever.toc")); local toc = tf:read("*a"); tf:close()
assert(toc:find("IconTexture: Interface\\AddOns\\TauntMasterForever\\Media\\logo"), "AddOns list icon is the logo")

step("header menu")
MENUS = {}
TM.handle.__scripts.OnMouseUp(TM.handle, "RightButton")
local hm = MENUS[#MENUS]
local lockEntry, settingsEntry
for _, e in ipairs(hm.entries) do if e.text == "Lock" then lockEntry = e elseif e.text == "Settings" then settingsEntry = e end end
lockEntry.fn(); assertEq(TM.db.locked, true, "locked via menu")
lockEntry.fn(); assertEq(TM.db.locked, false, "unlocked via menu")
settingsEntry.fn()

step("slash commands")
for _, c in ipairs({ "", "show", "hide", "toggle", "toggle", "lock", "unlock", "spells", "display", "advanced", "extras", "check", "debug", "reset", "help" }) do
    SlashCmdList.TAUNTMASTERFOREVER(c)
end
SECRET_MODE = true; SlashCmdList.TAUNTMASTERFOREVER("debug"); SECRET_MODE = false

step("minimap")
assertEq(TM.minimapButton.icon.__texture, "Interface\\AddOns\\TauntMasterForever\\Media\\logo", "the minimap button shows the logo")
assertEq(TM.minimapButton.icon.__texcoord, nil, "whole (it's round: nothing to trim)")
-- The logo file itself: what the game can load (an uncompressed 32-bit TGA, 128x128), and round
do
    local f = assert(io.open(ADDON_DIR .. "/Media/logo.tga", "rb"), "the logo file")
    local data = f:read("*a") f:close()
    assertEq(data:byte(3), 2, "uncompressed true-color TGA")
    assertEq(data:byte(13) + data:byte(14) * 256, 128, "128 wide")
    assertEq(data:byte(15) + data:byte(16) * 256, 128, "128 tall")
    assertEq(data:byte(17), 32, "32-bit, with transparency")
    assertEq(data:byte(18 + 4), 0, "its corner is see-through (a round logo, not a square one)")
    local pkg = io.open(ADDON_DIR .. "/.pkgmeta"):read("*a")
    assert(pkg:find("\n  %- art\n"), "the logo's sources aren't shipped")
end
TM.minimapButton.__scripts.OnClick(TM.minimapButton, "LeftButton")
TM.minimapButton.__scripts.OnClick(TM.minimapButton, "RightButton")
TM.minimapButton.__scripts.OnDragStart(TM.minimapButton)
TM.minimapButton.__scripts.OnUpdate()
TM.minimapButton.__scripts.OnDragStop(TM.minimapButton)
TM.minimapButton.__scripts.OnEnter(TM.minimapButton)

step("warrior + paladin + other class defaults")
for _, cls in ipairs({ "WARRIOR", "PALADIN", "MAGE" }) do
    STATE.class = cls
    TM:ApplyBindings()
    TM:PrintLoadMessage()
    local b = TM:GetBindings()
    print(cls, b["1"] and b["1"].text or "-", b["2"] and b["2"].text or "-")
end
assertEq(TM.unitToButton.party1.__attrs["shift-macrotext1"], nil, "mage has no shift binding")
STATE.class = "PALADIN"; TM:ApplyBindings()
assertEq(TM.unitToButton.party1.__attrs["shift-macrotext1"], "/cast [@party1,help,nodead] Blessing of Protection", "paladin BoP on the member")
STATE.class = "WARRIOR"; TM:ApplySettings()
TM.db.tankOnly = true; TM:ApplySettings()
assertEq(TM.main.__driver, "[stance:2] show; hide", "warrior defensive stance")

step("review fixes")
-- Unlearned class spells are found by ID (the game can't find them by name)
assert(C_Spell.GetSpellInfo("Mocking Blow") == nil, "stub: name lookup misses unlearned spells")
assertEq(TM:GetSpellInfo("mocking blow") and TM:GetSpellInfo("mocking blow").spellID, 694, "unlearned taunt found by ID")
assertEq(TM:GetSpellInfo("Not A Spell"), nil, "unknown spell stays unknown")
assertEq(TM:GetSpellInfo(nil), nil, "nil name is safe")
-- The targeted-ally button uses the same template as the bars
assertEq(TauntMasterForever_ally.__template, "SecureUnitButtonTemplate", "ally button template")
-- Dragging in combat: the drop does nothing if the drag never started
TM.db.locked = false; COMBAT = true; BLOCKED = {}
TM.handle.__scripts.OnDragStart(TM.handle); TM.handle.__scripts.OnDragStop(TM.handle)
assertEq(TM.main.isMoving, nil, "no drag in combat")
COMBAT = false
TM.handle.__scripts.OnDragStart(TM.handle); assertEq(TM.main.isMoving, true, "drag starts")
TM.handle.__scripts.OnDragStop(TM.handle); assertEq(TM.main.isMoving, false, "drag ends")
-- Hidden range results never get truth-tested
SECRET_MODE = true
for _, b in ipairs(TM.buttons) do if b:IsVisible() then TM:UpdateButton(b) end end
SECRET_MODE = false
step("cooldown icons in instances (hidden times)")
local icon = TM.cdIcons[1]
local function cdShown(onCd, ready, active, gcd)
    TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = onCd, ready
    CD_ACTIVE, CD_GCD = active, gcd
    SECRET_MODE = true; TM:UpdateCooldowns(); SECRET_MODE = false
    return icon.__shown
end
assertEq(cdShown(true, false, true, false), true, "on cooldown: shown with Show on cooldown")
assertEq(cdShown(true, false, false, false), false, "ready: hidden with Show on cooldown")
assertEq(cdShown(false, true, false, false), true, "ready: shown with Show when ready")
assertEq(cdShown(false, true, true, false), false, "on cooldown: hidden with Show when ready")
assertEq(cdShown(false, true, true, true), true, "global cooldown counts as ready")
-- The swipe is drawn from the game's own duration object, or from the hidden times
local swipes = {}
icon.cd.SetCooldown = function() swipes[#swipes + 1] = "times" end
assertEq(cdShown(true, false, true, false), true, "on cooldown")
assertEq(table.concat(swipes, ","), "times", "no duration object: the hidden times are handed to the swipe")
swipes = {}
C_Spell.GetSpellCooldownDuration = function(id) return { id = id } end
icon.cd.SetCooldownFromDurationObject = function(_, d) swipes[#swipes + 1] = "object" .. tostring(d.id) end
cdShown(true, false, true, false)
assertEq(swipes[1] and swipes[1]:match("^object%d+$") and #swipes, 1, "the duration object is used when the game has one")
swipes = {}
icon.cd.SetCooldownFromDurationObject = function() error("not this time") end
cdShown(true, false, true, false)
assertEq(table.concat(swipes, ","), "times", "and the times are the fallback if it fails")
C_Spell.GetSpellCooldownDuration, icon.cd.SetCooldownFromDurationObject, icon.cd.SetCooldown = nil, nil, nil
CD_ACTIVE, CD_GCD = nil, nil
TM.db.cdShowOnCooldown, TM.db.cdShowWhenReady = true, false
SECRET_MODE = true; SlashCmdList.TAUNTMASTERFOREVER("debug"); SECRET_MODE = false
step("backup taunt (no enemy targeted)")
STATE.class = "DRUID"; TM.db.bindings.DRUID = TM:DefaultBindings()
assertEq(TM.db.tauntFallback, false, "backup taunt off by default")
TM:ApplyBindings()
assertEq(TM.unitToButton.party1.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "no backup when off")
TM.db.tauntFallback = true; TM:ApplySettings()
assertEq(TM.unitToButton.party1.__attrs.macrotext1,
    "/cast [@party1target,harm,nodead] Growl; [@party1targettarget,harm,nodead] Growl", "backup in click macro")
assertEq(TM.unitToButton.party1.__attrs["*macrotext-tmleft"],
    "/cast [@party1target,harm,nodead] Growl; [@party1targettarget,harm,nodead] Growl", "backup in keybind macro")
assertEq(TM.totButton.__attrs.macrotext1, "/cast [@target,harm,nodead] Growl", "target's target bar unchanged")
assertEq(TauntMasterForever_ally.__attrs["*macrotext-tmleft"],
    "/cast [@targettarget,harm,nodead] Growl; [@targettargettarget,harm,nodead] Growl", "ally keybind backup")
-- Range check and announcement follow the same enemy
HOSTILE.party1target = false
assertEq(TM:EnemyUnitFor(TM.unitToButton.party1), "party1targettarget", "friendly target -> their target's target")
HOSTILE.party1target = nil
assertEq(TM:EnemyUnitFor(TM.unitToButton.party1), "party1target", "enemy target used as is")
SECRET_MODE = true
assertEq(TM:EnemyUnitFor(TM.unitToButton.party1), "party1target", "hidden hostility: use their target")
SECRET_MODE = false
TM.db.announceChannel = "PARTY"; TM.db.announceText = "{target} has been taunted off of {player}!"; STATE.inGroup = true; CHAT = {}; FAKE_TIME = FAKE_TIME + 3
HOSTILE.party1target = false
local p1b = TM.unitToButton.party1
p1b.__scripts.PreClick(p1b, "LeftButton"); fire("UNIT_SPELLCAST_SUCCEEDED", "player", "g", 6795)
assertEq(CHAT[1], "PARTY:Name_party1targettarget has been taunted off of Name_party1!", "backup names the right mob")
HOSTILE.party1target = nil; TM.db.announceChannel = "none"
TM.db.tauntFallback = false; TM:ApplySettings()
assertEq(TM.unitToButton.party1.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "backup off again")

step("nameplate marks")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
STATE.roles = {}
assertEq(TM.db.nameplateMarks, true, "nameplate marks on by default")
fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
local mark1 = PLATES.nameplate1.tmForeverMark
assert(mark1, "mark created on the plate")
MOB_TARGET = { nameplate1 = "party2", nameplate2 = "player" }
TM:UpdatePlateMarks()
assertEq(mark1.__shown, true, "mob on the healer is marked")
assertEq(PLATES.nameplate2.tmForeverMark.__shown, false, "mob on you isn't marked")
STATE.roles.party2 = "TANK"; TM:UpdatePlateMarks()
assertEq(mark1.__shown, false, "mob on another tank isn't marked")
STATE.roles = {}
HOSTILE.nameplate1 = false; TM:UpdatePlateMarks()
assertEq(mark1.__shown, false, "friendly plates aren't marked")
HOSTILE.nameplate1 = nil
-- Hidden answers (instances): stacked logos, the game sets their alpha
SECRET_UNITISUNIT = true; TM:UpdatePlateMarks()
assertEq(mark1.__shown, true, "hidden: mark frame shown, alpha decides")
assertEq(#mark1.layers, 2, "one layer per watched member")
SECRET_UNITISUNIT = false
-- Turned off: hidden
TM.db.nameplateMarks = false; TM:UpdatePlateMarks()
assertEq(mark1.__shown, false, "off hides marks")
TM.db.nameplateMarks = true
fire("NAME_PLATE_UNIT_REMOVED", "nameplate1")
assertEq(mark1.__shown, false, "removed plate's mark hidden")
MOB_TARGET = {}
step("boss warning sound falls back")
LOG = {}
TM.db.aggroSoundKey = "bosswarning"; TM:TestAggroSound()
local played
for _, l in ipairs(LOG) do if l:find("^SOUND") then played = l end end
assertEq(played, "SOUND 8959 " .. TM.db.aggroSoundChannel, "missing boss sounds fall back to one that plays")
MISSING_SOUNDS = {}; LOG = {}; TM:TestAggroSound()
played = nil
for _, l in ipairs(LOG) do if l:find("^SOUND") then played = l end end
assertEq(played, "SOUND 12197 " .. TM.db.aggroSoundChannel, "boss emote warning used when it exists")
TM.db.aggroSoundKey = "raidwarning"

step("settings changed in combat are applied once, when it ends")
local layouts, binds = 0, 0
local realLayoutGroup, realApplyToButton = TM.LayoutGroup, TM.ApplyBindingsToButton
TM.LayoutGroup = function(...) layouts = layouts + 1 return realLayoutGroup(...) end
TM.ApplyBindingsToButton = function(...) binds = binds + 1 return realApplyToButton(...) end
COMBAT = true; BLOCKED = {}
for n = 1, 25 do TM.db.width = 100 + n; TM:ApplySettings() end
SlashCmdList.TAUNTMASTERFOREVER("reset"); SlashCmdList.TAUNTMASTERFOREVER("reset")
assertEq(layouts, 0, "nothing is laid out in combat")
assertEq(#BLOCKED, 0, "no protected frame touched in combat: " .. table.concat(BLOCKED, ", "))
COMBAT = false
fire("PLAYER_REGEN_ENABLED")
assertEq(layouts, 1, "one layout for 25 changes")
assertEq(binds, #TM.buttons + #TM.hiddenButtons, "bindings applied once to each bar (and the targeted-ally and mouseover buttons)")
assertEq(TM.unitToButton.party1.__size[1], 125, "with the last value")
assertEq(TM.pending, nil, "nothing left waiting")
fire("PLAYER_REGEN_ENABLED")
assertEq(layouts, 1, "and it isn't run again")
TM.LayoutGroup, TM.ApplyBindingsToButton = realLayoutGroup, realApplyToButton
TM.db.width = 120; TM:ApplySettings()

step("health changes update the bar and health % only")
local realDead, realConnected = UnitIsDeadOrGhost, UnitIsConnected
local dead, offline = {}, {}
UnitIsDeadOrGhost = function(u) return dead[u] == true end
UnitIsConnected = function(u) return not offline[u] end
TM.db.healthText = true; TM.db.aggroSound = true; TM.db.aggroSoundLevel = 2
STATE.inGroup, STATE.party, STATE.roles, STATE.threat = true, 2, {}, {}
local hb = TM.unitToButton.party1
tick()
assertEq(hb.statusText.__text, "50%", "health % shown")
local updates = 0
local realUpdateButton = TM.UpdateButton
TM.UpdateButton = function(...) updates = updates + 1 return realUpdateButton(...) end
hb.statusText.__text = "stale"
fire("UNIT_HEALTH", "party1")
assertEq(hb.statusText.__text, "50%", "a health change refreshes the health %")
assertEq(updates, 0, "without redrawing the whole bar")
fire("UNIT_HEALTH", "nameplate7")
assertEq(updates, 0, "units without a bar are ignored")
STATE.threat.party1 = 3; LOG = {}; FAKE_TIME = FAKE_TIME + 5
fire("UNIT_HEALTH", "party1")
local sounded = false
for _, l in ipairs(LOG) do if l:find("^SOUND") then sounded = true end end
assertEq(sounded, false, "a health change alone doesn't play the aggro sound")
fire("UNIT_THREAT_SITUATION_UPDATE", "party1")
assertEq(updates, 1, "a threat change redraws the bar")
for _, l in ipairs(LOG) do if l:find("^SOUND") then sounded = true end end
assertEq(sounded, true, "and plays the aggro sound")
STATE.threat = {}; tick(); updates = 0
dead.party1 = true
fire("UNIT_HEALTH", "party1")
assertEq(hb.statusText.__text, "Dead", "dying shows Dead at once")
assertEq(updates, 1, "by redrawing the bar")
fire("UNIT_HEALTH", "party1")
assertEq(updates, 1, "still dead: nothing more to redraw")
assertEq(hb.statusText.__text, "Dead", "and Dead stays")
dead.party1 = nil
fire("UNIT_MAXHEALTH", "party1")
assertEq(hb.statusText.__text, "50%", "coming back shows health again")
assertEq(updates, 2, "by redrawing the bar")
offline.party1 = true
fire("UNIT_HEALTH", "party1")
assertEq(hb.statusText.__text, "Off", "going offline shows Off")
offline.party1 = nil; tick()
TM.db.healthText = false
hb.statusText.__text = "stale"
fire("UNIT_HEALTH", "party1")
assertEq(hb.statusText.__text, "stale", "aggro words are left to the threat updates")
TM.UpdateButton = realUpdateButton
UnitIsDeadOrGhost, UnitIsConnected = realDead, realConnected
TM.db.aggroSound = false
tick()

step("a role icon moves the name only when it changes")
local nameMoves = 0
local nameText = TM.unitToButton.party1.nameText
local realClear = nameText.ClearAllPoints
nameText.ClearAllPoints = function(...) nameMoves = nameMoves + 1 return realClear(...) end
STATE.roles.party1 = "HEALER"; TM.db.roleIcons = true
tick(); tick(); tick()
assertEq(nameMoves, 1, "moved once when the icon appeared")
assertEq(TM.unitToButton.party1.roleIcon.__shown, true, "icon shown")
STATE.roles.party1 = "TANK"; tick(); tick()
assertEq(nameMoves, 2, "and once when the role changed")
TM.db.roleIcons = false; tick(); tick()
assertEq(nameMoves, 3, "and once when icons were turned off")
assertEq(TM.unitToButton.party1.roleIcon.__shown, false, "icon hidden")
nameText.ClearAllPoints = nil
STATE.roles = {}; TM.db.roleIcons = true; tick()

step("nameplates that appear before the bars are built are still marked")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
TM.built = false   -- as after a /reload in the middle of a fight
fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
TM.built = true
MOB_TARGET = { nameplate9 = "party1" }
TM:UpdatePlateMarks()
assertEq(PLATES.nameplate9.tmForeverMark.__shown, true, "marked once the bars exist")
-- One member's answer hidden, another's readable: no stale logo is left showing
SECRET_MODE = true; local hiddenFalse = UnitExists("nobody"); SECRET_MODE = false
local realUnitIsUnit = UnitIsUnit
UnitIsUnit = function(a, b)
    if a == "nameplate9target" and b == "party2" then return hiddenFalse end
    if a == "nameplate9target" then return false end
    return realUnitIsUnit(a, b)
end
TM:UpdatePlateMarks()
local mark9 = PLATES.nameplate9.tmForeverMark
assertEq(mark9.__shown, true, "mixed answers: the mark frame shows, the game sets the alpha")
assertEq(mark9.layers[1].__shown, false, "the layer for the member it's known not to be on is hidden")
assertEq(mark9.layers[2].__shown, true, "the layer for the hidden answer is shown")
UnitIsUnit = realUnitIsUnit
fire("NAME_PLATE_UNIT_REMOVED", "nameplate9")
MOB_TARGET = {}

step("a damaged settings file falls back to defaults")
local saved = { point = TM.db.point, width = TM.db.width, classColors = TM.db.classColors }
TauntMasterForeverDB.point = "middle"
TauntMasterForeverDB.width = "wide"
TauntMasterForeverDB.classColors = 1
TauntMasterForeverDB.bindings = false
fire("ADDON_LOADED", ADDON)
assertEq(type(TM.db.point), "table", "position is a table again")
assertEq(TM.db.point[1], "CENTER", "default anchor")
assertEq(TM.db.point[3], -300, "default offset")
assertEq(TM.db.width, 120, "default width")
assertEq(TM.db.classColors, true, "default switch")
assertEq(type(TM.db.bindings), "table", "bindings table")
TM.db.point = { "TOPLEFT", "BOTTOMLEFT" }   -- half a position
fire("ADDON_LOADED", ADDON)
assertEq(TM.db.point[1], "TOPLEFT", "what's valid is kept")
assertEq(TM.db.point[4], 0, "what's missing is filled in")
TM:ApplySettings(); SlashCmdList.TAUNTMASTERFOREVER("reset")
assertEq(TM.unitToButton.party1.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "default bindings are back")
TM.db.width, TM.db.classColors = saved.width, saved.classColors
TM:ApplySettings()

step("class taunts in the player's language")
-- A German client: the game calls Growl "Knurren"
KNOWN.Knurren, KNOWN.Growl = KNOWN.Growl, nil
KNOWN.Knurren.name = "Knurren"
LOCAL_NAMES[6795] = "Knurren"
assertEq(TM:DefaultBindings()["1"].text, "Knurren", "new defaults use the local name")
assertEq(TM:DefaultBindings()["2"].text, "Challenging Roar", "falls back to English when the game gives no other name")
-- A binding saved in English becomes the local name at login; others are left alone
TM.db.bindings.DRUID = { ["1"] = { kind = "enemy", text = "Growl" }, ["2"] = { kind = "self", text = "Bear Form" } }
TM:LocalizeBindings()
assertEq(TM:GetBindings()["1"].text, "Knurren", "saved English taunt translated")
assertEq(TM:GetBindings()["2"].text, "Bear Form", "other spells unchanged")
assertEq(TM:GetSpellInfo("knurren").spellID, 6795, "found by its local name")
KNOWN.Growl, KNOWN.Knurren = KNOWN.Knurren, nil
KNOWN.Growl.name = "Growl"
LOCAL_NAMES = {}
TM:LocalizeBindings()
assertEq(TM:GetBindings()["1"].text, "Knurren", "an English client never rewrites names it can't find")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()
assertEq(TM:GetBindings()["1"].text, "Growl", "English client: English names")

step("lost aggro warning")
local realThreat = UnitThreatSituation
local targetThreat
UnitThreatSituation = function(u, mob) if mob == "target" then return targetThreat end return realThreat(u) end
local realAfter = C_Timer.After
local later = {}
C_Timer.After = function(_, fn) later[#later + 1] = fn end
local h = TM.handle
TM.db.aggroSound = true
local logBefore = #LOG
targetThreat = 3; tick()
targetThreat = 3; tick()
assertEq(h.text:GetText(), "TauntMaster", "no warning while you hold it")
targetThreat = 1; tick()
assertEq(h.text:GetText(), "Lost aggro!", "header warns when the mob turns away")
assertEq(h.alertAnim.__playing, true, "header pulses")
local played = false
for i = logBefore + 1, #LOG do if LOG[i]:find("^SOUND") then played = true end end
assert(played, "aggro sound plays with the warning")
for _, fn in ipairs(later) do fn() end; later = {}
assertEq(h.text:GetText(), "TauntMaster", "back to the name after a few seconds")
assertEq(h.alertAnim.__playing, false, "pulse stops")
-- Switching targets, hidden threat and an orange (still tanking) mob don't warn
targetThreat = 3; tick(); targetThreat = 0; fire("PLAYER_TARGET_CHANGED"); tick()
assertEq(h.text:GetText(), "TauntMaster", "a new target is not a loss")
targetThreat = 3; tick(); targetThreat = 2; tick()
assertEq(h.text:GetText(), "TauntMaster", "still tanking (orange) is not a loss")
targetThreat = 3; tick(); SECRET_MODE = true; targetThreat = UnitExists("player"); SECRET_MODE = false; tick()
assertEq(h.text:GetText(), "TauntMaster", "hidden threat: no guess")
targetThreat = 3; tick(); targetThreat = nil; tick()
assertEq(h.text:GetText(), "TauntMaster", "combat over: no warning")
TM.db.lostAggro = false; targetThreat = 3; tick(); targetThreat = 0; tick()
assertEq(h.text:GetText(), "TauntMaster", "can be turned off")
TM.db.lostAggro = true; TM.db.aggroSound = false
UnitThreatSituation = realThreat; C_Timer.After = realAfter; targetThreat = nil

step("colorblind-friendly aggro colors and aggro word with health %")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
STATE.unitsExist = { player = true, party1 = true, party2 = true }
STATE.threat = { party1 = 3 }
local bar1 = TM.unitToButton.party1
tick()
local function barColor() local c = bar1.bar.__color or {} return c[1] end
local realSetColor = bar1.bar.SetStatusBarColor
bar1.bar.SetStatusBarColor = function(self, r, g, b) self.__color = { r, g, b } end
tick(); assertEq(barColor(), 0.90, "standard red")
TM.db.threatColors = "colorblind"; tick(); assertEq(barColor(), 0.80, "colorblind purple")
TM.db.threatColors = "nonsense"; tick(); assertEq(barColor(), 0.90, "unknown choice falls back to standard")
TM.db.threatColors = "standard"
bar1.bar.SetStatusBarColor = realSetColor
TM.db.healthText = true; tick()
assertEq(bar1.statusText:GetText(), "50%", "health % alone")
TM.db.aggroWithHealth = true; tick()
assertEq(bar1.statusText:GetText(), "AGGRO 50%", "aggro word beside the health %")
TM:UpdateHealth(bar1)
assertEq(bar1.statusText:GetText(), "AGGRO 50%", "health updates keep the word")
-- Health hidden, threat readable: the game fills in the % after the word
local realHP, realHPMax = UnitHealth, UnitHealthMax
SECRET_MODE = true; local hidden50 = UnitHealth("party1"); SECRET_MODE = false
UnitHealth = function() return hidden50 end
UnitHealthMax = function() return hidden50 end
local realPct = UnitHealthPercent
UnitHealthPercent = function() return hidden50 end
tick()
assertEq(bar1.statusText.__fmt, "AGGRO %.0f%%", "hidden health formatted after the word")
UnitHealth, UnitHealthMax, UnitHealthPercent = realHP, realHPMax, realPct
STATE.threat = {}; tick()
assertEq(bar1.statusText:GetText(), "50%", "no word without aggro")
TM.db.healthText, TM.db.aggroWithHealth = false, false; tick()
-- The new choices are on the Appearance and Alerts tabs
TM:OpenConfig("appearance")
local seen = {}
walk(win, function(f) if f.__text then seen[f.__text] = true end end)
assert(seen["Keep the aggro word beside it"] and seen["Aggro colors"] and seen["Standard"], "appearance controls")
assert(seen["Warn when you lose aggro on your target"], "lost aggro switch")
assert(seen["This character uses its own settings"], "own settings switch")
TM:OpenConfig()

step("per-character settings")
local account = TM.accountDB
TM.charDB.settings = nil   -- the switch test above already made a copy
TM.db.width = 150; TM:ApplySettings()
assertEq(TM:UsesOwnSettings(), false, "shared by default")
TM:SetOwnSettings(true)
assert(TM.db ~= account, "own table")
assertEq(TM.db.width, 150, "starts as a copy of the shared settings")
TM.db.width = 90; TM:ApplySettings()
assertEq(account.width, 150, "shared settings untouched")
assertEq(TM.unitToButton.party1.__size[1], 90, "bars use this character's settings")
TM.db.bindings.DRUID["1"] = { kind = "enemy", text = "Taunt" }; TM:ApplyBindings()
assertEq(account.bindings.DRUID["1"].text, "Growl", "click bindings are separate too")
TM:SetOwnSettings(false)
assertEq(TM.db, account, "back to shared")
assertEq(TM.unitToButton.party1.__size[1], 150, "bars follow")
assertEq(TM.unitToButton.party1.__attrs.macrotext1, "/cast [@party1target,harm,nodead] Growl", "shared bindings back")
TM:SetOwnSettings(true)
assertEq(TM.db.width, 90, "own settings kept while switched off")
-- Saved own settings load next session, filled in with defaults
fire("ADDON_LOADED", ADDON)
assertEq(TM.db.width, 90, "own settings loaded")
assertEq(TM.db.lostAggro, true, "new settings filled in")
TauntMasterForeverCharDB = { ownSettings = true, settings = "broken" }
fire("ADDON_LOADED", ADDON)
assertEq(TM.db, TM.accountDB, "a damaged character file falls back to shared settings")
TM:SetOwnSettings(false)
TM.db.width = 120; TM:ApplySettings()

step("chat lines start with the logo and name")
local from = #LOG
SlashCmdList.TAUNTMASTERFOREVER("help"); SlashCmdList.TAUNTMASTERFOREVER("check"); SlashCmdList.TAUNTMASTERFOREVER("debug")
assert(#LOG > from + 10, "commands printed")
for i = from + 1, #LOG do
    if not LOG[i]:find("^SOUND") then
        assert(LOG[i]:find(ns.Theme.CHAT_PREFIX, 1, true) == 1, "chat line without the prefix: " .. LOG[i])
    end
end

step("only keybinding targets have global names")
assertEq(_G.TauntMasterForever, nil, "no global addon table")
assert(TauntMasterForever_party1 and TauntMasterForever_player and TauntMasterForever_ally and TauntMasterForever_mouseover, "bound buttons named")
for _, b in ipairs(TM.raidButtons) do assertEq(b:GetName(), nil, "raid bars unnamed") end
assertEq(TM.totButton:GetName(), nil, "target's target bar unnamed")
assertEq(TM.main:GetName(), nil, "main frame unnamed")

step("zone change")
STATE.inGroup, STATE.inRaid, STATE.party = true, false, 2
STATE.unitsExist = { player = true, party1 = true, party2 = true }
MOB_TARGET = { nameplate3 = "party2" }
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
assertEq(PLATES.nameplate3.tmForeverMark.__shown, true, "marked before the loading screen")
-- Loading screen: plates go away, then the new zone comes in
fire("NAME_PLATE_UNIT_REMOVED", "nameplate3")
assertEq(PLATES.nameplate3.tmForeverMark.__shown, false, "mark cleared with its plate")
fire("PLAYER_ENTERING_WORLD", false, false)
INSTANCE = true; STATE.party = 1; STATE.unitsExist = { player = true, party1 = true }
fire("GROUP_ROSTER_UPDATE"); tick()
MOB_TARGET = {}; TM:UpdatePlateMarks()
assertEq(PLATES.nameplate3.tmForeverMark.__shown, false, "no stale mark in the new zone")
INSTANCE = false

step("joining a group mid-fight")
STATE.inGroup, STATE.inRaid, STATE.party = false, false, 0
STATE.unitsExist = { player = true }
fire("GROUP_ROSTER_UPDATE"); tick()
COMBAT = true; BLOCKED = {}
STATE.inGroup, STATE.inRaid = true, true
STATE.unitsExist = { player = true, raid1 = true, raid2 = true, raid3 = true, raid4 = true, raid5 = true, raid6 = true }
RAID_GROUPS = { [6] = 2 }
fire("GROUP_ROSTER_UPDATE"); tick()
assertEq(#BLOCKED, 0, "nothing protected touched mid-fight: " .. table.concat(BLOCKED, ", "))
assert(TM.pending and TM.pending.fns.layout, "raid layout waits for the fight to end")
COMBAT = false; fire("PLAYER_REGEN_ENABLED")
assertEq(TM.pending, nil, "applied after the fight")
assertEq((pos("raid6")), TM.db.width + TM.db.spacing, "raid6 laid out in group 2's column")
STATE.inGroup, STATE.inRaid, STATE.party = false, false, 0; RAID_GROUPS = {}
STATE.unitsExist = { player = true }; fire("GROUP_ROSTER_UPDATE")
print("ALL TESTS PASSED")
