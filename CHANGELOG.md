# Changelog

## 2.5.1 (2026-11-17)

- Wailing Caverns (Alliance): Smart Drinks is only asked for once you have handed in Raptor Horns; Mebok does
  not offer it before. Without Raptor Horns the dungeon list counts 4 quests and the preparation no longer
  waits at Mebok.

## 2.5.0 (2026-11-17)

- New dungeon preparation for Alliance: Wailing Caverns (Trouble at the Docks, Smart Drinks, Deviate Hides,
  Deviate Eradication, The Glowing Shard), listed after The Deadmines. Every quest is checked to exist for
  the Alliance.
- Riverglades is complete: routes that pull in shared guide parts now contain them (Alliance 38-40 Riverglades
  went from 3 to 181 steps, 42-44 from 4 to 111; also Horde Riverglades and some dungeon routes).
- Route data: class and item notes no longer break step conditions; routes with several follow-up routes
  keep all of them (e.g. Loch Modan leads humans to Westfall); NPC ids no longer show in names and targets.
- Steps where you accept and hand in the same quest, and optional steps, are no longer skipped by mistake;
  dungeon preparation no longer waits for quests of another class.
- Circular waypoint paths start at the right point; side steps stay visible without unlocking earlier
  main steps.
- Route data updated to the latest guide source: new zone Riverglades (Alliance 38-40 and 42-44, Horde
  40-42 and 43-44), new Horde dungeon preparations The Drowned City and Krol'dok Stronghold, reworked
  routes from level 38 to 50, flight points Rog'mar and Farhold Keep.
- Steps for content that does not exist yet on WoW Forever (phase 5, before Naxxramas) are left out.
- Routes for one class or race (e.g. the Hunter route 21-23 Ashenvale/Stonetalon) are only offered to that
  class or race.
- Zephras Isle (levels 1-13): waypoints work again; their map was read as a coordinate.
- Steps that run alongside the main step, or stay pinned, no longer disappear after the first refresh.
- Postponed turn-ins: they come back when you return to their route after a bonus route, and an abandoned
  quest no longer blocks the route.
- Quest progress markers on nameplates and the target frame show again (Questie).
- Ferries: once you reach the dock, the arrow no longer points back to it while the ship sails.
- Restarting a dungeon preparation shows the flight again; the talent card no longer claims early points
  below level 10; the route button switches from the dungeon list to the route list.
- Talents: at the respec level the automatic build choice stays on its build and asks you to respec; builds
  that start at point 6 no longer mark the first 5 points as wrong.
- After a route data update, saved step progress of a changed route is reset instead of pointing at the
  wrong steps (quests you have done are still recognized).
- Travel: flights are only suggested over flight points you know (connecting flights need every stop);
  on a mount the planner uses your riding speed.
- The arrow finds your corpse when it lies in another zone than the graveyard; map pins keep up with your
  progress even when the arrow is hidden.
- Food tile ignores cooking recipes; the dungeon hint counts dungeon quests filed under the zone.
- Waypoint chains (e.g. Ashenvale to Ratchet): a waypoint you passed stays passed. Before, leaving its radius
  sent the arrow back to it, so you ran back and forth at the zone border.
- The arrow shows distance and walking time to the goal along the whole path, not just to the next waypoint.
- Quest giver check: when one step has quests from several NPCs, talking to one of them no longer marks the
  other NPCs' quests as "not offered".
- Dungeon preparation keeps the whole journey (flight, walk, flight point) instead of jumping to the last
  leg. Skip works right away; a skipped quest is collected at the end.
- Back really shows the previous step until you click Skip.
- Postponed turn-ins move with you to the next route: once the quest is done, the turn-in shows up
  there, until you hand it in.
- Optional turn-ins from the route source are handed in when ready and no longer ignored.
- Travel planner: only ferries of your own faction; an old flight destination no longer starts a flight to
  the wrong place; Hearthstone followed by a flight shows both legs; Hearthstone works in non-English
  clients after you visited a flight master; no "Crossing" without a ferry.
- Nameplates: checks protected values before using them, follows the on/off switch on the target frame
  too, redraws after combat.
- The big step line keeps its size after loading screens; long distances fit their column; the travel
  line no longer runs into the next mark; the layout follows the bonus tiles during combat.
- Route type in the options switches the route at once; changing the language says when /reload is needed.
- Welcome window: the first page no longer overlaps (the window grows for longer texts), hiding the whole
  interface no longer counts as seen, and it opens in front of the options window.
- Talents: a missing talent counts once, not per rank; a stored build that no longer exists falls back to
  automatic; the talent card stays on screen.
