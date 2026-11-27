# AntiGrief

A loot helper for **WoW: Forever**. AntiGrief scans your group's gear and tells you when someone rolls Need on an item that doesn't suit them: a warrior on a caster dagger, a mage on plate, a level 52 on a level 58 item, or something far worse than what they already wear.

Alerts are **private by default**. Only you see them, unless you turn on group announcements.

## What it does

- **Flags misfit Need rolls.** It checks the item against the roller's class, armor and weapon skills, level, stats and equipped gear. Each finding is rated Low, Medium or High, and you choose which level alerts you.
- **Follows up on the win.** If the flagged player wins the item, you get a chat line and the raid-warning sound.
- **Checks they equip it.** About 2 minutes after a flagged win, once nobody is fighting, it looks at the winner's gear again. If the item still isn't equipped, you get an alert with an alarm sound.
- **Fit report on new drops.** When an item drops, it lists who in the group it suits and who it doesn't. This one is only in your chat.
- **Shows fit on roll windows and tooltips.** A small badge under the loot roll window and an extra tooltip line show who the item suits.
- **Keeps a log.** Every flag, win and equip check is saved. You can review it in the log window, filter it by player or severity, and see per-player totals.
- **Counts repeats.** A player's second flag in the same dungeon is called out as such.

## A flag is a hint, not proof

There are honest reasons to Need an item that looks wrong: an off-spec set, a friend in the group the item was won for (Bind on Pickup items can be traded for 2 hours), or gear saved to put on after the pull. Talk to people before you kick them. Group announcements are off by default and use neutral wording ("doesn't look like a fit").

## Install

1. Download the zip and extract it into `World of Warcraft\_forever_\Interface\AddOns\`, so that the folder `AddOns\AntiGrief\` contains `AntiGrief.toc`.
2. Restart the game or type `/reload`.

[Pawn](https://www.curseforge.com/wow/addons/pawn) is optional. If it's installed, AntiGrief uses Pawn's scales for the upgrade check instead of item level.

## Commands

`/ag` or `/antigrief` lists everything. The common ones:

| Command | What it does |
| --- | --- |
| `/ag config` | Open the options panel (also in Esc > Options > AddOns) |
| `/ag status` | Settings and scan progress |
| `/ag on` / `/ag off` | Enable or disable |
| `/ag log` | Open the log window |
| `/ag test <shift-click an item>` | Judge an item against your group |
| `/ag sev 1-3` | Lowest severity that alerts (1 Low, 2 Medium, 3 High) |
| `/ag ignore <name>` | Never flag this player (again to undo) |
| `/ag sound`, `screen`, `announce`, `drops`, `pawn`, `minimap`, `tooltip`, `badge`, `friends` | Toggle a setting |
| `/ag feedback` | Discord link for feedback and bug reports |

The minimap button opens the log and the settings too. Tip: create a chat tab named **AntiGrief** and all of the addon's messages go there.

## Settings worth knowing

- **Minimum severity** (default Medium): lower findings are still logged, just not alerted.
- **Play sound** (default on): the raid-warning horn when a flagged player wins the item, and an alarm when they still haven't equipped it. Need rolls themselves make no sound.
- **Announce to group** (default off): posts a one-line note to party, raid or instance chat, at most one message every 30 seconds.
- **Don't flag friends or guildmates** (default on).

## Language support

Loot messages are read with the game's own strings, so Need detection works in every client language. The check of an item's stat and "Equip:" text is English only, and other client languages skip it.

## Feedback

Bug reports and ideas are welcome on Discord: <https://discord.gg/3GSsbDWWbM> (or type `/ag feedback` in game).

## License

MIT, see [LICENSE](LICENSE).
