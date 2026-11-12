# Changelog

## 2.2.3 (2026-11-12)

- An error in one part of the addon no longer stops the others from reacting to the same event; it is
  shown once in chat (and in BugSack) instead.
- The XP and route bars stop updating every frame once they reach their value; the path network builder
  switches itself off when it is done.
- Quest log changes of group members no longer trigger a route update.
- Quest markers read Questie through a checked adapter: an unsupported Questie version switches the
  markers off and `/ultima status` names the reason. If EllesmereUI nameplates change their layout, the
  markers fall back to the standard nameplates.
- Language options say which client languages still lack route hints or NPC names.
- German: "Gegenstand" and "Lager" instead of English terms.

## 2.2.2 (2026-11-11)

- Author name is now Blackwell Code (addon list, license).
- Download link for the latest version: `UltimaLevelingXP.zip` on the Releases page.
- GitHub forms for bug reports, wrong route steps and ideas.

## 2.2.1 (2026-11-11)

- Path dots and arrow: no more long detours. A path is only used when it is at most 1.5 times the
  straight line; short distances are walked directly.
- The path starts where it is shortest from your position, not at the nearest point behind you.
- Walking paths of different routes that come close are connected, so the network finds more direct ways.
- The path follows you: it is recalculated from your position when you leave it or move on.
- Even spacing of the path dots, recorded zigzags smoothed out.

## 2.2.0 (2026-11-11) - first public release

- Leveling talents: target ranks and the next point in the talent window, a card with build choice
  and the next points, chat reminder for free talent points, option page "Talents", `/ultima talents`.
- Profession checks: steps that ask you to raise a profession are skipped when your skill is already
  high enough.
- Buff food in the bags is detected in every client language.
- Horde: Swamp of Sorrows route no longer offered above its level.
- Options with 8 pages, automatic scaling by resolution, options reachable from the minimap button
  and the window.
- Interface in 10 languages, following the game client unless chosen otherwise.
- Route logic reworked: no more stuck steps, deferred turn-ins, previous route first, travel planner
  with known flight paths and Hearthstone, floor hints.
