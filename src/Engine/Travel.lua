-- Reiseplaner: liegt das naechste Ziel auf einem anderen Kontinent, waehlt er die Faehre mit dem
-- kuerzesten Gesamtweg (du -> Hafen, Ankunft -> Ziel) und liefert Etappen für Panel und Pfeil.
-- Faehrdaten: UltimaTravelData aus tools/convert.lua (Schiffe, Zeppeline aus den Routen).
local _, ns = ...
local T = {}
ns.Travel = T
local S = ns.State
local L = ns.L

local DOCK_RADIUS = 15        -- Yards: Hafen erreicht
local RIDE_COST = 600         -- Yards-Aequivalent für die Überfahrt, damit kurze Wege zaehlen
-- Faehren ohne Gegenrichtung in den Daten sind oft Fehleintraege ("Schiff nach X" mitten im Land).
-- Sie bleiben moeglich (z. B. Zeppeline der Horde), zaehlen aber deutlich teurer.
local NO_RETURN_PENALTY = 3000
local KIND_NAME = { boat = "Boat", zeppelin = "Zeppelin", tram = "Tram" } -- Schlüssel für ns.L

local docks -- vorbereitete Faehren mit Weltpunkt und Kontinenten

local function Prepare()
    if docks then return docks end
    docks = {}
    for _, t in ipairs(UltimaTravelData or ns.travelData or {}) do
        local x, y, ci = S.WorldPoint(t)
        local destCi = S.ZoneContinent(t.dest)
        if x and ci and destCi and ci ~= destCi then
            docks[#docks + 1] = { t = t, x = x, y = y, ci = ci, destCi = destCi }
        end
    end
    -- Ankunftshafen: Faehre in der Zielzone, die zurück in die Abfahrtszone faehrt
    for _, d in ipairs(docks) do
        for _, back in ipairs(docks) do
            if back.t.m == d.t.dest and back.t.dest == d.t.m and back.t.kind == d.t.kind then
                d.arrival = back
                break
            end
        end
    end
    return docks
end

local function ZoneName(m, fallback) return S.MapName(m) or fallback or "?" end

-------------------------------------------------------------------------------
-- Reisen auf demselben Kontinent: Laufen gegen Fliegen und Ruhestein abwägen.
-- Flugnetz: UltimaFlightData (Flugpunkte mit Weltposition und Flugzeiten in Sekunden, aus tools/convert.lua).
-- Geflogen wird nur zwischen Flugpunkten, die der Charakter kennt (ns.cdb.taxi, beim Flugmeister gemerkt).
-- Kosten in Sekunden: Reisezeit je Strecke, der Ruhestein ist ein Sprung.
-------------------------------------------------------------------------------
local WALK_SPEED = 7          -- Yards je Sekunde zu Fuß
local WALK_DETOUR = 1.3       -- Luftlinie -> geschätzter Laufweg
local TAXI_OVERHEAD = 12      -- Sekunden: ansprechen, abheben, landen
local HEARTH_COST = 20        -- Sekunden: wirken und Ladebildschirm
-- Mindest-Ersparnis in Sekunden: Einstellung travel.minSaving (Vorgabe 90)
local MIN_SAVING_SHARE = 0.25 -- und mindestens dieser Anteil der Laufzeit
local HEARTHSTONE_ITEM = 6948
T.FLIGHT_RADIUS = 15

local function WalkTime(ci, ax, ay, bx, by)
    return (S.WorldDistance(ci, ax, ay, bx, by) or 1e9) * WALK_DETOUR / WALK_SPEED
end

function T.Flights()
    local letter = UnitFactionGroup("player") == "Alliance" and "A" or "H"
    return (UltimaFlightData or ns.flightData or {})[letter] or {}
end

-- Ruhestein bereit? Abklingzeit geschützt oder unbekannt: gilt als nicht bereit (lieber kein falscher Rat).
local function HearthReady()
    if S.ItemCount(HEARTHSTONE_ITEM) < 1 then return false end
    local getCooldown = C_Container and C_Container.GetItemCooldown or GetItemCooldown
    if not getCooldown then return false end
    local start, duration = getCooldown(HEARTHSTONE_ITEM)
    if ns.IsSecret(start) or ns.IsSecret(duration) or start == nil then return false end
    return start == 0 or duration == 0
end

-- Flugpunkt am Ruhestein-Ort: Name des Flugpunkts beginnt mit dem Ort ("Auberdine" -> "Auberdine, Darkshore").
-- Die Position des Gasthauses selbst steht nicht in den Daten; der Flugpunkt daneben ist die Näherung.
local function HearthNode(flights)
    local bind = GetBindLocation and GetBindLocation()
    if not bind or bind == "" then return nil end
    for id, node in pairs(flights) do
        if node.n:sub(1, #bind + 1) == bind .. "," then return id end
    end
    return nil
end

function T.PlanLocal(a, px, py, ci, tx, ty)
    T.flyTarget, T.flyTargetId = nil, nil
    if not ns.KnowsTaxi or not ns.db.travel.flights then return nil end
    local MIN_SAVING = ns.db.travel.minSaving
    local flights = T.Flights()
    local walk = WalkTime(ci, px, py, tx, ty)
    if walk < MIN_SAVING then return nil end -- nah genug, nichts zu planen

    -- Kürzeste Zeit zu jedem bekannten Flugpunkt: zu Fuß vom Spieler, dann über Flugverbindungen
    local dist, prev, via, open = {}, {}, {}, {}
    for id, node in pairs(flights) do
        if node.ci == ci and ns.KnowsNode(id, node) then
            dist[id] = WalkTime(ci, px, py, node.x, node.y)
            via[id] = "walk"
            open[id] = true
        end
    end
    local hearth = HearthReady() and HearthNode(flights) or nil
    if hearth and flights[hearth].ci == ci and (not dist[hearth] or HEARTH_COST < dist[hearth]) then
        dist[hearth], via[hearth], open[hearth] = HEARTH_COST, "hearth", true
    end
    while next(open) do
        local best
        for id in pairs(open) do
            if not best or dist[id] < dist[best] then best = id end
        end
        open[best] = nil
        for dest, seconds in pairs(flights[best].t) do
            local node = flights[dest]
            if node and ns.KnowsNode(dest, node) then
                local d = dist[best] + seconds + TAXI_OVERHEAD
                if not dist[dest] or d < dist[dest] then
                    dist[dest], prev[dest], via[dest], open[dest] = d, best, "fly", true
                end
            end
        end
    end

    local bestEnd, bestTime
    for id, d in pairs(dist) do
        local node = flights[id]
        if node.ci == ci then
            local total = d + WalkTime(ci, node.x, node.y, tx, ty)
            if not bestTime or total < bestTime then bestEnd, bestTime = id, total end
        end
    end
    if not bestEnd or walk - bestTime < math.max(MIN_SAVING, walk * MIN_SAVING_SHARE) then return nil end

    -- Kette zurückverfolgen: erster Flugpunkt und wie man ihn erreicht
    local first = bestEnd
    while prev[first] do first = prev[first] end
    local target = ZoneName(a.m, a.z)
    local saved = math.floor((walk - bestTime) / 60 + 0.5)
    local tail = { kind = "info", text = ns.F("Continue to your destination in %s", target), done = false, icon = "goto",
        sub = ns.F("saves about %d min", saved) }
    if via[first] == "hearth" then
        return { { kind = "ride", text = L["Use your Hearthstone"], sub = flights[first].n, done = false, icon = "home" }, tail }
    end
    if first == bestEnd then return nil end -- nur zu einem Flugpunkt laufen bringt nichts
    local from, dest = flights[first], flights[bestEnd]
    local toMaster = S.WorldDistance(ci, px, py, from.x, from.y) or 0
    T.flyTarget, T.flyTargetId = dest.n, bestEnd
    return {
        { kind = "goto", text = ns.F("To the flight master: %s", from.n),
          point = { m = a.m, x = from.x, y = from.y, w = true, ci = ci, r = T.FLIGHT_RADIUS },
          done = toMaster <= T.FLIGHT_RADIUS, icon = "fly" },
        { kind = "ride", text = ns.F("Fly to %s", dest.n), done = false, icon = "fly" },
        tail,
    }
end

-- Etappen zum Wegpunkt a, oder nil, wenn keine Reise noetig ist.
-- Etappe: { kind = "goto"|"ride"|"info", text, point = { m, x, y, w, ci, r }, done }
local PLAN_TTL = 1 -- Sekunden
T.knowledge = 0     -- zählt hoch, wenn neue Flugpunkte bekannt werden (Assist.lua)
local cache = {}

function T.Plan(a)
    if not a then return nil end
    local tx, ty, tci = S.WorldPoint(a)
    local px, py, pci = S.PlayerWorld()
    if not (tx and px and tci and pci) then return nil end
    if tci == pci then
        -- gleicher Zielpunkt innerhalb einer Sekunde: gemerkten Plan liefern (Suche über das Flugnetz sparen)
        -- Der Schlüssel enthält alles, wovon der Plan abhängt: Ziel, grobe Spielerposition (25 Yards),
        -- Stand der bekannten Flugpunkte und ob der Ruhestein bereit ist.
        local now = GetTime()
        local key = ("%.0f:%.0f:%.0f:%.0f:%d:%s:%s:%s"):format(tx, ty, px / 25, py / 25, T.knowledge,
            tostring(ns.cdb.taxi), tostring(ns.cdb.taxiIds), tostring(HearthReady()))
        if cache.key == key and now - cache.t < PLAN_TTL then
            T.flyTarget, T.flyTargetId = cache.fly, cache.flyId
            return cache.plan
        end
        local plan = T.PlanLocal(a, px, py, pci, tx, ty)
        cache.key, cache.t, cache.plan, cache.fly, cache.flyId = key, now, plan, T.flyTarget, T.flyTargetId
        return plan
    end

    local best, bestCost
    for _, d in ipairs(Prepare()) do
        if d.ci == pci and d.destCi == tci then
            local cost = (S.WorldDistance(pci, px, py, d.x, d.y) or 1e9) + RIDE_COST
            -- Ankunft: bekannter Gegenhafen, sonst die Mitte der Zielzone
            local ax, ay
            if d.arrival then
                ax, ay = d.arrival.x, d.arrival.y
            else
                ax, ay = S.WorldPoint({ m = d.t.dest, x = 50, y = 50 })
                cost = cost + NO_RETURN_PENALTY
            end
            if ax then cost = cost + (S.WorldDistance(tci, ax, ay, tx, ty) or 0) end
            if not bestCost or cost < bestCost then best, bestCost = d, cost end
        end
    end

    local target = ZoneName(a.m, a.z)
    if not best then
        return { { kind = "info", text = ns.F("Travel to %s: no ferry connection in the data", target) } }
    end
    local name = ns.L[KIND_NAME[best.t.kind] or best.t.kind]
    local destName = ZoneName(best.t.dest, best.t.destName)
    local toDock = S.WorldDistance(pci, px, py, best.x, best.y) or 0
    local legs = {
        { kind = "goto", text = ns.F("To the dock: %s to %s", name, destName),
          sub = ZoneName(best.t.m), point = { m = best.t.m, x = best.x, y = best.y, w = true, ci = best.ci, r = DOCK_RADIUS },
          done = toDock <= DOCK_RADIUS, icon = best.t.kind },
        { kind = "ride", text = ns.F("Take the %s to %s", name, destName), done = false, icon = best.t.kind },
        { kind = "info", text = ns.F("Continue to your destination in %s", target), done = false, icon = "goto" },
    }
    return legs
end

-- Ziel für den Pfeil: Hafen, solange er nicht erreicht ist; sonst nichts (auf dem Schiff warten).
function T.ArrowTarget(legs)
    if not legs then return nil end
    for _, leg in ipairs(legs) do
        if leg.kind == "goto" and not leg.done then return leg.point end
        if leg.kind == "ride" then return nil end
    end
    return nil
end
