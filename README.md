# TauntMaster Forever

**Click a party member's bar to taunt their target off them.**

TauntMaster Forever is a tanking addon for **World of Warcraft: Forever**. It shows a bar for every member of your party or raid, colors each bar by how much threat that player has, and lets you rescue them with one click — no targeting, no macros, no fumbling.

It's a from-scratch rebuild of the classic *TauntMaster* addon, written for Forever's modern addon rules.

---

## Features

- **Aggro at a glance** — every bar changes color with that player's threat:
  - **Grey** — fine
  - **Yellow** — has more threat than the tank
  - **Orange** — is being attacked, but isn't firmly holding the mob
  - **Red** — has aggro
- **Click to taunt** — click a member's bar and your taunt is cast on *their* target. Your own target never changes.
- **Every mouse button and modifier is bindable** — Left, Right and Middle click, each with Shift, Ctrl and Alt. Bind a spell, a macro, assist, or target.
- **Taunt picker** — choose from every taunt your class has, with icons. Spells you haven't learned yet are marked.
- **Taunt cooldown icons** — see when your taunts are on cooldown, or when they're ready.
- **Low mana warning** — shows next to your bar and your healers' bars when mana drops below the level you choose.
- **Aggro alerts** — optional flashing bar and sound when someone else pulls a mob.
- **Target's target bar** — see who your target is hitting, and click it to taunt your target.
- **Raid support** — raid bars are grouped by raid group.
- **Extras** — health %, range fading, role icons, sort by role, bar textures, text sizes, class colors, and a "only show in Defensive Stance / Bear Form" mode.
- **Taunt announcements** — optionally announce your taunts in party, raid, instance or raid warning chat.

## Installation

1. Download the latest release.
2. Unzip it into your WoW: Forever `Interface\AddOns` folder so you end up with an `AddOns\TauntMasterForever\` folder.
   During the beta, that's `World of Warcraft\_classic_beta_\Interface\AddOns\`.
3. Restart the game, or type `/reload` if it's already running.

When you log in you'll see a message like:

> TauntMaster Forever loaded. Growl assigned to Left Click, Challenging Roar assigned to Right Click.

That's it — your class's taunts are set up automatically.

## Default click bindings

| Class | Left Click | Right Click | Shift-Left Click | Ctrl-Left Click | Middle Click |
|---|---|---|---|---|---|
| Warrior | Taunt | Mocking Blow | Challenging Shout | Assist | Target |
| Druid | Growl | Challenging Roar | — | Assist | Target |
| Paladin | Judgement\* | — | Blessing of Protection | Assist | Target |

\*Judgement only taunts while **Seal of Fury** is active.

Taunts cast on "their target" go to the enemy the clicked player is fighting. Blessing of Protection is cast on the clicked player.

## Using it

- **Move the bars** — drag the orange header. Lock them in place from the header's right-click menu or the options.
- **Open the options** — type `/tm`, left-click the minimap button, or right-click the header and choose **Settings**.
- **Show or hide the bars** — right-click the minimap button, or type `/tm toggle`.

### Options window

| Tab | What's there |
|---|---|
| **General** | Bar size, units per column, max columns, Left/Right Click spells, minimap icon, lock, hide when solo, low mana warning, taunt cooldown icons |
| **Advanced** | Show bars, show in raids, include yourself, class colors, spacing, scale, text sizes, taunt announcements, reset position |
| **Click Bindings** | Every mouse button and modifier, with spell names or macros |
| **Extras** | Aggro sound and flash, health %, range fade, role icons, sort by role, bar texture, target's target, tank-stance-only mode |

In a custom macro, `{unit}` is replaced with the clicked player (for example `/cast [@{unit}target] Growl`).

### Slash commands

| Command | Does |
|---|---|
| `/tm` | Open or close the options |
| `/tm show` · `/tm hide` · `/tm toggle` | Show or hide the bars |
| `/tm lock` · `/tm unlock` | Lock or unlock the bars' position |
| `/tm display` · `/tm advanced` · `/tm spells` · `/tm extras` | Open a specific options tab |
| `/tm check` | Check that your bound spells exist and are learned |
| `/tm reset` | Move the bars back to the middle of the screen |

`/tauntmaster` works too.

## Good to know

WoW: Forever runs on the modern addon system, which hides some combat information from addons. TauntMaster Forever is built around those rules:

- **It never acts on its own.** Every taunt is your click. Addons can't auto-taunt.
- **Hidden values are handled by the game.** Things like your mana and party health are shown through the game's own display, so the addon never needs to read the numbers.
- **Some changes wait until combat ends.** WoW doesn't let addons move or rearrange clickable bars during combat. If you change the layout, resize bars, or someone changes raid group mid-fight, the bars update as soon as combat ends. Colors, text and alerts always update live.
- **Say and Yell announcements** only work inside instances — that's a WoW rule for chat sent from a click.
- **Tank-stance-only mode** does nothing for Paladins, since they don't have a tank stance.

## Troubleshooting

- **A click does nothing** — type `/tm check`. It lists each bound spell and whether it was found and learned. Fix any misspelled spell on the **Click Bindings** tab.
- **The bars disappeared** — you may have hidden them, or turned on **Hide When Solo** or tank-stance-only mode. Type `/tm show`.
- **The bars are off-screen** — type `/tm reset`.

## Feedback and bug reports

Found a bug or have an idea? Please [submit it on GitHub](https://github.com/severd8/tauntmasterforever/issues/new/choose). A short form asks for your class, group type and any error message, so issues can be fixed quickly. You'll need a free GitHub account. Otherwise, feel free to leave a comment on the CurseForge page.

## Support the addon

TauntMaster Forever is free. If it has saved your group a wipe, you can [leave a small tip on PayPal](https://www.paypal.com/donate/?business=HN2BMEG53YUJW&no_recurring=0&currency_code=USD). Thank you!

## Credits

Special thanks to **Classic Mistake** in WoW Forever for their help with the initial testing.

Inspired by the original *TauntMaster* addon by prodigy. TauntMaster Forever is a separate, from-scratch rebuild and isn't affiliated with the original.

## License

MIT — see [LICENSE](LICENSE).
