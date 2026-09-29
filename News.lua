-- Short "What's new" lines for the splash screen (Splash.lua), newest first.
-- Add an entry here with every release, matching the top version in CHANGELOG.md
-- (a test fails if they don't match).

local ADDON, ns = ...
local TM = ns.TM

TM.NEWS = {
    { version = "1.12.0", date = "2026-09-29", items = {
        "Redesigned options window with tabs, switches and dropdown menus.",
        "Aggro \"Volume slider\" is now \"Sound channel\" (Master, Sound Effects or Dialog).",
    } },
    { version = "1.11.0", date = "2026-09-29", items = {
        "All settings are on one scrolling page, divided into sections.",
        "Aggro sound: choose the sound, when it plays, and which volume slider it follows.",
    } },
    { version = "1.10.0", date = "2026-09-29", items = {
        "Welcome screen with quick-start tips and recent changes. Reopen it with /tm news.",
    } },
    { version = "1.9.1", date = "2026-09-29", items = {
        "Keybindings have their own TauntMaster Forever section.",
    } },
    { version = "1.9.0", date = "2026-09-29", items = {
        "Bars fade when your taunt can't reach; a red X shows who has no enemy targeted.",
        "Announcements name the mob and player: \"Defias Thug has been taunted off of Aeri!\"",
    } },
    { version = "1.8.0", date = "2026-09-29", items = {
        "Controller and keyboard support: bind a button to taunt off any party member.",
    } },
    { version = "1.7.3", date = "2026-09-29", items = {
        "Taunts are only announced when they actually cast.",
    } },
    { version = "1.7.2", date = "2026-09-29", items = {
        "Spell names autocomplete and are checked as you type.",
    } },
    { version = "1.7.1", date = "2026-09-29", items = {
        "Adjustable taunt cooldown icon size.",
    } },
    { version = "1.7.0", date = "2026-09-29", items = {
        "First release.",
    } },
}
