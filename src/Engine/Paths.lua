-- Wegnetz: aus den Laufwegen aller Routen (aufeinanderfolgende Wegpunkte) entsteht ein Graph je Kontinent.
-- Die Routen-Autoren sind diese Wege selbst gelaufen; sie fuehren über Strassen, Paesse und Bruecken.
-- Eine A*-Suche liefert Zwischenpunkte statt Luftlinie, damit der Pfeil nicht in Sackgassen führt.
-- Aufbau läuft in Haeppchen (hoechstens wenige Millisekunden je Frame), Suche bei Bedarf.
local _, ns = ...
local Paths = {}
ns.Paths = Paths
local S = ns.State

local CELL = 8          -- Yards: Punkte in derselben Zelle verschmelzen zu einem Knoten
local MAX_EDGE = 320    -- Yards: weitere Spruenge sind Reisen (Flug, Ruhestein), keine Wege
local SNAP = 260        -- Yards: so weit duerfen Start und Ziel vom Netz entfernt sein
local BUCKET = 100      -- Yards: Raster für die Suche nach dem naechsten Knoten
local DETOUR = 3.0      -- Umweg hoechstens 3-mal Luftlinie (+ 300 Yards), sonst Luftlinie
local TELEPORT = { fly = true, hs = true, zone = true, home = true }

local graph = {}        -- [Kontinent] = { cell = {}, buckets = {}, count = 0 }
local ready, building = false, nil
Paths.stats = { nodes = 0, edges = 0 }

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function Graph(ci)
    local g = graph[ci]
    if not g then
        g = { cell = {}, buckets = {}, count = 0 }
        graph[ci] = g
    end
    return g
end

local function NodeAt(g, x, y)
    local key = math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
    local node = g.cell[key]
    if node then return node end
    node = { x = x, y = y, adj = {} }
    g.cell[key] = node
    g.count = g.count + 1
    Paths.stats.nodes = Paths.stats.nodes + 1
    local bkey = math.floor(x / BUCKET) .. ":" .. math.floor(y / BUCKET)
    local bucket = g.buckets[bkey]
    if not bucket then bucket = {}; g.buckets[bkey] = bucket end
    bucket[#bucket + 1] = node
    return node
end

local function Link(a, b)
    if a == b or a.adj[b] then return end
    a.adj[b] = true
    b.adj[a] = true
    Paths.stats.edges = Paths.stats.edges + 1
end

-- Liest alle Routen; yield nach jeweils "batch" Wegpunkten.
local function BuildAll(batch)
    local n = 0
    for _, route in ipairs(ns.routes or {}) do
        local prev, prevCi
        for _, step in ipairs(route.s) do
            for _, a in ipairs(step.a) do
                if TELEPORT[a[1]] then
                    prev = nil
                elseif a[1] == "goto" then
                    local x, y, ci = S.WorldPoint(a)
                    if x and ci then
                        local node = NodeAt(Graph(ci), x, y)
                        if prev and prevCi == ci and Dist(prev.x, prev.y, x, y) <= MAX_EDGE then Link(prev, node) end
                        prev, prevCi = node, ci
                    end
                    n = n + 1
                    if batch and n % batch == 0 then coroutine.yield() end
                end
            end
        end
    end
    ready = true
end

-- Startet den Aufbau. step(): für Tests ohne Frames; sonst läuft er über OnUpdate mit Zeitbudget.
function Paths.Build(sync)
    graph, ready = {}, false
    Paths.stats = { nodes = 0, edges = 0 }
    if sync then BuildAll(nil) return end
    building = coroutine.create(function() BuildAll(300) end)
end

function Paths.IsReady() return ready end

if CreateFrame then
    local driver = CreateFrame("Frame")
    driver:SetScript("OnUpdate", function()
        if not building then return end
        local start = debugprofilestop()
        while building and debugprofilestop() - start < 4 do
            local ok, err = coroutine.resume(building)
            if not ok then
                print(ns.WARN .. ns.F("Path network build failed: %s", tostring(err)))
                building = nil
            elseif coroutine.status(building) == "dead" then
                building = nil
            end
        end
    end)
end

local function Nearest(g, x, y)
    local best, bestD
    local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
    local r = math.ceil(SNAP / BUCKET)
    for i = bx - r, bx + r do
        for j = by - r, by + r do
            local bucket = g.buckets[i .. ":" .. j]
            if bucket then
                for _, node in ipairs(bucket) do
                    local d = Dist(node.x, node.y, x, y)
                    if d <= SNAP and (not bestD or d < bestD) then best, bestD = node, d end
                end
            end
        end
    end
    return best
end

-- Binaerer Heap für A*
local function Push(heap, node, f)
    heap[#heap + 1] = { node, f }
    local i = #heap
    while i > 1 do
        local p = math.floor(i / 2)
        if heap[p][2] <= heap[i][2] then break end
        heap[p], heap[i] = heap[i], heap[p]
        i = p
    end
end
local function Pop(heap)
    local top = heap[1]
    local last = table.remove(heap)
    if #heap > 0 then
        heap[1] = last
        local i = 1
        while true do
            local l, r, m = i * 2, i * 2 + 1, i
            if heap[l] and heap[l][2] < heap[m][2] then m = l end
            if heap[r] and heap[r][2] < heap[m][2] then m = r end
            if m == i then break end
            heap[m], heap[i] = heap[i], heap[m]
            i = m
        end
    end
    return top[1]
end

-- Weg von (px, py) nach (tx, ty) auf Kontinent ci als Liste von Punkten { x, y, ci, w = true }.
-- nil, wenn das Netz noch nicht fertig ist, kein Weg existiert oder der Umweg zu gross waere.
function Paths.Find(ci, px, py, tx, ty)
    if not ready then return nil end
    local g = graph[ci]
    if not g then return nil end
    local start, goal = Nearest(g, px, py), Nearest(g, tx, ty)
    if not start or not goal or start == goal then return nil end

    local open, gScore, came, closed = {}, { [start] = 0 }, {}, {}
    Push(open, start, Dist(start.x, start.y, goal.x, goal.y))
    local visits = 0
    while #open > 0 and visits < 80000 do
        local current = Pop(open)
        if current == goal then break end
        if not closed[current] then
            closed[current] = true
            visits = visits + 1
            for nb in pairs(current.adj) do
                local tentative = gScore[current] + Dist(current.x, current.y, nb.x, nb.y)
                if not gScore[nb] or tentative < gScore[nb] then
                    gScore[nb] = tentative
                    came[nb] = current
                    Push(open, nb, tentative + Dist(nb.x, nb.y, goal.x, goal.y))
                end
            end
        end
    end
    if not came[goal] then return nil end

    local direct = Dist(px, py, tx, ty)
    if gScore[goal] > DETOUR * direct + 300 then return nil end

    local nodes, node = {}, goal
    while node do
        table.insert(nodes, 1, node)
        node = came[node]
    end
    -- Ausduennen: Punkte naeher als 30 Yards zum vorigen entfallen, das Ziel kommt zuletzt dazu
    local points, last = {}, nil
    for _, n in ipairs(nodes) do
        if not last or Dist(last.x, last.y, n.x, n.y) >= 30 then
            points[#points + 1] = { x = n.x, y = n.y, ci = ci, w = true, r = 18 }
            last = n
        end
    end
    points[#points + 1] = { x = tx, y = ty, ci = ci, w = true, r = 12, final = true }
    return points, gScore[goal]
end
