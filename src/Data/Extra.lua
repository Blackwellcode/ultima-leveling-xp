-- Eigene Zusatz-Routen von Ultima.
-- Schlafsack-Questreihe "Cozy Sleeping Bag", ab Level 14. Quellen: Warcraft Wiki "...and that note you found"
-- (Quest 79008 Allianz, 79007 Horde); Koordinaten aus zwei Guides (Stand 2026-11-12): method.gg "How to Get the
-- Cozy Sleeping Bag In WoW Forever" und wowseer.gg "Cozy Sleeping Bag".
--   Westfall 37.14/50.13, Barrens 46.12/74.32, Stonetalon Lager 40.6/52.4 (wowseer, Zelt), Mound of Dirt 39.6/49.8
--   (beide), Loch Modan 49.45/12.91 (beide), Hillsbrad Rampe an der Mauer 87.36/49.62 (beide). Die Messenger Bag
--   liegt hinter dem Tunnel auf der Mauer (Arathi 22.4/24.2); der Pfeil führt zur Rampe, der Hinweis erklärt den Rest.
-- Die Routen werden erst nach dem Laden der Einstellungen gebaut (ns.BuildExtraRoutes), damit Hinweise und
-- Name in der gewählten Sprache erscheinen. Die ID bleibt fest (gespeicherte Fortschritte hängen daran).
local _, ns = ...
local L = ns.L

local WESTFALL, BARRENS, LOCH_MODAN, STONETALON, HILLSBRAD = 1436, 1413, 1432, 1442, 1424

local function Common()
    return {
        { a = { { "goto", m = STONETALON, x = 40.6, y = 52.4, r = 12 }, { "turnin", q = 79192 }, { "accept", q = 79980 } },
          h = { L["Pocket Litter: camp on a path in the hills near {friendly:Sun Rock Retreat}"] } },
        { a = { { "goto", m = STONETALON, x = 39.6, y = 49.8, r = 8 }, { "turnin", q = 79980 }, { "accept", q = 79974 } },
          h = { L["Mound of Dirt: on the ledge north of the camp, below you"] } },
        { a = { { "goto", m = LOCH_MODAN, x = 49.45, y = 12.91, r = 12 }, { "turnin", q = 79974 }, { "accept", q = 79975 } },
          h = { L["Carved Figurine at {friendly:Stonewrought Dam}: jump onto the ledge at the dam wall"] } },
        { a = { { "goto", m = HILLSBRAD, x = 87.36, y = 49.62, r = 15 }, { "turnin", q = 79975 }, { "accept", q = 79976 } },
          h = { L["Messenger Bag on a wall platform; the cart to climb up stands north of the wall"] } },
        { a = { { "turnin", q = 79976 } },
          h = { L["Click {warn:Hastily Rolled-Up Satchel} right below the Messenger Bag, not just the Messenger Bag"] } },
    }
end

local function Route(faction, first, second)
    local steps = { first, second }
    for _, s in ipairs(Common()) do steps[#steps + 1] = s end
    return { id = faction .. ":extra:Schlafsack-Questreihe", n = L["Sleeping bag quest chain"], f = faction, k = "extra",
        lo = 14, hi = 60, s = steps }
end

function ns.BuildExtraRoutes()
    return {
        Route("A",
            { a = { { "goto", m = WESTFALL, x = 37.14, y = 50.13, r = 8 }, { "accept", q = 79008 } },
              h = { L["Alexston Farmstead in Westfall: click the board or the burned remains"] } },
            { a = { { "goto", m = BARRENS, x = 46.12, y = 74.32, r = 8 }, { "turnin", q = 79008 }, { "accept", q = 79192 } },
              h = { L["{friendly:Burned-Out Remains} in the south of The Barrens"] } }),
        Route("H",
            { a = { { "goto", m = BARRENS, x = 46.12, y = 74.32, r = 8 }, { "accept", q = 79007 } },
              h = { L["{friendly:Burned-Out Remains} in the south of The Barrens, south of Camp Taurajo"] } },
            { a = { { "goto", m = WESTFALL, x = 37.14, y = 50.13, r = 8 }, { "turnin", q = 79007 }, { "accept", q = 79192 } },
              h = { L["Alexston Farmstead in Westfall"] } }),
    }
end
ns.SLEEPING_BAG_ROUTE = { Alliance = "A:extra:Schlafsack-Questreihe", Horde = "H:extra:Schlafsack-Questreihe" }
