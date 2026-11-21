-- Wegnetz: aus den Laufwegen aller Routen (aufeinanderfolgende Wegpunkte) entsteht ein Graph je Kontinent.
-- Die Wege führen über Straßen, Pässe und Brücken. Laufwege verschiedener Routen, die sich nahe kommen,
-- werden verbunden, damit das Netz keine Umwege über eine einzelne bekannte Strecke erzwingt.
-- Die Suche (A*) startet an mehreren Netzpunkten rund um den Spieler und endet an mehreren rund um das
-- Ziel; so beginnt der Weg dort, wo es von deiner Position aus am kürzesten ist, nicht am nächsten
-- Punkt hinter dir. Ist der Weg kaum besser als die Luftlinie oder ein großer Umweg, gilt die Luftlinie.
-- Aufbau läuft in Häppchen (höchstens wenige Millisekunden je Frame), Suche bei Bedarf.
local _, ns = ...
local Paths = {}
ns.Paths = Paths
local S = ns.State

local CELL = 8          -- Yards: Punkte in derselben Zelle verschmelzen zu einem Knoten
local MAX_EDGE = 320    -- Yards: weitere Sprünge sind Reisen (Flug, Ruhestein), keine Wege
local LINK = 30         -- Yards: so nahe Knoten verschiedener Laufwege werden verbunden
local TRAIL_LINK = 12   -- Yards: Laufspur und Route nur so dicht verbinden (sonst über einen Fluss oder eine Klippe)
local SNAP = 260        -- Yards: so weit dürfen Start und Ziel vom Netz entfernt sein
local CANDIDATES = 10   -- so viele Netzpunkte je Seite kommen als Einstieg und Ausstieg in Frage
local BUCKET = 100      -- Yards: Raster für die Suche nach nahen Knoten
local DETOUR = 1.5      -- Weg höchstens 1,5-mal so lang wie die Luftlinie (+ 40 Yards), sonst Luftlinie
local DETOUR_ADD = 40
local COVER = 45        -- Yards: ein Punkt der Luftlinie gilt als begangen, wenn ein Netzpunkt so nahe liegt
local COVER_SHARE = 0.7 -- so viel der Luftlinie begangen: dort lässt sich laufen ...
local OPEN_DETOUR = 1.25 -- ... dann gilt die Luftlinie schon, wenn der Weg 25 % länger ist (Stadtwege um Häuser: ~1,2)
local DIRECT = 120      -- Yards: bis zu dieser Luftlinie wird direkt gelaufen
local SIMPLIFY = 12     -- Yards: Zacken der aufgezeichneten Wege bis zu dieser Abweichung glätten
local SPACING = 35      -- Yards: Abstand der Wegpunkte (Punkte auf der Karte)
local GREED = 1.3       -- Gewicht der Restentfernung: Suche läuft zielstrebig, Weg höchstens wenig länger
local MAX_VISITS = 4000 -- Obergrenze je Suche, damit eine Neuberechnung nie ruckelt (sonst Luftlinie)
local TELEPORT = { fly = true, hs = true, zone = true, home = true }

local graph = {}        -- [Kontinent] = { cell = {}, buckets = {}, near = {}, count = 0 }
local ready, building = false, nil
Paths.stats = { nodes = 0, edges = 0, links = 0 }

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

local function Graph(ci)
    local g = graph[ci]
    if not g then
        g = { cell = {}, buckets = {}, near = {}, count = 0 }
        graph[ci] = g
    end
    return g
end

local function Link(a, b)
    if a == b or a.adj[b] then return false end
    a.adj[b] = true
    b.adj[a] = true
    Paths.stats.edges = Paths.stats.edges + 1
    return true
end

