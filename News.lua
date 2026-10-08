-- Short "What's new" lines for the splash screen (Splash.lua), newest first.
-- Add an entry here with every release, matching the top version in CHANGELOG.md
-- (a test fails if they don't match).

local _, ns = ...
local TM = ns.TM

TM.NEWS = {
    { version = "1.14.3", date = "2026-10-08", items = {
        "Under the hood: one shared look for all four Forever addons. Nothing changes in the game.",
    } },
    { version = "1.14.2", date = "2026-10-06", items = {
        "New logo on the CurseForge page. Nothing changes in the game.",
    } },
    { version = "1.14.1", date = "2026-10-04", items = {
        "New logo: the shield in a gold ring, like the other Forever addons.",
    } },
    { version = "1.14.0", date = "2026-10-03", items = {
        "The header above the bars shows the logo. ToppedOff Forever and Outfitter Forever now share this look.",
    } },
    { version = "1.13.3", date = "2026-10-03", items = {
        "Fixes for settings changed during a fight and for nameplate marks after a /reload in combat. Lighter in raids.",
    } },
    { version = "1.13.2", date = "2026-10-01", items = {
        "Clearer option text for nameplate marks and /tm reset.",
    } },
    { version = "1.13.1", date = "2026-09-30", items = {
        "The bar header keeps the same look when locked.",
    } },
    { version = "1.13.0", date = "2026-09-30", items = {
        "Nameplate marks: the logo appears over mobs attacking your healer or DPS. Click the mob to taunt it.",
        "New option (off by default): backup taunt when a player has a friend targeted instead of an enemy.",
    } },
    { version = "1.12.2", date = "2026-09-30", items = {
        "Taunt cooldown icons now show and hide correctly in dungeons.",
    } },
    { version = "1.12.1", date = "2026-09-29", items = {
        "Bug fixes: range fading in instances, Say/Yell announcements, unlearned taunts, Targeted ally keybindings.",
    } },
    { version = "1.12.0", date = "2026-09-29", items = {
        "Redesigned options window with tabs, switches and dropdown menus.",
        "Aggro \"Volume slider\" is now \"Sound channel\" (Master, Sound Effects or Dialog).",
        "New logo on the minimap button, and one consistent look everywhere.",
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
