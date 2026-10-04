## 1.14.1

- **New logo**: the shield in a gold ring, matching ToppedOff Forever, Outfitter Forever and BattleText Forever. It's the same everywhere the logo shows: the bar header, the settings window, chat lines, the minimap button, the welcome window, nameplate marks and the AddOns list.

## 1.14.0

One look for TauntMaster Forever, ToppedOff Forever and Outfitter Forever.

- The header above the bars now shows the logo beside the name, the same bar ToppedOff Forever has above its icons. The name there is "TauntMaster", so it fits beside the logo on narrow bars.
- Chat lines from TauntMaster Forever start with the logo.
- Nothing else changes: the settings window is the one the other two addons now copy.

## 1.13.3

Under the hood: a code review, with fixes and lighter work in raids. Nothing changes in how the addon looks or is used.

- Fixed: changing settings during a fight queued every change, and all of them were re-applied one after another when the fight ended. Each kind of change is now applied once, with the latest values.
- Fixed: after a `/reload` in the middle of a fight, enemies whose nameplates were already up got no nameplate marks until they left the screen and came back.
- Fixed: a nameplate mark could keep showing a stale logo when the game hid the answer for some group members and not for others.
- A damaged settings file (a setting of the wrong kind) no longer stops the bars from loading; the damaged setting goes back to its default.
- Lighter in raids: a health change now only updates that bar's health, and a nameplate appearing only updates that nameplate.

## 1.13.2

