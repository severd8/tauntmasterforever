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
- **Can your click land?** A bar fades when your taunt can't reach that player's target, and a **red X** beside it means they have no enemy targeted, so clicking won't taunt anything.
- **Nameplate marks** — the TauntMaster Forever logo appears over any enemy that's attacking someone other than you or another tank. Click the marked mob to taunt it. Needs enemy nameplates turned on (V key).
- **Backup taunt** (optional, off by default) — when a player has a friend targeted instead of an enemy, a click taunts what that friend is fighting.
- **Click to taunt** — click a member's bar and your taunt is cast on *their* target. Your own target never changes.
- **Every mouse button and modifier is bindable** — Left, Right and Middle click, each with Shift, Ctrl and Alt. Bind a spell, a macro, assist, or target.
- **Taunt picker** — choose from every taunt your class has, with icons. Spells you haven't learned yet are marked.
- **Taunt cooldown icons** — see when your taunts are on cooldown, or when they're ready.
- **Low mana warning** — shows next to your bar and your healers' bars when mana drops below the level you choose.
- **Aggro alerts** — optional flashing bar and sound when someone else pulls a mob. Pick the sound, when it plays (close to pulling, has aggro, or firmly has aggro) and which sound channel it plays on (Master, Sound Effects or Dialog).
- **Target's target bar** — see who your target is hitting, and click it to taunt your target.
- **Raid support** — raid bars are grouped by raid group.
- **Customizable** — health %, range fading, role icons, sort by role, bar textures, text sizes, class colors, and a "only show in Defensive Stance / Bear Form" mode.
- **Taunt announcements** — optionally announce your taunts in party, raid, instance or raid warning chat, like "Defias Thug has been taunted off of Aeri!". Sent only when the taunt actually casts. Use `{target}` and `{player}` in your own message.

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

Settings are grouped into tabs down the left side of the options window:

| Tab | What's there |
|---|---|
| **Taunts** | Left and Right Click spell pickers, taunt announcements, target's target bar, backup taunt |
| **Click Bindings** | Every mouse button and modifier, with spell names or macros |
| **Layout** | Bar size, columns, spacing, scale, lock, include yourself, show in raids, hide when solo, tank-stance-only mode, sort by role, reset position |
| **Appearance** | Class colors, role icons, health %, bar texture, text sizes |
| **Alerts** | Aggro flash and sound (sound choice with a Test button, when it plays, sound channel), reach fading, low mana warning, taunt cooldown icons, nameplate marks |
| **General** | Keybinding hints, minimap icon, welcome screen, command list |

In a custom macro, `{unit}` is replaced with the clicked player (for example `/cast [@{unit}target] Growl`).

### Controller and keybindings

Prefer a controller, or keys instead of clicking? Go to **Options → Keybindings → TauntMaster Forever** and bind any key or controller button:

| Binding | Does |
|---|---|
| **You / Party 1–4: Left Click spell** | Casts your Left Click spell on that player's target |
| **You / Party 1–4: Right Click spell** | Casts your Right Click spell for that player |
| **Targeted ally: Left / Right Click spell** | Target a friendly player, then press it to taunt whatever is attacking them. Works in raids too. |

Bound keys appear beside each party bar, so you always know which button saves whom. Turn the hints off on the **General** tab of the options.

### Slash commands

| Command | Does |
|---|---|
| `/tm` | Open or close the options |
| `/tm show` · `/tm hide` · `/tm toggle` | Show or hide the bars |
| `/tm lock` · `/tm unlock` | Lock or unlock the bars' position |
| `/tm spells` | Open the options at Click Bindings |
| `/tm check` | Check that your bound spells exist and are learned |
| `/tm news` | Show the welcome / what's new window |
| `/tm reset` | Move the bars back to the middle of the screen |

`/tauntmaster` works too.

## Good to know

WoW: Forever runs on the modern addon system, which hides some combat information from addons. TauntMaster Forever is built around those rules:

- **It never acts on its own.** Every taunt is your click. Addons can't auto-taunt.
- **Hidden values are handled by the game.** Things like your mana and party health are shown through the game's own display, so the addon never needs to read the numbers.
- **Some changes wait until combat ends.** WoW doesn't let addons move or rearrange clickable bars during combat. If you change the layout, resize bars, or someone changes raid group mid-fight, the bars update as soon as combat ends. Colors, text and alerts always update live.
- **Say and Yell announcements** only work inside instances. Outside them, WoW blocks addon Say and Yell messages that aren't sent directly by a key press.
- **Tank-stance-only mode** does nothing for Paladins, since they don't have a tank stance.

## Limitation: players who target a friend

A click taunts **whatever the clicked player has targeted**. WoW doesn't tell addons which mob is attacking a player, and it doesn't let addons pick a target for you in combat.

Healers usually target the tank or whoever they're healing, not the mob hitting them. When that happens, clicking their bar has nothing to taunt, and a **red X** shows beside it. The same goes for anyone who targets another party member.

Ways around it:

- **Nameplate marks** (on by default) put the logo over the mob that's on them. Click it and taunt.
- **Backup taunt** (Taunts tab, off by default) taunts what their friendly target is fighting. It helps when the healer targets a DPS who's fighting that mob, but it isn't always the mob that's on them.
- **Your AoE taunt** (Challenging Roar or Challenging Shout) grabs everything near you.
- **Healers who use mouseover healing** (Clique or mouseover macros) can keep an enemy targeted, so a click on their bar works normally.

## Troubleshooting

- **A click on a healer does nothing** — they probably have a friend targeted, not the mob. See **Limitation** above.
- **A click does nothing** — type `/tm check`. It lists each bound spell and whether it was found and learned. Fix any misspelled spell on the **Click Bindings** tab.
- **The bars disappeared** — you may have hidden them, or turned on **Hide When Solo** or tank-stance-only mode. Type `/tm show`.
- **The bars are off-screen** — type `/tm reset`.
- **No nameplate marks** — turn on enemy nameplates (V key), and check that **Nameplate marks** is on in the **Alerts** tab.

## Feedback and bug reports

Found a bug or have an idea? Please [submit it on GitHub](https://github.com/severd8/tauntmasterforever/issues/new/choose). A short form asks for your class, group type and any error message, so issues can be fixed quickly. You'll need a free GitHub account. Otherwise, feel free to leave a comment on the CurseForge page.

## Support the addon

TauntMaster Forever is free. If it has saved your group a wipe, you can [leave a small tip on Ko-fi](https://ko-fi.com/tauntmasterforever). Thank you!

## Credits

Special thanks to **Classic Mistake** in WoW Forever for their help with the initial testing.

Inspired by the original *TauntMaster* addon by prodigy. TauntMaster Forever is a separate, from-scratch rebuild and isn't affiliated with the original.

## License

MIT — see [LICENSE](LICENSE).
