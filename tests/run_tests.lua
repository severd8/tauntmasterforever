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
TM:ApplyFonts(); TM:RequestLayout()
assertEq(TM.cdIcons[1].__size[1], 20, "icons resize in combat")
assertEq(#BLOCKED, 0, "nothing protected touched in combat")
COMBAT = false; fire("PLAYER_REGEN_ENABLED")
assertEq(TM.totButton.__pos[2], 38, "bar repositioned after combat")
TM.db.cdIconSize = 26; TM.db.showToT = false; TM:ApplySettings()

step("secret mode")
SECRET_MODE = true
runScenario("hidden values")
SECRET_MODE = false

step("options window: every tab, check, slider, cycle, button")
TM:OpenConfig()
local win = TauntMasterForeverConfig
assert(win and win.__shown, "window open")
for _, page in ipairs({ "general", "advanced", "spells", "extras", "display", "bindings" }) do TM:OpenConfig(page) end
local function walk(f, fn) fn(f) for _, c in ipairs(f.__children or {}) do walk(c, fn) end end
local clicked, slid = 0, 0
walk(win, function(f)
    if f.__kind == "CheckButton" and f.__scripts.OnClick then
        f:SetChecked(not f:GetChecked()); f.__scripts.OnClick(f); clicked = clicked + 1
        f:SetChecked(not f:GetChecked()); f.__scripts.OnClick(f)
    elseif f.__kind == "Slider" and f.__scripts.OnValueChanged then
        f.__scripts.OnValueChanged(f, 17); f.__scripts.OnValueChanged(f, 12); slid = slid + 1
    elseif f.__kind == "Button" and f.__scripts.OnClick and f.__text ~= "Close" then
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
for _, e in ipairs(menu.entries) do if e.text == "Custom spell..." then e.fn() end end
assertEq(POPUPS[#POPUPS].name, "TAUNTMASTERFOREVER_CUSTOM", "custom popup")
-- Accept the popup with typed text
local popup = { data = "1" }
local eb = { GetText = function() return "  Taunt  " end }
popup.GetEditBox = function() return eb end
StaticPopupDialogs.TAUNTMASTERFOREVER_CUSTOM.OnAccept(popup, "1")
assertEq(TM:GetBindings()["1"].text, "Taunt", "custom spell trimmed and saved")
TM.db.bindings.DRUID = TM:DefaultBindings(); TM:ApplyBindings()

step("click bindings: validation and autocomplete")
TM:OpenConfig("spells")
local rows = TM._spellRows
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
FAKE_TIME = FAKE_TIME + 3

step("keybindings and controller support")
-- Every binding in Bindings.xml has a readable name
local f = assert(io.open(ADDON_DIR .. "/Bindings.xml")); local xml = f:read("*a"); f:close()
local count = 0
for name in xml:gmatch('name="([^"]+)"') do
    count = count + 1
    assert(_G["BINDING_NAME_" .. name], "missing binding name for " .. name)
end
assertEq(count, 12, "12 keybindings")
-- Own section in the Keybindings menu, like other addons
local cats = {}
for c in xml:gmatch('category="([^"]+)"') do cats[#cats + 1] = c end
assertEq(#cats, 12, "every binding has a category")
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
assertEq(splash.check:GetChecked(), false, "checkbox reflects setting")
splash.check:SetChecked(true); splash.check.__scripts.OnClick(splash.check)
assertEq(TM.db.showSplash, true, "checkbox turns it back on")
SlashCmdList.TAUNTMASTERFOREVER("news"); assertEq(splash.__shown, false, "/tm news closes it")
local esc = false
for _, n in ipairs(UISpecialFrames) do if n == "TauntMasterForeverSplash" then esc = true end end
assert(esc, "Escape closes the splash")
-- News list stays in sync with the changelog
local cf = assert(io.open(ADDON_DIR .. "/CHANGELOG.md")); local topVersion = cf:read("*a"):match("## ([%d%.]+)"); cf:close()
assertEq(TM:CurrentNewsVersion(), topVersion, "News.lua top version matches CHANGELOG.md")
for _, e in ipairs(TM.NEWS) do assert(e.version and e.date and #e.items > 0, "news entry complete") end

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

print("ALL TESTS PASSED")
