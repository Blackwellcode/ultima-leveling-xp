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
-- 5b. Offenes Gelände (Redridge, Bild 2026-11-21): der einzige Netzweg macht eine Delle nach Süden
-- (1,41-mal die Luftlinie), aber andere Routen kreuzen die Luftlinie überall: dort lässt sich laufen
-- -> Luftlinie. Ohne die kreuzenden Routen ist das Gelände unbekannt -> der Weg bleibt.
-------------------------------------------------------------------------------
local dip = Route(Join(Line(0, 0, 200, -200, 40), Line(200, -200, 400, 0, 40)))
local crossings = { dip }
for x = 80, 320, 80 do crossings[#crossings + 1] = Route(Line(x, -60, x, 60, 40)) end
Build(crossings)
points, length = Paths.Find(1, 0, 0, 400, 0)
check("Delle bei begangener Luftlinie: Luftlinie", points == nil, length and ("Weg " .. math.floor(length)) or nil)
Build({ dip })
points, length = Paths.Find(1, 0, 0, 400, 0)
check("Delle ohne Laufwege an der Luftlinie: Weg bleibt", points ~= nil, length and ("Weg " .. math.floor(length)) or "Luftlinie")
-- Brücke: die Straße liegt lange auf der Luftlinie und macht dann einen nötigen Bogen. Der eigene Weg
-- zählt nicht als Beleg für begehbares Gelände -> Weg bleibt (Code-Prüfung 2026-11-21)
Build({ Route(Join(Line(0, 0, 1200, 0, 40), Line(1200, 0, 1200, 300, 40), Line(1200, 300, 1600, 300, 40),
    Line(1600, 300, 1600, 0, 40))) })
points, length = Paths.Find(1, 0, 0, 1600, 0)
check("Brücke: eigener Weg auf der Luftlinie zählt nicht als begangen", points ~= nil,
    length and ("Weg " .. math.floor(length)) or "Luftlinie")
-- Dieselbe Straße von einer zweiten Route 15 Yards versetzt aufgezeichnet: zählt auch nicht
local function Bridge(o)
    return Route(Join(Line(0, o, 1200, o, 40), Line(1200, o, 1200, 300 + o, 40), Line(1200, 300 + o, 1600, 300 + o, 40),
        Line(1600, 300 + o, 1600, o, 40)))
end
Build({ Bridge(0), Bridge(15) })
points, length = Paths.Find(1, 0, 0, 1600, 0)
check("Brücke: zweite Aufzeichnung 15 Yards daneben zählt nicht als begangen", points ~= nil,
    length and ("Weg " .. math.floor(length)) or "Luftlinie")
-- Zuschlag: Weg knapp über 1,5 x Luftlinie + 40 Yards -> Luftlinie (vorher bis + 120 erlaubt)
Build({ Route(Join(Line(0, 0, 200, 275, 40), Line(200, 275, 400, 0, 40))) })
points, length = Paths.Find(1, 0, 0, 400, 0)
check("Umweg über 1,5 x Luftlinie + 40 Yards: Luftlinie", points == nil, length and ("Weg " .. math.floor(length)) or nil)

-------------------------------------------------------------------------------
-- 5c. Laufspuren: wo du selbst gelaufen bist, kennt das Netz den Weg (gespeichert in ns.db.trail)
-------------------------------------------------------------------------------
ns.db = { trail = {} }
local bridge = { Route(Join(Line(0, 0, 1200, 0, 40), Line(1200, 0, 1200, 300, 40), Line(1200, 300, 1600, 300, 40),
    Line(1600, 300, 1600, 0, 40))) }
Build(bridge)
-- du läufst geradeaus von (1200, 0) nach (1600, 0), Position etwa jede Sekunde (7 Yards/s)
for x = 1200, 1600, 7 do Paths.Record(1, x, 0) end
Paths.Record(1, 1600, 0)
points, length = Paths.Find(1, 0, 0, 1600, 0)
check("Laufspur: selbst gelaufene Abkürzung ersetzt den Bogen", points == nil or (length and length < 1700),
    length and ("Weg " .. math.floor(length)) or "Luftlinie")
local saved = Paths.TrailCount(1)
check("Laufspur: Stücke gespeichert", saved > 10, saved .. " Stücke")
Build(bridge)
points, length = Paths.Find(1, 0, 0, 1600, 0)
check("Laufspur: nach Neuaufbau (Neuladen) weiter bekannt", points == nil or (length and length < 1700),
    length and ("Weg " .. math.floor(length)) or "Luftlinie")
-- Teleport/Ladebildschirm (Sprung über 80 Yards) und Fallen, Schwimmen, Flug verbinden nichts
ns.db = { trail = {} }
Build({})
Paths.Record(2, 0, 0); Paths.Record(2, 20, 0); Paths.Record(2, 500, 0); Paths.Record(2, 520, 0)
check("Laufspur: Sprung über 80 Yards wird nicht verbunden", Paths.TrailCount(2) == 2, Paths.TrailCount(2) .. " Stücke")
Paths.Record(2, 540, 0, true); Paths.Record(2, 560, 0); Paths.Record(2, 580, 0, true); Paths.Record(2, 600, 0)
check("Laufspur: Fallen/Schwimmen/Flug unterbricht die Spur", Paths.TrailCount(2) == 2, Paths.TrailCount(2) .. " Stücke")
Paths.Record(2, 605, 0)
check("Laufspur: unter 15 Yards Bewegung kein neues Stück", Paths.TrailCount(2) == 2, Paths.TrailCount(2) .. " Stücke")
-- Zwei getrennt gelaufene Spuren 25 Yards nebeneinander (zwei Ufer, oben/unten an einer Klippe): nur die
-- gelaufenen Stücke verbinden, keine Nahverbindung zwischen Spuren (Code-Prüfung 2026-11-21)
ns.db = { trail = {} }
Build({})
Paths.Record(3, nil, nil)
for x = 0, 600, 20 do Paths.Record(3, x, 0) end
Paths.Record(3, nil, nil)
for x = 600, 0, -20 do Paths.Record(3, x, 25) end
check("Laufspur: Spuren nebeneinander werden nicht verbunden", Paths.stats.links == 0, Paths.stats.links .. " Nahverbindungen")
-- Eine Spur neben einem Routenpunkt wird angebunden (sonst nützt sie der Suche nichts)
Build({ { s = { { a = { { "goto", x = 300, y = 10, ci = 3 } } } } } })
check("Laufspur: Spur neben einer Route wird angebunden", Paths.stats.links > 0, Paths.stats.links .. " Nahverbindungen")
-- Fluss: Ufer A (y=0) und Ufer B (y=25) getrennt gelaufen, ein Routenpunkt dicht am Ufer A darf die Ufer
-- nicht verbinden (Code-Prüfung 2026-11-21)
ns.db = { trail = {} }
Build({ { s = { { a = { { "goto", x = 700, y = 4, ci = 4 } } } } } })
Paths.Record(4, nil, nil)
for x = 1200, 0, -20 do Paths.Record(4, x, 0) end
Paths.Record(4, nil, nil)
for x = 600, 1200, 20 do Paths.Record(4, x, 25) end
for y = 25, 600, 20 do Paths.Record(4, 1200, y) end
points = Paths.Find(4, 0, 0, 1200, 600)
-- Ufer B erreicht man von A aus nur über den Fluss: jeder gefundene Weg kreuzt ihn
check("Laufspur: Routenpunkt am Ufer verbindet die Ufer nicht", points == nil,
    points and ("Weg mit " .. #points .. " Punkten über den Fluss") or "kein Weg")
-- Spuren löschen (/ultima spuren reset)
Paths.ClearTrail()
local emptied = next(ns.db.trail) == nil
check("Laufspur: Löschen entfernt alle Spuren", emptied and Paths.TrailCount(3) == 0, Paths.TrailCount(3) .. " Stücke")
ns.db = nil
Paths.Record(2, 700, 0)
check("Laufspur: ohne gespeicherte Daten kein Fehler", true)

-------------------------------------------------------------------------------
-- 6. Kein Netz in der Nähe, anderer Kontinent, Netz nicht fertig
-------------------------------------------------------------------------------
Build({ Route(Line(0, 0, 400, 0, 40)) })
check("Ziel weit abseits des Netzes: Luftlinie", Paths.Find(1, 0, 0, 2000, 2000) == nil)
check("Anderer Kontinent ohne Netz: Luftlinie", Paths.Find(2, 0, 0, 400, 0) == nil)

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
