-- Eigene Zusatz-Routen von Ultima.
-- Schlafsack-Questreihe "Cozy Sleeping Bag", ab Level 14, Quelle: Warcraft Tavern, Cozy Sleeping Bag Guide,
-- und Warcraft Wiki "...and that note you found" (Quest 79008 Allianz, 79007 Horde, Westfall 37,5 / 50,7).
-- Für Stonetalon und Hillsbrad nennen die Quellen keine Koordinaten: dort führt Ultima nur in die Zone.
-- Die Routen werden erst nach dem Laden der Einstellungen gebaut (ns.BuildExtraRoutes), damit Hinweise und
-- Name in der gewählten Sprache erscheinen. Die ID bleibt fest (gespeicherte Fortschritte hängen daran).
local _, ns = ...
local L = ns.L

local WESTFALL, BARRENS, LOCH_MODAN, STONETALON, HILLSBRAD = 1436, 1413, 1432, 1442, 1424

local function Common()
    return {
        { a = { { "zone", to = "Stonetalon Mountains", zm = STONETALON }, { "turnin", q = 79192 }, { "accept", q = 79980 } },
          h = { L["Pocket Litter: camp on a path in the hills near {friendly:Sun Rock Retreat}"] } },
        { a = { { "turnin", q = 79980 }, { "accept", q = 79974 } },
          h = { L["Mound of Dirt: directly east of the camp"] } },
        { a = { { "goto", m = LOCH_MODAN, x = 49, y = 12, r = 12 }, { "turnin", q = 79974 }, { "accept", q = 79975 } },
          h = { L["Carved Figurine at {friendly:Stonewrought Dam}: jump onto the ledge at the dam wall"] } },
        { a = { { "zone", to = "Hillsbrad Foothills", zm = HILLSBRAD }, { "turnin", q = 79975 }, { "accept", q = 79976 } },
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
            { a = { { "goto", m = WESTFALL, x = 37.5, y = 50.7, r = 8 }, { "accept", q = 79008 } },
              h = { L["Alexston Farmstead in Westfall: click the board or the burned remains"] } },
            { a = { { "goto", m = BARRENS, x = 46, y = 74, r = 8 }, { "turnin", q = 79008 }, { "accept", q = 79192 } },
              h = { L["{friendly:Burned-Out Remains} in the south of The Barrens"] } }),
        Route("H",
            { a = { { "goto", m = BARRENS, x = 46, y = 74, r = 8 }, { "accept", q = 79007 } },
              h = { L["{friendly:Burned-Out Remains} in the south of The Barrens, south of Camp Taurajo"] } },
            { a = { { "goto", m = WESTFALL, x = 37.5, y = 50.7, r = 8 }, { "turnin", q = 79007 }, { "accept", q = 79192 } },
              h = { L["Alexston Farmstead in Westfall"] } }),
    }
end
ns.SLEEPING_BAG_ROUTE = { Alliance = "A:extra:Schlafsack-Questreihe", Horde = "H:extra:Schlafsack-Questreihe" }
