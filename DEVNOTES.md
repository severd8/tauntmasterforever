# TauntMaster Forever — developer notes

A tanking addon for **World of Warcraft: Forever** (interface 16001, client 1.60.x). One bar per party/raid member, colored by threat; clicking a bar casts the bound taunt on that member's target. A from-scratch rebuild of the old TauntMaster addon.

- Author: `severd8`.
- CurseForge project ID: **1717418** (in the `.toc` as `X-Curse-Project-ID`).
- License: MIT. Credits in README: tester "Classic Mistake" in WoW Forever; inspired by the original TauntMaster by prodigy.

## Files

- `TauntMasterForever.toc` — `## Version: @project-version@` is filled in by the packager from the git tag. Don't hard-code a version.
- `Core.lua` — everything except the options window: bars, threat colors, click bindings (secure attributes), layout, visibility, low mana warning, cooldown icons, target's target, minimap button, header menu, slash commands, events.
- `News.lua` — short "What's new" lines for the splash screen, newest first. **Add an entry with every release**; its top version must match the top of `CHANGELOG.md` (a test checks this).
- `Splash.lua` — welcome / what's new window. Shows once per new `News.lua` version (and on first install) unless turned off; `/tm news` opens it. Logo is `Media/logo.tga` (128×128).
- `Theme.lua` — the shared look: colors (`C`), `Fill`, `Border`, `Text`, `FlatButton`, `SwitchWidget`, `HeaderGradient`, plus `NAME` ("TauntMaster Forever") and `LOGO`. Every window uses it. Don't use Blizzard templates (UIPanelButtonTemplate etc.); a test fails if one comes back.
- `Options.lua` — the options window: custom-styled (flat dark panels, gold text, red accents; colors from `Theme.lua`) with tabs down the left (`TABS`: Taunts, Click Bindings, Layout, Appearance, Alerts, General). Widgets: `Card`, `Switch`, `Dropdown` (uses `MenuUtil` menus), `FlatSlider`, `FlatEditBox`, `FlatButton`, `SpellSelector`. `TM:OpenConfig(name)` opens a tab; old names (`spells`, `extras`, `advanced`, `display`) are aliases.
- `Bindings.xml` — keybindings (loaded automatically by WoW, not listed in the `.toc`). Each is a `CLICK` binding on a bar (`TauntMasterForever_player`, `_party1`–`_party4`) or the hidden `TauntMasterForever_ally` button, using the made-up mouse buttons `TMLeft`/`TMRight`. Their secure attributes are `*type-tmleft` / `*macrotext-tmleft` etc.; the `*` matches any modifier so controller buttons with modifiers still use the plain Left/Right Click spell. Binding names are set in `Core.lua` (`BINDING_NAME_...`).
- `tests/` — offline test suite (not shipped). `wowstub.lua` fakes the WoW API; `run_tests.lua` holds the scenarios; `run.lua` runs them.
- `CHANGELOG.md` — release notes shown on CurseForge. Newest version at the top.
- `.pkgmeta` — packager config (folder name, changelog, files to leave out of the download).
- `.github/workflows/test.yml` — runs the tests on every push. `release.yml` — on a `v*` tag, runs the tests, then packages and uploads to CurseForge.

## WoW Forever rules the code must follow

Forever runs the modern (Midnight 12.x-style) addon API, not the Classic one.

- **Lua 5.1.** No `goto`, `//`, bitwise operators or `_ENV`.
- **Secret values.** Some API results are hidden from addons: party members' names, class, health and threat can be secret, and the player's own current mana is secret (max mana is readable). Comparing, doing math on, concatenating or truth-testing a secret value throws an error.
  - Always check `IsSecret(v)` **before** any `== nil`, comparison, `and`/`or` test or arithmetic on an API result.
  - Secrets can be passed straight into widgets (`SetText`, `SetFormattedText`, `SetValue`, `SetMinMaxValues`, `SetAlpha`, `SetCooldown`), usually inside `pcall`.
  - The low mana warning uses `UnitPowerPercent` with a step curve from `C_CurveUtil.CreateCurve()` so the game decides visibility.
- **Combat lockdown.** Protected (secure) frames can't be moved, resized, shown/hidden or have attributes changed in combat. Use `TM:RunOutOfCombat(key, fn)`: out of combat it runs `fn` at once; in combat it keeps one `fn` per key (a later request with the same key replaces the earlier one), and they run when combat ends. `TM:Layout()`, `TM:ApplyVisibility()` and `TM:ApplyBindings()` already go through it, so call them freely. The header (`TM.handle`) and main frame count as protected because secure bars are anchored to them.
- **No automation.** Every taunt must come from the player's click. Never auto-taunt or auto-target.
- **Missing APIs seen on Forever:** `Slider:SetObeyStepsOnDrag` doesn't exist (guard with `if s.SetObeyStepsOnDrag`). Guard any newer API the same way.
- Taunt announcements are sent from Lua, not the click macro: a bar's `PreClick` hook records the clicked binding's spell (`TM:OnBarClick`), and `UNIT_SPELLCAST_SUCCEEDED` for the player sends the message if that spell succeeds within 1.5 seconds (`TM:OnSpellCastSucceeded`). Uses `C_ChatInfo.SendChatMessage` (falls back to `SendChatMessage`) inside `pcall`.
- Tank stance conditions: Warrior Defensive Stance = `[stance:2]`, Druid Bear Form = `[form:1]` (confirmed in game). Paladins have no stance; their taunt is Judgement with Seal of Fury.
- **One list of clicks.** `TM.CLICKS` holds every bindable click (key, label, secure attribute names). The options rows, `/tm check`, the load message and `TM:ApplyBindingsToButton` all walk it; `TM:EachSpellBinding(fn)` visits the ones bound to a spell. `TM.SPELL_KINDS` and `TM.NO_TEXT_KINDS` say which kinds cast a named spell and which need no text.
- **Refreshing a bar.** `TM:UpdateButton` redraws everything (every quarter second from the ticker, on threat changes, and when a bar appears). `UNIT_HEALTH` / `UNIT_MAXHEALTH` only run `TM:UpdateHealth`: the bar and the health %, plus a full redraw when the unit has just died, gone offline or come back (`btn.down`). The name is re-anchored only when the role icon changes (`btn.roleAtlas`).
- **Saved settings** are checked on load: a value whose type doesn't match its default is replaced by the default (`FillDefaults`).

## Testing

Run from the repo root before every commit:

    lua5.1 tests/run.lua

It loads the addon against the fake WoW API and exercises login, macros, visibility, grouping, raids by group, combat lockdown (fails if a protected frame is touched in combat), hidden-value mode, every options control, the spell picker, header menu, slash commands and minimap button. Add a scenario to `tests/run_tests.lua` for any new feature. The stub can't detect truth-tests on secret values, so review those by hand.

Things only testable in game: real click-to-taunt in a group, Forever's exact secret-value rules, the right-click menus.

## Releasing

1. Make the change, run the tests, add a new section at the top of `CHANGELOG.md` (e.g. `## 1.7.1`), and add the matching entry at the top of `News.lua`.
2. Commit and push to `main`. The **Tests** workflow must be green.
3. Tag and push the tag: `git tag v1.7.1 && git push origin v1.7.1`. Tags containing `beta` or `alpha` upload as Beta/Alpha files.
4. The **Package and release** workflow runs the tests again, then uploads to CurseForge. Check the Actions tab for a green check and the CurseForge Files page (new files go through CurseForge review).

A tag publishes to players, so only tag a tested commit.