local function AddTo(index, key, node)
    local list = index[key]
    if not list then list = {}; index[key] = list end
    list[#list + 1] = node
end

-- Nahe Knoten anderer Laufwege verbinden (feines Raster, nur die 3x3 Nachbarzellen). Zwei Knoten aus
-- Laufspuren verbindet nur das gelaufene Stück selbst, nie die Nähe: zwei Ufer oder oben/unten an einer
-- Klippe liegen nah beieinander, ohne dass man hinüber kommt.
local function LinkNear(g, node)
    local nx, ny = math.floor(node.x / LINK), math.floor(node.y / LINK)
    for i = nx - 1, nx + 1 do
        for j = ny - 1, ny + 1 do
            for _, other in ipairs(g.near[i .. ":" .. j] or {}) do
                local reach = (node.trail or other.trail) and TRAIL_LINK or LINK
                if not (node.trail and other.trail) and Dist(node.x, node.y, other.x, other.y) <= reach
                    and Link(node, other) then
                    Paths.stats.links = Paths.stats.links + 1
                end
            end
        end
    end
end

-- Knoten der Rasterzelle; trail = aus einer Laufspur. Landet ein Routenpunkt in der Zelle einer Laufspur,
-- wird der Knoten ein Routenknoten und bekommt jetzt seine Nahverbindungen.
local function NodeAt(g, x, y, trail)
    local key = math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
    local node = g.cell[key]
    if node then
        if node.trail and not trail then
            node.trail = nil
            LinkNear(g, node)
        end
        return node
    end
    node = { x = x, y = y, adj = {}, trail = trail or nil }
    g.cell[key] = node
    g.count = g.count + 1
    Paths.stats.nodes = Paths.stats.nodes + 1
    AddTo(g.buckets, math.floor(x / BUCKET) .. ":" .. math.floor(y / BUCKET), node)
    LinkNear(g, node)
    AddTo(g.near, math.floor(x / LINK) .. ":" .. math.floor(y / LINK), node)
    return node
end

-------------------------------------------------------------------------------
-- Laufspuren: wo du selbst gelaufen bist (kontoweit gespeichert, ns.db.trail[Kontinent][Stück] = true).
-- Ein Stück verbindet zwei Rasterzellen (CELL); Schlüssel "x1:y1:x2:y2" in Zellen, kleinere Zelle zuerst.
-- So kennt das Netz auch Gelände, durch das keine Route führt, sobald du es einmal betreten hast.
-------------------------------------------------------------------------------
local TRAIL_STEP = 15     -- Yards: neues Stück erst nach so viel Bewegung
local TRAIL_BREAK = 80    -- Yards: weiter in einem Schritt = Teleport, Ladebildschirm, Flug: nicht verbinden
local TRAIL_MAX = 10000   -- Stücke je Kontinent (etwa 0,3 MB gespeicherte Daten, rund 150 km Laufweg)
local lastTrail           -- { ci, x, y } letzte aufgezeichnete Position
local trailCount = {}     -- [Kontinent] = Anzahl Stücke (aus den gespeicherten Daten gezählt)
local trailPending = {}   -- während eines laufenden Aufbaus aufgezeichnet: { ci, key }, danach verknüpft

local function TrailStore(ci)
    local db = ns.db
    if not db then return nil end
    db.trail = db.trail or {}
    local t = db.trail[ci]
    if not t then t = {}; db.trail[ci] = t end
    if not trailCount[ci] or trailCount[ci].t ~= t then
        local n = 0
        for _ in pairs(t) do n = n + 1 end
        trailCount[ci] = { t = t, n = n }
    end
    return t
end

local function TrailKey(ax, ay, bx, by)
    local a1, a2 = math.floor(ax / CELL), math.floor(ay / CELL)
    local b1, b2 = math.floor(bx / CELL), math.floor(by / CELL)
    if a1 == b1 and a2 == b2 then return nil end
    if b1 < a1 or (b1 == a1 and b2 < a2) then a1, a2, b1, b2 = b1, b2, a1, a2 end
    return a1 .. ":" .. a2 .. ":" .. b1 .. ":" .. b2
end

-- Stück aus einem Schlüssel ins Netz: Knoten in den Zellmitten
local function TrailLink(ci, key)
    local a1, a2, b1, b2 = key:match("^(-?%d+):(-?%d+):(-?%d+):(-?%d+)$")
    if not a1 then return end
    local g = Graph(ci)
    local half = CELL / 2
    local a = NodeAt(g, tonumber(a1) * CELL + half, tonumber(a2) * CELL + half, true)
    local b = NodeAt(g, tonumber(b1) * CELL + half, tonumber(b2) * CELL + half, true)
    Link(a, b)
end

-- Deine Position (Weltkoordinaten). blocked: Flug, Fallen, Schwimmen o. ä. - das unterbricht die Spur
-- (ein Sprung eine Klippe hinab ist kein Weg zurück nach oben).
function Paths.Record(ci, x, y, blocked)
    if not (ci and x and y) or blocked then
        lastTrail = nil
        return
    end
    local last = lastTrail
    if last and last.ci == ci then
        local d = Dist(last.x, last.y, x, y)
        if d < TRAIL_STEP then return end
        if d <= TRAIL_BREAK then
            local t = TrailStore(ci)
            local key = t and TrailKey(last.x, last.y, x, y)
            if key and not t[key] and trailCount[ci].n < TRAIL_MAX then
                t[key] = true
                trailCount[ci].n = trailCount[ci].n + 1
                -- ins fertige Netz sofort; während eines Aufbaus vormerken (er liest die Tabelle als Schnappschuss)
                if ready then TrailLink(ci, key) else trailPending[#trailPending + 1] = { ci, key } end
            end
        end
    end
    lastTrail = { ci = ci, x = x, y = y }
end

function Paths.TrailCount(ci)
    if not TrailStore(ci) then return 0 end
    return trailCount[ci].n
end

-- Alle Laufspuren löschen (/ultima spuren reset) und das Netz ohne sie neu aufbauen.
function Paths.ClearTrail()
    if ns.db then ns.db.trail = {} end
    trailCount, trailPending, lastTrail = {}, {}, nil
    Paths.Build()
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
    -- eigene Laufspuren: erst Schnappschuss der Schlüssel (neue Einträge während einer Pause würden ein
    -- laufendes pairs() durcheinanderbringen), danach die währenddessen aufgezeichneten
    local snapshot = {}
    for ci, t in pairs(ns.db and ns.db.trail or {}) do
        if type(t) == "table" then
            for key in pairs(t) do snapshot[#snapshot + 1] = { ci, key } end
        end
    end
    for _, e in ipairs(snapshot) do
        TrailLink(e[1], e[2])
        n = n + 1
        if batch and n % batch == 0 then coroutine.yield() end
    end
    ready = true
    local pending = trailPending
    trailPending = {}
    for _, e in ipairs(pending) do TrailLink(e[1], e[2]) end
end

-- Aufbau über OnUpdate mit Zeitbudget (4 ms je Bild). Der Handler hängt nur, solange gebaut wird.
local driver = CreateFrame and CreateFrame("Frame") or nil
local function Drive(self)
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
    if not building then self:SetScript("OnUpdate", nil) end
end

-- Startet den Aufbau. sync: sofort (Tests); sonst läuft er über OnUpdate mit Zeitbudget.
function Paths.Build(sync)
    graph, ready = {}, false
    Paths.stats = { nodes = 0, edges = 0, links = 0 }
    if sync then BuildAll(nil) return end
    building = coroutine.create(function() BuildAll(300) end)
    if driver then driver:SetScript("OnUpdate", Drive) end
end

function Paths.IsReady() return ready end

-- Die nächsten Knoten im Umkreis SNAP, nach Entfernung sortiert, höchstens CANDIDATES
local function Nearby(g, x, y)
    local list = {}
    local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
    local r = math.ceil(SNAP / BUCKET)
    for i = bx - r, bx + r do
        for j = by - r, by + r do
            for _, node in ipairs(g.buckets[i .. ":" .. j] or {}) do
                local d = Dist(node.x, node.y, x, y)
                if d <= SNAP then list[#list + 1] = { node, d } end
            end
        end
    end
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = #list, CANDIDATES + 1, -1 do list[i] = nil end
    return list
end

-- Anteil der Luftlinie, an dem Laufwege irgendeiner Route vorbeiführen (Netzpunkt höchstens COVER entfernt).
-- Hoch: das Gelände dazwischen ist begehbar, ein Bogen des Netzes ist dann kein nötiger Umweg.
-- skip(node) = true: Knoten zählt nicht. Find übergibt den Korridor des gefundenen Wegs: der Weg selbst und
-- andere Aufzeichnungen derselben Straße belegen nicht, dass sich die Luftlinie laufen lässt (eine Straße
-- auf der Luftlinie mit nötigem Bogen über eine Brücke).
-- need: Schwelle (Anteil). Mit need bricht die Zählung ab, sobald das Ergebnis feststeht; dann ist der
-- Rückgabewert nur als "erreicht / nicht erreicht" gegen need verlässlich.
local function Covered(g, px, py, tx, ty, skip, need)
    local len = Dist(px, py, tx, ty)
    local n = math.max(2, math.floor(len / 25))
    local hit = 0
    local target = need and need * (n + 1)
    for i = 0, n do
        if target then
            if hit >= target then return hit / (n + 1) end
            if hit + (n - i + 1) < target then return hit / (n + 1) end
        end
        local x, y = px + (tx - px) * i / n, py + (ty - py) * i / n
        local bx, by = math.floor(x / BUCKET), math.floor(y / BUCKET)
        local found = false
        for bi = bx - 1, bx + 1 do
            for bj = by - 1, by + 1 do
                for _, node in ipairs(g.buckets[bi .. ":" .. bj] or {}) do
                    if Dist(node.x, node.y, x, y) <= COVER and not (skip and skip(node)) then found = true break end
                end
                if found then break end
            end
            if found then break end
        end
        if found then hit = hit + 1 end
    end
    return hit / (n + 1)
end
Paths.Covered = function(ci, px, py, tx, ty) return graph[ci] and Covered(graph[ci], px, py, tx, ty) or 0 end

-- Binärer Heap für A*
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

-- Abstand eines Punkts zur Strecke a-b
local function SegmentDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 == 0 then return Dist(px, py, ax, ay) end
    local t = math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
    return Dist(px, py, ax + t * dx, ay + t * dy)
end
Paths.SegmentDist = SegmentDist

-- Douglas-Peucker: Punkte weglassen, die weniger als eps von der Verbindung ihrer Nachbarn abweichen
local function Simplify(list, eps)
    if #list < 3 then return list end
    local keep = { [1] = true, [#list] = true }
    local stack = { { 1, #list } }
    while #stack > 0 do
        local seg = table.remove(stack)
        local a, b = seg[1], seg[2]
        local worst, worstD = nil, eps
        for i = a + 1, b - 1 do
            local d = SegmentDist(list[i].x, list[i].y, list[a].x, list[a].y, list[b].x, list[b].y)
            if d > worstD then worst, worstD = i, d end
        end
        if worst then
            keep[worst] = true
            stack[#stack + 1] = { a, worst }
            stack[#stack + 1] = { worst, b }
        end
    end
    local out = {}
    for i, p in ipairs(list) do if keep[i] then out[#out + 1] = p end end
    return out
end

-- Gleichmäßige Wegpunkte im Abstand "step" entlang des Linienzugs (ohne den Startpunkt)
local function Resample(list, step)
    local out = {}
    local carry = 0
    for i = 2, #list do
        local a, b = list[i - 1], list[i]
        local len = Dist(a.x, a.y, b.x, b.y)
        local pos = step - carry
        while pos < len do
            local t = pos / len
            out[#out + 1] = { x = a.x + t * (b.x - a.x), y = a.y + t * (b.y - a.y) }
            pos = pos + step
        end
        carry = len - (pos - step)
    end
    return out
end

-- Weg von (px, py) nach (tx, ty) auf Kontinent ci als Liste von Punkten { x, y, ci, w = true }, dazu
-- seine Länge. nil, wenn das Netz noch nicht fertig ist, kein Weg existiert oder die Luftlinie besser ist.
function Paths.Find(ci, px, py, tx, ty)
    if not ready then return nil end
    local g = graph[ci]
    if not g then return nil end
    local direct = Dist(px, py, tx, ty)
    if direct <= DIRECT then return nil end
    local starts, goals = Nearby(g, px, py), Nearby(g, tx, ty)
    if #starts == 0 or #goals == 0 then return nil end

    -- Ausstieg: Restweg vom Netzpunkt bis zum Ziel
    local exit = {}
    for _, c in ipairs(goals) do exit[c[1]] = c[2] end
    local GOAL = { x = tx, y = ty }

    local open, gScore, came, closed = {}, {}, {}, {}
    for _, c in ipairs(starts) do
        local node, d = c[1], c[2]
        if not gScore[node] or d < gScore[node] then
            gScore[node] = d
            Push(open, node, d + GREED * Dist(node.x, node.y, tx, ty))
        end
    end
    local visits = 0
    while #open > 0 and visits < MAX_VISITS do
        local current = Pop(open)
        if current == GOAL then break end
        if not closed[current] then
            closed[current] = true
            visits = visits + 1
            local base = gScore[current]
            if exit[current] then
                local total = base + exit[current]
                if not gScore[GOAL] or total < gScore[GOAL] then
                    gScore[GOAL] = total
                    came[GOAL] = current
                    Push(open, GOAL, total)
                end
            end
            for nb in pairs(current.adj) do
                local tentative = base + Dist(current.x, current.y, nb.x, nb.y)
                if not gScore[nb] or tentative < gScore[nb] then
                    gScore[nb] = tentative
                    came[nb] = current
                    Push(open, nb, tentative + GREED * Dist(nb.x, nb.y, tx, ty))
                end
            end
        end
    end
    local length = gScore[GOAL]
    if not length or length > DETOUR * direct + DETOUR_ADD then return nil end
    -- Begangenes Gelände: ein Bogen des Netzes ist dort kein nötiger Umweg
    if length > OPEN_DETOUR * direct then
        -- Korridor: Knoten höchstens COVER neben dem gefundenen Weg (Spieler, Netzpunkte, Ziel)
        local poly, n = { { x = tx, y = ty } }, came[GOAL]
        while n do
            poly[#poly + 1] = n
            n = came[n]
        end
        poly[#poly + 1] = { x = px, y = py }
        local memo = {}
        local function InCorridor(node)
            local v = memo[node]
            if v == nil then
                v = false
                for i = 2, #poly do
                    local a, b = poly[i - 1], poly[i]
                    if SegmentDist(node.x, node.y, a.x, a.y, b.x, b.y) <= COVER then v = true break end
                end
                memo[node] = v
            end
            return v
        end
        if Covered(g, px, py, tx, ty, InCorridor, COVER_SHARE) >= COVER_SHARE then return nil end
    end

    -- Linienzug: Spieler, Netzpunkte, Ziel; geglättet und gleichmäßig verteilt
    local line, node = { { x = tx, y = ty } }, came[GOAL]
    while node do
        table.insert(line, 1, { x = node.x, y = node.y })
        node = came[node]
    end
    table.insert(line, 1, { x = px, y = py })
    line = Simplify(line, SIMPLIFY)
    -- Weg ist nach dem Glätten praktisch gerade: Luftlinie
    if #line <= 2 then return nil end

    local points = {}
    for _, p in ipairs(Resample(line, SPACING)) do
        if Dist(p.x, p.y, tx, ty) >= SPACING * 0.5 then
            points[#points + 1] = { x = p.x, y = p.y, ci = ci, w = true, r = 18 }
        end
    end
    points[#points + 1] = { x = tx, y = ty, ci = ci, w = true, r = 12, final = true }
    return points, length
end
