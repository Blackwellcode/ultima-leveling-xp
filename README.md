# Ultima Leveling XP

Leveling companion for **WoW Forever** (Interface 16001): step-by-step routes from level 1 to 60 for
Alliance and Horde, a navigation arrow, a travel planner, bonus tracking and leveling talents right in
your talent window. Free, no ads, available in 10 languages.

## Features

- **Routes 1–60** for Alliance and Horde, plus dungeon, survival and AoE routes. The addon picks the
  route that fits your level and continues on its own; finished quests and steps are detected.
- **Arrow** with distance and time to arrival, floor hints (upstairs/downstairs) and corpse runs.
- **Travel planner**: suggests flights and your Hearthstone when they save time. Only flight paths
  you know are used.
- **Bonuses**: tiles for Rested, Well Fed, sleeping bag and camp; warns when a bonus runs out and
  finds buff food in your bags.
- **Warnings** about dangerous enemies and high-level group members.
- **Automation** (optional, hold Shift to pause): accepts and turns in route quests (never picks a
  reward for you), buys the spells a step asks for at the trainer, picks the flight destination.
- **Buttons**: quest item button and target button for the step's NPC or enemy.
- **Map and nameplates**: markers on world map and minimap, quest and level markers on nameplates.
- **Leveling talents**: when you open your talent window, every talent of the chosen build shows its
  target rank (green = done, yellow = open, red = differs), the next point glows, and a card next to
  the window lists your next points. Builds for all classes, chosen automatically or by you.
- **Professions**: steps like "farm until Cooking 10" are skipped when your skill is already higher.
- **Options** for everything (`/ultima options` or right-click the minimap button), window scales
  automatically with your resolution.
- **Languages**: English, German, French, Spanish, Italian, Portuguese, Russian, Korean, Simplified
  and Traditional Chinese. The interface follows your game client unless you pick a language.

## Installation

Download `UltimaLevelingXP-<version>.zip` from the
[Releases](https://github.com/Blackwellcode/ultima-leveling-xp/releases) page (not the "Source code"
archive) and extract it into `World of Warcraft\_forever_\Interface\AddOns`. You get several folders:

| Folder | Content |
|---|---|
| `UltimaLevelingXP` | the addon |
| `UltimaLevelingXP_A` / `_H` | routes for Alliance / Horde, loaded on demand |
| `UltimaLevelingXP_<language>` | route texts and NPC names for your client language, loaded on demand |

Keep all folders; the addon loads only what your character needs.

## Commands

`/ultima` (or `/ulx`) toggles the window. Further commands:
`options`, `arrow`, `routes`, `auto`, `quests`, `talents`, `border`, `hints`, `language`, `reset`,
`status`, `debug`.

## Development

The repository holds the addon code (`src/`), libraries, graphics, talent data and the offline tests
(`lua tools/test-*.lua`, Lua 5.1 compatible code). The route database is generated separately and
ships only in the release archive.

## Licenses

- Code, interface and graphics: MIT License, see `LICENSE.txt`.
- Route data: CC BY-NC-SA 4.0 (non-commercial, share alike), see `CREDITS.txt` and `LICENSE-DATA.txt`.
- Libraries in `libs\`: their own licenses, see `CREDITS.txt`.

---

## Deutsch

Leveling-Begleiter für **WoW Forever**: Routen von Stufe 1 bis 60 für Allianz und Horde, Pfeil mit
Entfernung und Ankunftszeit, Reiseplaner (Flüge, Ruhestein), Boni im Blick, Warnungen, optionale
Quest-Automatik und Leveling-Talente direkt im Talentfenster. Kostenlos, ohne Werbung, in 10 Sprachen.

Installation: `UltimaLevelingXP-<Version>.zip` unter
[Releases](https://github.com/Blackwellcode/ultima-leveling-xp/releases) herunterladen, nach
`World of Warcraft\_forever_\Interface\AddOns` entpacken, alle Ordner behalten. Bedienung über `/ultima`, Optionen über `/ultima optionen` oder Rechtsklick auf das
Minimap-Symbol.