- Errors caught by Ultima are also passed to the game's error handler (BugSack).

## 2.4.2 (2026-11-15)

- The navigation arrow shows the house colours: orange on the way, green when you are close. Its texture
  still carried the old turquoise, and the colour on top mixed with it since 2.3.0.

## 2.4.1 (2026-11-14)

- Sleeping bag quest chain no longer reports itself finished halfway: its steps follow one another and are
  never skipped or postponed.
- Quest chains: if a later part of a chain is in your quest log or done, Ultima counts the earlier parts as
  done too and continues where you are in the chain (for example The Defias Brotherhood).
- The arrow skips places where nothing is left to do: if you already have the quest from the first quest
  giver of a step, it leads straight to the next one.
- Dungeon preparation now ends as soon as every quest for the dungeon is in your quest log, then Ultima goes
  back to your leveling route. Quests you skipped still count as missing and Ultima leads you to them.
- Loot instantly: with auto loot on, Ultima picks up everything at once when the loot opens. On by default,
  switch it off in the options under Automation.
- Steps with two quest givers in two places (dungeon preparation, e.g. Shoni and Wilder in Stormwind) now
  name the right person for each waypoint instead of always the first one.
- Quest automation also works with quest givers that show the old greeting list when the game does not
  know a quest's name yet: Ultima then uses the name from its route data.
- Quest automation keeps a short log of its last decisions in the saved data, to find out why it did or
  did not act at a quest giver.
- During a flight the arrow shows the flight and its destination, and the map shows no path back to the
  flight master. Before, the travel planner kept suggesting the flight master the whole flight long.

## 2.4.0 (2026-11-12)

- Everything by button, no commands needed: the window has eight buttons (back, skip, choose route,
  prepare a dungeon, arrow on/off, options, help, fold), each with a tooltip that says what it does.
  They are real buttons now: tiles in a toolbar at the bottom of the window, grouped by purpose, with
  hover, pressed and on states. Options, talent card and the welcome guide use the same buttons. The
  help button opens the welcome guide, which shows every button with its symbol, name and purpose.
- More symbols in the window: every step and action line starts with its symbol (accept, turn in, kill,
  collect, travel ...), the status strip shows the bonus icons, travel legs show boat, flight or Hearthstone.
- Prepare a dungeon: with the gate button pick a dungeon and Ultima collects every quest
  for it, leads you through the dungeon and to the turn-ins, then goes back to your leveling route. The list
  shows how many of the dungeon's quests you have done; hover a dungeon for its quests. "Back to <route>"
  leaves the preparation at any time. Travel legs to quests you already finished are left out.
- Welcome window on the first start of each character, four short pages: a sketch of the window with
  numbered parts and the main features, all buttons explained, your route (professions, dungeons) and the helpers (automation,
  travel planner, arrow, hints, map and nameplate markers, talents). Every switch applies at once.
  Reopen it with the help button.
- Professions along the route, per character: switch off First Aid, Cooking or Fishing and Ultima leaves
  out the trainer visits and skill-up steps and follows the route as if you never learned the profession.
  Quests stay in. Also in the options under Professions.
- Route steps are skipped with a right-click; the tooltip now says so.
- Sleeping bag quest chain: starting it from the status strip no longer ends it at once. A second start
  resumed at the step where you left off; if that quest was not in your log, the chain counted as finished
  and Ultima went straight back to your route. Now every start follows your quest log.
- Sleeping bag quest chain: every stop now has a waypoint (the camp and the Mound of Dirt in Stonetalon, the
  dam in Loch Modan, the ramp at the wall in Hillsbrad), and the Westfall and Barrens spots are more precise.
  The arrow no longer says "At your destination" anywhere in the world.
- Mound of Dirt hint corrected: it lies on the ledge north of the camp, not east of it.
- Steps that only name a zone no longer count as reached while you are outside that zone, so the
  "Nobody here?" hint no longer appears there.
- The arrow hides its empty dial when there is no target.

## 2.3.0 (2026-11-12)

- New look: graphite panel with hairlines instead of rounded cards, Barlow type (shipped with the addon,
  SIL Open Font License), one orange accent that marks what is next.
- Route progress is a rail of ticks on the left edge of the panel; the orange mark sits on your current step.
- The current step reads as one large sentence with distance and walking time as figures on the right;
  further actions show their verb in a column of their own.
- Bonus tiles became a quiet status strip: label above, value below, a word in orange when you can act.
- The arrow sits on a round graphite dial with an orange arrowhead, distance large, time small below it.
- Options window and talent card follow the same style. Labels use sentence case instead of capitals.
- Russian uses the game's Cyrillic font, Korean and Chinese the client font.

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
