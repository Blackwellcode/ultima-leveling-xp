-- Offline-Test des Wegnetzes (src/Engine/Paths.lua) mit nachgebauten Laufwegen in Weltkoordinaten (Yards).
-- Aufruf aus dem Projektordner: lua tools/test-paths.lua
local fails = 0
local function check(label, ok, detail)
    if not ok then fails = fails + 1 end
    io.write(("%-70s %s%s\n"):format(label, ok and "OK" or "FEHLER", detail and ("  " .. detail) or ""))
end

local ns = {}
for _, f in ipairs({ "src/Core.lua", "src/Locale/Locale.lua", "src/Locale/enUS.lua", "src/Engine/State.lua", "src/Engine/Paths.lua" }) do
    assert(loadfile(f))("UltimaLevelingXP", ns)
end
-- Wegpunkte der Testrouten liegen direkt in Weltkoordinaten
ns.State.WorldPoint = function(a) return a.x, a.y, a.ci end
local Paths = ns.Paths

local function Route(list)
    local steps = {}
    for _, p in ipairs(list) do steps[#steps + 1] = { a = { { "goto", x = p[1], y = p[2], ci = 1 } } } end
    return { s = steps }
end
-- Gerade Linie von a nach b mit Punkten alle "step" Yards
local function Line(ax, ay, bx, by, step)
    local list, len = {}, math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2)
    local n = math.floor(len / step + 0.5)
    for i = 0, n do list[#list + 1] = { ax + (bx - ax) * i / n, ay + (by - ay) * i / n } end
    return list
end
local function Join(...)
    local out = {}
    for _, part in ipairs({ ... }) do for _, p in ipairs(part) do out[#out + 1] = p end end
    return out
end
local function Build(routes)
    ns.routes = routes
    Paths.Build(true)
end
local function Length(points, px, py)
    local len, x, y = 0, px, py
    for _, p in ipairs(points) do
        len = len + math.sqrt((p.x - x) ^ 2 + (p.y - y) ^ 2)
        x, y = p.x, p.y
    end
    return len
end

-------------------------------------------------------------------------------
-- 1. Großer Umweg (wie im Bild): der einzige bekannte Laufweg macht einen Bogen -> Luftlinie
-------------------------------------------------------------------------------
Build({ Route(Join(Line(0, 0, 0, 400, 40), Line(0, 400, 300, 400, 40), Line(300, 400, 300, 0, 40))) })
local points, length = Paths.Find(1, 0, 0, 300, 0)
check("Umweg 1100 Yards bei 300 Yards Luftlinie: Luftlinie statt Bogen", points == nil, length and ("Weg " .. math.floor(length)) or nil)

-------------------------------------------------------------------------------
-- 2. Sinnvoller Bogen (Straße um ein Hindernis): Weg wird genutzt, gleichmäßige Punkte, Ziel zuletzt
-------------------------------------------------------------------------------
Build({ Route({ { 0, 0 }, { 100, 80 }, { 200, 100 }, { 300, 80 }, { 400, 0 } }) })
points, length = Paths.Find(1, 0, 0, 400, 0)
check("Bogen 445 Yards bei 400 Yards Luftlinie: Weg wird genutzt", points ~= nil, length and ("Weg " .. math.floor(length)) or nil)
local even, final = true, points and points[#points]
for i = 2, points and #points - 1 or 0 do
    local d = math.sqrt((points[i].x - points[i - 1].x) ^ 2 + (points[i].y - points[i - 1].y) ^ 2)
    if d > 36 then even = false end
end
check("Punkte gleichmäßig (höchstens 35 Yards Abstand)", points and even)
check("Letzter Punkt ist das Ziel", final and final.final and final.x == 400 and final.y == 0)
check("Weg folgt dem Bogen (Mitte nördlich der Luftlinie)", points and points[math.floor(#points / 2)].y > 40)

-------------------------------------------------------------------------------
-- 3. Einstieg nach vorn: der nächste Netzpunkt liegt hinter dem Spieler, der bessere Einstieg davor
-------------------------------------------------------------------------------
Build({ Route(Join(Line(-300, 0, 300, 0, 40), Line(300, 0, 300, 300, 40))) })
points = Paths.Find(1, -10, 25, 300, 300) -- nächster Netzpunkt (-20, 0) liegt hinter dir, (20, 0) davor
check("Weg beginnt nach vorn, nicht am nächsten Punkt hinter dir", points ~= nil and points[1].x > -10,
    points and ("erster Punkt x=" .. math.floor(points[1].x)) or "kein Weg")

-------------------------------------------------------------------------------
-- 4. Laufwege verschiedener Routen, die sich nahe kommen, sind verbunden
-------------------------------------------------------------------------------
Build({ Route(Line(0, 0, 400, 0, 40)), Route(Line(400, 25, 400, 400, 40)) })
check("Nahe Laufwege verbunden", Paths.stats.links > 0, "Verbindungen " .. Paths.stats.links)
points, length = Paths.Find(1, 0, 0, 400, 400)
check("Weg über zwei Routen hinweg gefunden", points ~= nil, length and ("Weg " .. math.floor(length)) or nil)
check("Weglänge passt zur Strecke (etwa 800 Yards)", length and length > 780 and length < 830)
check("Punkte zusammen etwa so lang wie der Weg", points and math.abs(Length(points, 0, 0) - length) < 40,
    points and ("Punkte " .. math.floor(Length(points, 0, 0))) or nil)

-------------------------------------------------------------------------------
-- 5. Kurze Strecke und gerade Wege: Luftlinie
-------------------------------------------------------------------------------
check("Unter 120 Yards: Luftlinie", Paths.Find(1, 0, 0, 100, 0) == nil)
local jitter = {}
for i = 0, 15 do jitter[#jitter + 1] = { i * 30, (i % 2 == 0) and 5 or -5 } end
Build({ Route(jitter) })
check("Zickzack-Aufzeichnung eines geraden Wegs: Luftlinie", Paths.Find(1, 0, 0, 450, 0) == nil)

-------------------------------------------------------------------------------
-- 6. Kein Netz in der Nähe, anderer Kontinent, Netz nicht fertig
-------------------------------------------------------------------------------
Build({ Route(Line(0, 0, 400, 0, 40)) })
check("Ziel weit abseits des Netzes: Luftlinie", Paths.Find(1, 0, 0, 2000, 2000) == nil)
check("Anderer Kontinent ohne Netz: Luftlinie", Paths.Find(2, 0, 0, 400, 0) == nil)

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