- The Alerts tab explains that you target the marked mob, then taunt it (the mark itself isn't clickable).
- The General tab says `/tm reset` resets the bars' position, since it doesn't center them.

## 1.13.1

- The bar header keeps its red and gold look when locked, like ToppedOff Forever. Lock and unlock from the header's right-click menu.

## 1.13.0

- New: **nameplate marks**. The TauntMaster Forever logo appears over any enemy that's attacking someone other than you or another tank, so you can click it and taunt it, even when that player (like a healer) has no enemy targeted. On by default; turn it off in the Alerts tab. Needs enemy nameplates on (V key).
- New option: **backup taunt when they have no enemy targeted** (Taunts tab, off by default). If the clicked player is targeting a friend, the click taunts what that friend is fighting.
- Fixed: the "Boss Warning" aggro sound played nothing. It now uses the boss emote warning sound, and falls back to another sound if the game doesn't have it.
- The README and description explain why players who target a friend can't be taunted off with a click, and the ways around it.

## 1.12.2

- Fixed: in dungeons, the taunt cooldown icons always showed, ignoring "Show on cooldown" / "Show when ready". The game hides cooldown times there, so the addon now uses the game's on-cooldown flag instead.
- /tm debug now lists your Left Click taunt's cooldown details.

## 1.12.1

- Fixed: bars could stop updating inside instances when range fading was on.
- Fixed: Say and Yell announcements outside instances caused an "Interface action failed" error. They're now skipped there (WoW only allows them inside instances).
- Fixed: taunts you haven't learned yet showed as "not found" instead of "not learned".
- Fixed: the "Targeted ally" keybindings now work the same way as the bar keybindings.
- Fixed: the announcement message is saved as you type, so closing the window mid-edit keeps it.
- Fixed: dragging the header during combat could trigger a blocked-action warning.
- Fixed: the low mana warning now counts you as a healer when you're the only one.
- /tm reset during combat now says the bars will move when combat ends.

## 1.12.0

- Redesigned options window: a custom look with tabs down the left side (Taunts, Click Bindings, Layout, Appearance, Alerts, General), grouped cards, on/off switches, dropdown menus and cleaner sliders.
- Renamed the aggro "Volume slider" option to "Sound channel". It picks which of WoW's volume settings (Master, Sound Effects or Dialog) the alert follows.
- The General tab lists the slash commands.
- New logo on the minimap button and in the AddOns list.
- One consistent look everywhere: the welcome screen, bar header and autocomplete list now match the options window.
- The addon is called "TauntMaster Forever" everywhere, including chat messages, the bar header and menus.

## 1.11.0

- All settings are now on one scrolling page, divided into sections: Taunt Spells, Layout, Appearance, Aggro Alerts, Reach, Taunt Cooldowns, Low Mana Warning, Announcements, Target's Target, Controller & Keybindings, Click Bindings and General.
- New aggro sound options: choose the sound (with a Test button), when it plays (close to pulling, has aggro, or firmly has aggro), and which volume slider it follows (Master, Sound Effects or Dialog).
- New: turn the welcome screen on or off in the General section.
- Scale now uses a slider. "Hide low mana warning" is now "Show low mana warning".

## 1.10.0

- New: welcome screen with quick-start tips and the latest changes. It shows once after each update (and on first install). Turn it off with the checkbox at the bottom, and reopen it anytime with /tm news.

## 1.9.1

- Keybindings now have their own "TauntMaster Forever" section in Options > Keybindings, like other addons, instead of being listed under AddOns.

## 1.9.0

- New: a red X beside a bar means that player has no enemy targeted, so clicking their bar has nothing to taunt. Their bar also fades.
- Fading now means "your click can't land": their target is out of range of your taunt, or they don't have an enemy targeted.
- New: taunt announcements can name the mob and the player, like "Defias Thug has been taunted off of Aeri!". Use {target} and {player} in the message on the Advanced tab. This is the new default message.
- AoE taunts announce as "Everything nearby has been taunted off of <player>!".

## 1.8.0

- New: controller and keyboard support. Under Options > Keybindings > TauntMaster Forever you can bind a key or controller button to taunt off yourself or any party member, using your Left or Right Click spell.
- New: "Targeted ally" keybindings. Target a friendly player and press it to taunt whatever is attacking them. Works in raids too.
- New: keybinding hints beside each party bar show which button taunts off that player (can be turned off on the Extras tab).
- Keybindings always use the plain Left/Right Click spell, even if your controller button includes a modifier like Shift.

## 1.7.3

- Taunt announcements now go out only when a taunt you clicked on a bar actually casts. Nothing is sent if the spell is on cooldown, out of range or fails, or when you taunt from your action bars.
- Party, raid and instance announcements are skipped quietly when you're not in that kind of group, instead of showing an error.

## 1.7.2

- New: spell names on the Click Bindings tab are checked as you type. A green check means the spell was found, yellow means you haven't learned it yet, and red means no spell has that name. A message under the Save button explains the problem, and opening the tab lists any saved spells that need attention.
- New: autocomplete. Start typing and a list of matching spells from your spellbook appears. Click one, or use the arrow keys and press Tab or Enter.
- Spell names are saved with the game's exact spelling, so "growl" becomes "Growl". This also applies to "Custom spell..." in the General tab.

## 1.7.1

- New: Icon Size slider for the taunt cooldown icons (General tab, under Taunt Cooldowns)
- The target's-target bar moves up to make room for larger icons
- README: added bug report and support links

## 1.7.0 — Initial release

First public release of TauntMaster Forever for WoW: Forever.

- Bars for every party and raid member, colored by aggro (grey, yellow, orange, red)
- Click a member's bar to cast your taunt on their target
- Class taunts set up automatically for Warriors, Druids and Paladins
- Bind any mouse button with Shift, Ctrl or Alt to a spell, macro, assist or target
- Taunt picker with every taunt for your class
- Taunt cooldown icons, shown on cooldown or when ready
- Low mana warning for you and your healers
- Aggro flash and optional aggro sound
- Target's target bar that taunts your own target when clicked
- Raid bars grouped by raid group, with optional sort by role
- Health %, range fading, role icons, class colors, bar textures and text sizes
- Tank-stance-only mode for Defensive Stance and Bear Form
- Optional taunt announcements in chat
- Options window with General, Advanced, Click Bindings and Extras tabs
- Minimap button, header right-click menu and /tm commands
