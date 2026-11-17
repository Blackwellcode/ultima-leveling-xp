-- Offline-Test der Ultima-Engine gegen die echte Datenbank: ein simulierter Charakter spielt Routen durch.
-- Aufruf aus dem Projektordner: lua tools/test-engine.lua
local ns = {}
local function load(path) assert(loadfile(path))("UltimaLevelingXP", ns) end
for _, f in ipairs({ "src/Core.lua", "src/Locale/Locale.lua", "src/Locale/enUS.lua", "src/Locale/deDE.lua",
    "src/Engine/Conditions.lua", "src/Engine/State.lua", "src/Engine/Progress.lua",
    "src/Engine/Text.lua", "src/Engine/Runner.lua" }) do
    load(f)
end
for _, f in ipairs({ "data/Routes_A.lua", "data/Routes_B.lua" }) do assert(loadfile(f))() end
ns.routes = UltimaRouteData
-- Oberflächen-Sprache Deutsch: die Text-Prüfungen unten erwarten deutsche Texte
ns.InitDB({ lang = "deDE", langChosen = true }, {})
local S, R, P = ns.State, ns.Runner, ns.Progress

-------------------------------------------------------------------------------
-- Simulierte Spielwelt
-------------------------------------------------------------------------------
local W = {}
local function ResetWorld(level)
    if ns.cdb then ns.cdb.pointer, ns.cdb.manual, ns.cdb.marks, ns.cdb.open, ns.cdb.unavail = {}, {}, {}, {}, {} end
    W = { level = level, xp = 0, onLog = {}, turned = {}, obj = {}, all = {}, items = {}, known = {},
        zone = "Westfall", subzone = "", pos = nil, map = 1436, bound = nil }
end
ResetWorld(13)
local player = { race = "Human", class = "PALADIN", faction = "Alliance", game = "FOREVER", sex = 2, locale = "enUS" }
S.Player = function() player.level = W.level; return player end
S.Level = function() return W.level end
S.XP = function() return W.xp, 1000 end
S.OnQuest = function(q) return W.onLog[q] == true end
S.TurnedIn = function(q) return W.turned[q] == true end
S.QuestComplete = function(q) return W.all[q] == true end
S.Objective = function(q, o) if not W.onLog[q] then return nil end return W.obj[q .. ":" .. o] == true, nil end
S.QuestTitle = function(q) return "Quest " .. q end
S.ItemCount = function(i) return W.items[i] or 0 end
S.ItemName = function(i) return "Item " .. i end
S.KnowsSpell = function(sp) return W.known[sp] == true end
S.SkillLevel = function() return nil end
S.SpellName = function(sp) return "Spell " .. sp end
S.ZoneText = function() return W.zone end
S.SubzoneText = function() return W.subzone end
S.AreaName = function(area) return "Area " .. area end
S.MapName = function(m) return "Map " .. tostring(m) end
-- Quests mit Zielen: alle, für die irgendeine Route ein complete/collect enthaelt (Liefer-Quests haben keine)
local HAS_OBJECTIVES = {}
for _, r in ipairs(ns.routes) do
    for _, s in ipairs(r.s) do
        for _, a in ipairs(s.a) do
            if (a[1] == "complete" or a[1] == "collect") and a.q then HAS_OBJECTIVES[a.q] = true end
        end
    end
end
S.HasOpenObjectives = function(q) return HAS_OBJECTIVES[q] == true and W.all[q] ~= true end
S.InMap = function(m) return m ~= nil and W.map == m end
S.BoundTo = function(area) return area ~= nil and W.bound == area end
S.Distance = function(a)
    if not W.pos then return 999 end
    if W.pos == a then return 0 end
    return 999
end

-- Fuehrt eine offene Handlung im simulierten Spiel aus.
local performed = {}
local function Perform(view, si, entry)
    local a = entry.a
    local tag = a[1]
    performed[tag] = (performed[tag] or 0) + 1
    if tag == "accept" then W.onLog[a.q] = true
    elseif tag == "complete" then
        if a.o then W.obj[a.q .. ":" .. a.o] = true else W.all[a.q] = true end
        W.all[a.q] = true
    elseif tag == "turnin" then W.onLog[a.q] = nil; W.turned[a.q] = true; W.xp = W.xp + 400
        if W.xp >= 1000 then W.xp = W.xp - 1000; W.level = W.level + 1 end
    elseif tag == "collect" then W.items[a.i] = a.n or 1
    elseif tag == "xp" then
        if a.away then W.level = a.lvl - 1; W.xp = 1000 - a.away
        else W.level = math.max(W.level, a.lvl); if a.pct then W.xp = math.ceil(a.pct * 1000) end end
    elseif tag == "train" then W.known[a.sp] = true
    elseif tag == "abandon" then W.onLog[a.q] = nil
    elseif tag == "zone" then W.zone = a.to; W.map = a.zm
    elseif tag == "subzone" then W.subzone = "Area " .. a.area
    elseif tag == "hs" or tag == "home" or tag == "fly" or tag == "fp" then
        P.SetMark(view.route.id, si, entry.i)
    end
end

-- Spielt die aktive Route durch. Liefert Anzahl Hauptschritte, Fehlertext bei Haenger.
local function PlayRoute(maxIter)
    local mains, lastMain, same = 0, nil, 0
    for _ = 1, maxIter do
        local view = R.Evaluate()
        if view.finished then return mains, nil, view end
        if view.main == lastMain then
            same = same + 1
            if same > 3 then
                local at = view.main or view.open[1]
                local tags = {}
                for _, e in ipairs(P.Actions(view.route.s[at], S.Player())) do tags[#tags + 1] = e.a[1] end
                return mains, ("haengt an Schritt %d (%s)"):format(at, table.concat(tags, ",")), view
            end
        else
            same, lastMain, mains = 0, view.main, mains + 1
        end
        -- Wegpunkt erreichen, dann alle offenen blockierenden Handlungen erledigen
        local wp = R.Waypoint(view)
        if wp then W.pos = wp end
        for _, si in ipairs(view.sticky) do
            for _, e in ipairs(P.Actions(view.route.s[si], S.Player())) do
                if P.BLOCKING[e.a[1]] then Perform(view, si, e) end
            end
        end
        -- Nachhol-Schritt aus einer anderen Route zuerst erledigen
        if view.catchup then
            local c = view.catchup
            for _, e in ipairs(P.Actions(c.route.s[c.si], S.Player())) do
                if P.BLOCKING[e.a[1]] then Perform(view, c.si, e) end
            end
        end
        -- Haupt-Schritt und zurueckgestellte, jetzt abgebbare Schritte (eine Route ist erst fertig,
        -- wenn auch die erledigt sind)
        local todo = {}
        if view.main then todo[#todo + 1] = view.main end
        for _, si in ipairs(view.open) do todo[#todo + 1] = si end
        for _, si in ipairs(todo) do
            for _, e in ipairs(P.Actions(view.route.s[si], S.Player())) do
                if P.BLOCKING[e.a[1]] and not P.Done(e.a, { routeId = view.route.id, si = si, ai = e.i }) then
                    Perform(view, si, e)
                end
            end
        end
    end
    return mains, "Iterationsgrenze erreicht"
end

-------------------------------------------------------------------------------
local fails = 0
local function check(label, ok, detail)
    if not ok then fails = fails + 1 end
    io.write(("%-62s %s%s\n"):format(label, ok and "OK" or "FEHLER", detail and ("  " .. detail) or ""))
end

-- Bedingungen
local function C(text, over)
    local ctx = { race = "Human", class = "PALADIN", faction = "Alliance", level = 14, game = "FOREVER", sex = 2, locale = "enUS" }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ns.Cond.Eval(text, ctx)
end
check("Bedingung 'Human' fuer Mensch", C("Human"))
check("Bedingung '!Hunter' fuer Paladin", C("!Hunter"))
check("Bedingung 'NightElf/Dwarf' fuer Mensch falsch", not C("NightElf/Dwarf"))
check("Bedingung '!NightElf !Hunter/!Dwarf !Hunter'", C("!NightElf !Hunter/!Dwarf !Hunter"))
check("Bedingung 'Dwarf Hunter/Human Hunter' fuer Paladin falsch", not C("Dwarf Hunter/Human Hunter"))
check("Bedingung Level '15' bei Level 14 falsch", not C("15"))
check("Bedingung Klammern '!(Hunter/Warrior) Human'", C("!(Hunter/Warrior) Human"))
check("Bedingung Spiel 'FOREVER'", C("FOREVER") and not C("TBC"))

-- Routenwahl
-- Seit 2026-11-17 führt "11-13 Loch Modan" (Menschen-Weg) laut Quelle in "13-15 Westfall" (vorher ging diese
-- #next-Zeile verloren). Unfertig gilt dort "Vorgänger zuerst" wie bei Darkshore unten; die Westfall-Prüfung
-- setzt daher einen gespielten Loch-Modan-Abschnitt voraus.
ns.cdb.route = nil
local lochFirst = R.FindRoute(S.Player())
check("Routenwahl Level 13 Mensch, Loch Modan unfertig: Vorgänger 11-13 Loch Modan zuerst",
    lochFirst and lochFirst.n == "11-13 Loch Modan", lochFirst and lochFirst.n)
local function PlayedLochModan()
    for _, s in ipairs(R.Get("A:route:11-13 Loch Modan").s) do
        for _, a in ipairs(s.a) do if a.q then W.turned[a.q] = true end end
    end
end
PlayedLochModan()
local best = R.FindRoute(S.Player())
check("Routenwahl Level 13 Mensch Paladin: 13-15 Westfall", best and best.n == "13-15 Westfall", best and best.n)
for q in pairs(W.turned) do W.turned[q] = nil end

-- Durchlauf Westfall. Spielwelt wie nach den Vorgaenger-Routen: Quests, die Westfall abgibt, aber nicht
-- selbst annimmt, stehen fertig im Log (sonst entfallen ihre Abgaben zu Recht).
do
    local acceptedHere, turnedHere = {}, {}
    for _, s in ipairs(R.Get("A:route:13-15 Westfall").s) do
        for _, a in ipairs(s.a) do
            if a[1] == "accept" then acceptedHere[a.q] = true end
            if a[1] == "turnin" then turnedHere[a.q] = true end
        end
    end
    for q in pairs(turnedHere) do
        if not acceptedHere[q] then W.onLog[q], W.all[q] = true, true end
    end
end
R.Load("A:route:13-15 Westfall")
local mains, err, view = PlayRoute(4000)
check("Westfall komplett durchgespielt ohne Haenger", err == nil, err or (mains .. " Hauptschritte"))
check("Westfall: Quests angenommen und abgegeben", (performed.accept or 0) > 10 and (performed.turnin or 0) > 10,
    ("%d angenommen, %d abgegeben"):format(performed.accept or 0, performed.turnin or 0))
local nextId = view and R.Advance(view)
check("Folge-Route geladen: 14-16 Darkshore", nextId == "A:route:14-16 Darkshore", tostring(nextId))

-- Einstieg mitten in der Route: halbe Westfall-Quests schon abgegeben
ResetWorld(14)
local west = R.Get("A:route:13-15 Westfall")
local turnins = {}
for _, s in ipairs(west.s) do for _, a in ipairs(s.a) do if a[1] == "turnin" then turnins[#turnins + 1] = a.q end end end
for i = 1, math.floor(#turnins / 2) do W.turned[turnins[i]] = true end
R.Load(west.id)
local v = R.Evaluate()
check("Einstieg in der Mitte: aktueller Schritt nach Schritt 1", v.main and v.main > 1, "Schritt " .. tostring(v.main))

-- Texte
local t = ns.Text.Action({ "accept", q = 6285, t = "Accept Return to Lewis" })
check("Text: Annahme mit Questname", t and t:find("Annehmen") and t:find("Quest 6285"))
check("Text: Marken werden eingefaerbt", ns.Text.Render("{enemy:Defias}"):find("|cffff5f4aDefias|r", 1, true) ~= nil)

-------------------------------------------------------------------------------
-- Haenger aus dem Spiel (2026-11-09): 16-19 Darkshore, Schritt 4 "The Cliffspring River" abgeben,
-- Quest im Log, Ziel aber nie erledigt, weil Route 14-16 uebersprungen wurde.
-------------------------------------------------------------------------------
local DS = "A:route:16-19 Darkshore"
ResetWorld(16)
ns.cdb.open = {}
W.onLog[4762], W.onLog[4740] = true, true
R.Load(DS)
v = R.Evaluate()
check("Darkshore: Haupt-Schritt bleibt die Abgabe (Schritt 4)", v.main == 4, "Schritt " .. tostring(v.main))
-- Schritt mit dem Ziel von Quest 4762 in 14-16 Darkshore (vor 2026-11-17 Nummer 185; seit #include stehen
-- eingebundene Schritte davor, die Nummer ergibt sich deshalb aus den Daten)
local goalStep
for si, s in ipairs(R.Get("A:route:14-16 Darkshore").s) do
    for _, a in ipairs(s.a) do if a[1] == "complete" and a.q == 4762 and not goalStep then goalStep = si end end
end
check("Darkshore: Ziel wird aus 14-16 Darkshore nachgeholt",
    v.catchup and v.catchup.route.id == "A:route:14-16 Darkshore" and v.catchup.si == goalStep,
    v.catchup and (v.catchup.route.id .. " #" .. v.catchup.si) or "kein Nachholen")
local wp = R.Waypoint(v)
check("Darkshore: Pfeil zeigt zum Fluss (Nachhol-Ziel), nicht zum Questgeber",
    wp and math.floor(wp.x) == -387 and math.floor(wp.y) == 7219, wp and (wp.x .. "," .. wp.y) or "kein Ziel")
W.obj["4762:1"], W.all[4762] = true, true
v = R.Evaluate()
check("Darkshore: Ziel erledigt -> kein Nachholen, Abgabe ist dran", v.main == 4 and v.catchup == nil,
    "Schritt " .. tostring(v.main))
W.onLog[4762], W.turned[4762], W.onLog[4763] = nil, true, true
v = R.Evaluate()
check("Darkshore: nach Abgabe geht es weiter", v.main and v.main > 4, "Schritt " .. tostring(v.main))
local mainsDS, errDS = PlayRoute(4000)
check("Darkshore 16-19 ab hier ohne Haenger durchgespielt", errDS == nil, errDS or (mainsDS .. " Hauptschritte"))

-- Ohne Nachhol-Quelle in der Zone: Abgabe wird zurueckgestellt, Route laeuft weiter
ResetWorld(16)
ns.cdb.open = {}
W.onLog[4762], W.onLog[4740] = true, true
local realSources = R.QuestSources
R.QuestSources = function() return {} end
R.Load(DS)
v = R.Evaluate()
check("Ohne Quelle: Abgabe zurueckgestellt, Route geht weiter", v.main and v.main > 4 and v.waiting == 1
    and ns.cdb.open[DS] and ns.cdb.open[DS][4] == 4762, "Schritt " .. tostring(v.main) .. ", wartend " .. v.waiting)
W.all[4762] = true
v = R.Evaluate()
check("Zurueckgestellte Abgabe erscheint, sobald die Quest fertig ist", v.open[1] == 4, "offen: " .. tostring(v.open[1]))
W.onLog[4762], W.turned[4762], W.onLog[4763] = nil, true, true -- abgegeben, Folgequest angenommen
v = R.Evaluate()
check("Abgegebene zurueckgestellte Quest wird vergessen", #v.open == 0 and ns.cdb.open[DS][4] == nil)
R.QuestSources = realSources

-- Quest nie angenommen: Abgabe und Folgequest werden uebersprungen
ResetWorld(16)
ns.cdb.open = {}; W.onLog[4740] = true
R.Load(DS)
v = R.Evaluate()
check("Nie begonnene Reihe: Abgabe + Folgequest uebersprungen", v.main and v.main > 4, "Schritt " .. tostring(v.main))

-- Questlog noch nicht geladen: nichts ueberspringen, Zeiger bleibt
ResetWorld(16)
ns.cdb.open = {}
ns.questsReady = false
R.Load(DS)
ns.cdb.pointer[DS] = 4
W.onLog[4762] = nil
R.Evaluate()
check("Questlog nicht geladen: Zeiger und Zurueckgestellt unveraendert",
    ns.cdb.pointer[DS] == 4 and next(ns.cdb.open[DS] or {}) == nil, "Zeiger " .. tostring(ns.cdb.pointer[DS]))
ns.questsReady = nil

-- Reise ueberholt: Ruhestein-Schritt gilt, sobald du an einem spaeteren Wegpunkt stehst
local hsRoute, hsSi, hsGoto
for _, r in ipairs(R.Candidates(S.Player(), "route")) do
    for si, s in ipairs(r.s) do
        local only = #P.Actions(s, S.Player()) > 0
        for _, e in ipairs(P.Actions(s, S.Player())) do
            if P.BLOCKING[e.a[1]] and e.a[1] ~= "hs" then only = false end
        end
        local hasHs = false
        for _, e in ipairs(P.Actions(s, S.Player())) do if e.a[1] == "hs" then hasHs = true end end
        local probe = { level = r.lo }
        for k, val in pairs(S.Player()) do if k ~= "level" then probe[k] = val end end
        if only and hasHs and not s.c and not s.cw and not s.st and not s.o and P.Applies(s, probe) then
            for j = si + 1, math.min(#r.s, si + 3) do
                for _, a in ipairs(r.s[j].a) do
                    if a[1] == "goto" and not r.s[j].c and not a.c and P.Applies(r.s[j], probe) then
                        hsGoto = a
                        break
                    end
                end
                if hsGoto then break end
            end
            if hsGoto then hsRoute, hsSi = r, si break end
        end
    end
    if hsRoute then break end
end
if hsRoute then
    ResetWorld(hsRoute.lo)
    ns.cdb.open = {}
    R.Load(hsRoute.id)
    ns.cdb.pointer[hsRoute.id] = hsSi
    v = R.Evaluate()
    local before = v.main
    W.pos = hsGoto
    v = R.Evaluate()
    check("Ruhestein-Schritt ueberholt, wenn spaeterer Wegpunkt erreicht",
        before == hsSi and v.main ~= hsSi,
        hsRoute.n .. " #" .. hsSi .. ": vorher " .. tostring(before) .. ", nachher " .. tostring(v.main))
else
    check("Ruhestein-Schritt fuer Test gefunden", false)
end

-- Zone und Ruhestein-Ort sprachunabhaengig ueber IDs
local zoneA = { "zone", to = "Darkshore", zm = 1439 }
W.map = 1439
check("Zone per Karten-ID erledigt", P.Done(zoneA) == true)
W.map = 1436
check("Zone per Karten-ID offen in anderer Zone", P.Done(zoneA) == false)
W.bound = 442
check("Ruhestein-Ort per Gebiets-ID erkannt", P.Done({ "home", area = 442 }, { routeId = "x", si = 1, ai = 1 }) == true)

-- Datenbank: Zonen-Handlungen tragen Karten-IDs, home traegt den Ort
-- (Nur Schritte mit bindlocation liefern einen Ort; die übrigen erkennt Live.lua am Ereignis
-- HEARTHSTONE_BOUND oder die Überholt-Regel.)
local zoneTotal, zoneIds, homeTotal, homeArea = 0, 0, 0, 0
for _, r in ipairs(ns.routes) do
    for _, s in ipairs(r.s) do
        local hasBind = false
        for _, a in ipairs(s.a) do if a[1] == "bindlocation" and tonumber(a.to) then hasBind = true end end
        for _, a in ipairs(s.a) do
            if a[1] == "zone" then zoneTotal = zoneTotal + 1; if a.zm then zoneIds = zoneIds + 1 end end
            if a[1] == "home" and hasBind then homeTotal = homeTotal + 1; if a.area then homeArea = homeArea + 1 end end
        end
    end
end
check("Zonen-Handlungen mit Karten-ID", zoneIds == zoneTotal, zoneIds .. "/" .. zoneTotal)
check("home-Handlungen mit bindlocation tragen die Gebiets-ID", homeTotal > 0 and homeArea == homeTotal,
    homeArea .. "/" .. homeTotal)

-- Alle Allianz-Startrouten bis Level 20 ohne Haenger (Human Paladin)
local stuck, tested = {}, 0
for _, r in ipairs(R.Candidates(S.Player(), "route")) do
    if r.hi <= 60 then
        ResetWorld(r.lo)
        tested = tested + 1
        R.Load(r.id)
        local _, e = PlayRoute(6000)
        if e then stuck[#stuck + 1] = r.n .. ": " .. e end
    end
end
check("Alle Routen 1-60 (Mensch Paladin, Forever und Classic) ohne Haenger", #stuck == 0, #stuck > 0 and table.concat(stuck, " | ") or (tested .. " Routen gespielt"))

-- Eskorte (Therylune, 2026-11-10): Quest fertig, das einzelne Ziel meldet der Client weiter als offen
ResetWorld(16)
W.onLog[945] = true
local escort = { "complete", q = 945, o = 1 }
check("Eskorte: offenes Ziel, Quest nicht fertig -> Schritt offen", P.Done(escort) == false)
W.all[945] = true -- Quest als Ganzes fertig, W.obj["945:1"] bleibt leer
check("Eskorte: Quest fertig -> Schritt erledigt, auch wenn das Ziel 0/1 meldet", P.Done(escort) == true)
-- Vorgaenger zuerst (2026-11-10): Level 16, Route 14-16 nie gespielt -> erst 14-16, nicht 16-19
ResetWorld(16)
ns.cdb.route = nil
local pick = R.FindRoute(S.Player())
check("Routenwahl Level 16 ohne Vorgaenger-Quests: 14-16 Darkshore zuerst", pick and pick.n == "14-16 Darkshore", pick and pick.n)
-- Vorgaenger erledigt (alle Abgaben gemacht) -> Folge-Route
for _, s in ipairs(R.Get("A:route:14-16 Darkshore").s) do
    for _, a in ipairs(s.a) do if a.q then W.turned[a.q] = true end end
end
pick = R.FindRoute(S.Player())
check("Routenwahl Level 16 mit erledigtem Vorgaenger: 16-19 Darkshore", pick and pick.n == "16-19 Darkshore", pick and pick.n)
ResetWorld(13)
PlayedLochModan()
pick = R.FindRoute(S.Player())
check("Routenwahl Level 13 bleibt 13-15 Westfall", pick and pick.n == "13-15 Westfall", pick and pick.n)
-- Verschachtelte Klammern in Bedingungen
check("Bedingung verschachtelt '!(Hunter/(Warrior Human))' fuer Paladin", C("!(Hunter/(Warrior Human))"))
check("Bedingung verschachtelt '(Human (Paladin/Mage))'", C("(Human (Paladin/Mage))") and not C("(Human (Hunter/Mage))"))
-- Dungeon-Schritte: Vorgabe aus, per Einstellung an
local dungeonStep = { a = { { "dungeon", to = "DM" }, { "accept", q = 1 } } }
ns.db.dungeonSteps = false
check("Dungeon-Schritt ohne Einstellung ausgeblendet", P.Applies(dungeonStep, S.Player()) == false)
ns.db.dungeonSteps = true
check("Dungeon-Schritt mit Einstellung sichtbar", P.Applies(dungeonStep, S.Player()) == true)
ns.db.dungeonSteps = false
-- Berufsstufen (2026-11-11: "Kochen auf 10 farmen" erschien bei Kochen 38)
local cookStep = { a = { { "collect", i = 6889, n = 10 }, { "skill", name = "cooking", lvl = 10, skip = true },
  { "skill", name = "cooking", lvl = 1, rev = true, skip = true } } }
local cookLevel
S.SkillLevel = function(name) if name == "cooking" then return cookLevel end end
cookLevel = 38
check("Beruf: Kochen 38 -> Farm-Schritt fuer Kochen 10 entfaellt", P.Applies(cookStep, S.Player()) == false)
cookLevel = 5
check("Beruf: Kochen 5 -> Farm-Schritt bleibt", P.Applies(cookStep, S.Player()) == true)
cookLevel = -1
check("Beruf: Kochen nicht erlernt -> Schritt entfaellt (<1)", P.Applies(cookStep, S.Player()) == false)
cookLevel = nil
check("Beruf: Stufe unbekannt -> Schritt bleibt sichtbar", P.Applies(cookStep, S.Player()) == true)
S.SkillLevel = function() return nil end
-- Datenbank: Fertigkeits-Bedingungen tragen Stufe und Kennzeichen
local skillTotal, skillOk = 0, 0
for _, r in ipairs(ns.routes) do
  for _, s in ipairs(r.s) do
    for _, a in ipairs(s.a) do
      if a[1] == "skill" then skillTotal = skillTotal + 1; if a.lvl and a.name then skillOk = skillOk + 1 end end
    end
  end
end
check("Datenbank: alle Fertigkeits-Bedingungen mit Beruf und Stufe", skillTotal > 0 and skillOk == skillTotal, skillOk .. "/" .. skillTotal)
-------------------------------------------------------------------------------
-- Schlafsack-Questreihe (2026-11-13): "Bonus route finished" mitten in der Kette. Zustand aus den
-- SavedVariables: Zeiger 3 (Abgabe 79192, Annahme 79980), Rückweg zur Leveling-Route gemerkt.
-------------------------------------------------------------------------------
load("src/Data/Extra.lua")
for _, r in ipairs(ns.BuildExtraRoutes()) do
    if r.f == "A" then ns.routes[#ns.routes + 1] = r end
end
R.Reindex()
local BAG = ns.SLEEPING_BAG_ROUTE.Alliance
local BACK = "A:route:16-19 Darkshore"
local function BagState()
    ResetWorld(18)
    ns.cdb.route, ns.cdb.returnRoute = BAG, BACK
    ns.cdb.pointer[BAG] = 3
    W.turned[79008] = true
end
check("Schlafsack-Route geladen", R.Get(BAG) ~= nil)

-- a) Questziel offen, keine Nachhol-Quelle: die Abgabe darf nicht zurückgestellt werden, sonst ist die
--    Kette ohne offenen Schritt und meldet sich fertig.
BagState()
W.onLog[79192] = true
local realOpen = S.HasOpenObjectives
S.HasOpenObjectives = function(q) if q == 79192 then return true end return realOpen(q) end
v = R.Evaluate()
check("Schlafsack: Quest mit offenem Ziel -> nicht fertig, Schritt 3 bleibt",
    not v.finished and v.main == 3 and v.waiting == 0,
    "fertig " .. tostring(v.finished) .. ", Schritt " .. tostring(v.main) .. ", wartend " .. v.waiting)
S.HasOpenObjectives = realOpen

-- b) Quest gerade abgegeben, Abschluss-Flag noch nicht gesetzt (oder Quest nicht im Log): die
--    Folgeschritte gelten nicht als "Kette nie begonnen".
BagState()
v = R.Evaluate()
check("Schlafsack: Quest weder im Log noch abgegeben -> nicht fertig",
    not v.finished and v.main == 3, "fertig " .. tostring(v.finished) .. ", Schritt " .. tostring(v.main))

-- c) Mitten in der Kette neu gestartet: Stand ergibt sich aus dem Questlog
BagState()
ns.cdb.pointer[BAG] = nil
W.turned[79192], W.onLog[79980] = true, true
v = R.Evaluate()
check("Schlafsack: Neustart mit 79980 im Log -> Abgabe 79980 (Schritt 4)", not v.finished and v.main == 4,
    "Schritt " .. tostring(v.main))

-- d) Ganze Kette abgegeben: fertig
BagState()
for _, q in ipairs({ 79192, 79980, 79974, 79975, 79976 }) do W.turned[q] = true end
v = R.Evaluate()
check("Schlafsack: alle Quests abgegeben -> fertig", v.finished == true, "Schritt " .. tostring(v.main))

-- e) Durchspielen ab Zeiger 3 ohne Haenger und ohne vorzeitiges Ende
BagState()
W.onLog[79192] = true
local _, bagErr, bagView = PlayRoute(200)
check("Schlafsack: ab Schritt 3 bis zur letzten Abgabe durchgespielt",
    bagErr == nil and bagView and bagView.finished and W.turned[79976] == true,
    bagErr or ("79976 abgegeben: " .. tostring(W.turned[79976])))
ns.cdb.route, ns.cdb.returnRoute = nil, nil

-------------------------------------------------------------------------------
-- Audit 2026-11-16: synthetische Routen für Randfälle der Auswertung
-------------------------------------------------------------------------------
local function AddRoute(r)
    r.f, r.lo, r.hi = r.f or "A", r.lo or 1, r.hi or 60
    ns.routes[#ns.routes + 1] = r
    R.Reindex()
    return r
end

-- a) Reisekette in der Dungeon-Vorbereitung: Flug, dann Laufweg, dann Quest. Der Flug entfällt nicht,
--    nur weil danach noch eine Reise kommt (Audit: "Flug nach Wetlands" wurde übersprungen).
ResetWorld(22)
W.zone = "Westfall"
AddRoute({ id = "T:dungeonquests:kette", k = "dungeonquests", n = "Kette", s = {
    { a = { { "fly", to = "Wetlands" } } },
    { a = { { "zone", to = "Hillsbrad Foothills" } } },
    { a = { { "accept", q = 900201 }, { "target", names = { "NpcA" } } } },
    { a = { { "complete", q = 900201 } } },
} })
ns.cdb.route = "T:dungeonquests:kette"
local tv = R.Evaluate()
check("Vorbereitung: Flug vor einem Laufweg bleibt Haupt-Schritt", tv.main == 1, "Schritt " .. tostring(tv.main))

-- b) Reise in eine Gegend, deren Quests du schon hast, entfällt weiter, wenn danach ein Flug folgt
ResetWorld(22)
W.onLog[900202] = true
AddRoute({ id = "T:dungeonquests:leer", k = "dungeonquests", n = "Leer", s = {
    { a = { { "fly", to = "Wetlands" } } },
    { a = { { "accept", q = 900202 }, { "target", names = { "NpcA" } } } },
    { a = { { "fly", to = "Southshore" } } },
    { a = { { "accept", q = 900203 }, { "target", names = { "NpcB" } } } },
    { a = { { "complete", q = 900202 } } },
    { a = { { "complete", q = 900203 } } },
} })
ns.cdb.route = "T:dungeonquests:leer"
tv = R.Evaluate()
check("Vorbereitung: Flug ins Leere entfällt, Flug zur offenen Quest bleibt", tv.main == 3, "Schritt " .. tostring(tv.main))

-- c) "Nicht angeboten" gilt nur für Quests des angesprochenen NPCs (Audit: Gespräch mit A strich die Quests von B)
do
    local step = { a = { { "accept", q = 900101 }, { "target", names = { "NpcA" } }, { "goto", m = 1, x = 1, y = 1 },
        { "accept", q = 900102 }, { "target", names = { "NpcB" } }, { "goto", m = 1, x = 2, y = 2 } } }
    local actions = P.Actions(step, S.Player())
    local all = function() return true end
    local miss = R.NotOffered and R.NotOffered(actions, all, function(n) return n == "NpcA" end, {}) or {}
    check("Nicht angeboten: nur die Quest von NpcA", #miss == 1 and miss[1] == 900101, table.concat(miss, ","))
    miss = R.NotOffered and R.NotOffered(actions, all, function(n) return n == "NpcC" end, {}) or { 0 }
    check("Nicht angeboten: fremder NPC folgert nichts", #miss == 0, table.concat(miss, ","))
    local mixed = { a = { { "accept", q = 900103 }, { "target", names = { "NpcA" } }, { "target", names = { "NpcB" } } } }
    miss = R.NotOffered and R.NotOffered(P.Actions(mixed, S.Player()), all, function(n) return n == "NpcA" end, {}) or { 0 }
    check("Nicht angeboten: zwei NPCs im selben Abschnitt -> kein Schluss", #miss == 0, table.concat(miss, ","))
    local withTurnin = { a = { { "turnin", q = 900104 }, { "accept", q = 900105 }, { "target", names = { "NpcA" } } } }
    miss = R.NotOffered and R.NotOffered(P.Actions(withTurnin, S.Player()), all, function(n) return n == "NpcA" end, {}) or { 0 }
    check("Nicht angeboten: offene Abgabe beim selben NPC -> kein Schluss", #miss == 0, table.concat(miss, ","))
end

-- d) "Zurück" zeigt den vorigen Schritt, auch wenn er erledigt ist, bis du weiterklickst
ResetWorld(22)
AddRoute({ id = "T:route:zurueck", k = "route", n = "Zurueck", s = {
    { a = { { "accept", q = 900301 } } },
    { a = { { "accept", q = 900302 } } },
    { a = { { "accept", q = 900303 } } },
} })
ns.cdb.route = "T:route:zurueck"
W.onLog[900301], W.onLog[900302] = true, true
tv = R.Evaluate()
local backTo = R.Back(tv)
local tv2 = R.Evaluate()
check("Zurück: voriger (erledigter) Schritt bleibt Haupt-Schritt", tv.main == 3 and backTo == 2 and tv2.main == 2,
    ("vorher %s, zurück %s, danach %s"):format(tostring(tv.main), tostring(backTo), tostring(tv2.main)))
R.Skip(tv2.main)
tv2 = R.Evaluate()
check("Zurück: Überspringen geht wieder vorwärts", tv2.main == 3, "Schritt " .. tostring(tv2.main))

-- e) Optionale Abgabe (negative ID in der Quelle): wird abgegeben, wenn fertig, hält sonst nicht an
check("Optionale Abgabe: Konverter liefert positive IDs",
    (function()
        for _, r in ipairs(ns.routes) do for _, st in ipairs(r.s) do for _, a in ipairs(st.a) do
            if a[1] == "turnin" and a.q and a.q < 0 then return false end
        end end end
        return true
    end)())
ResetWorld(22)
local optTurnin = { "turnin", q = 900401, opt = true }
W.onLog[900401] = true
HAS_OBJECTIVES[900401] = true
check("Optionale Abgabe: Quest mit offenem Ziel blockiert nicht", P.Done(optTurnin) == true)
W.all[900401] = true
check("Optionale Abgabe: fertige Quest wird abgegeben", P.Done(optTurnin) == false)
ns.cdb.route = nil

-- f) Überspringen in der Dungeon-Vorbereitung wirkt sofort; die Quest wird am Ende trotzdem noch geholt
ResetWorld(22)
AddRoute({ id = "T:dungeonquests:skip", k = "dungeonquests", n = "Skip", s = {
    { a = { { "accept", q = 900501 }, { "target", names = { "NpcA" } } } },
    { a = { { "accept", q = 900502 }, { "target", names = { "NpcB" } } } },
    { a = { { "complete", q = 900501 } } },
    { a = { { "complete", q = 900502 } } },
} })
ns.cdb.route = "T:dungeonquests:skip"
tv = R.Evaluate()
R.Skip(tv.main)
tv2 = R.Evaluate()
check("Vorbereitung: Überspringen geht zur nächsten offenen Quest", tv.main == 1 and tv2.main == 2,
    ("vorher %s, danach %s"):format(tostring(tv.main), tostring(tv2.main)))
W.onLog[900502] = true
tv2 = R.Evaluate()
check("Vorbereitung: danach zurück zur übersprungenen Quest", tv2.main == 1 and not tv2.finished,
    "Schritt " .. tostring(tv2.main))
ns.cdb.route = nil

-- g) Zurückgestellte Abgabe beim Routenwechsel in die Folgeroute mitnehmen (Entscheidung 2026-11-16)
ResetWorld(22)
ns.cdb.carry = {}
AddRoute({ id = "T:route:alt", k = "route", n = "Alt", s = {
    { a = { { "accept", q = 900601 } } },
    { a = { { "turnin", q = 900601 } } },
} })
AddRoute({ id = "T:route:neu", k = "route", n = "Neu", s = {
    { a = { { "accept", q = 900602 } } },
} })
HAS_OBJECTIVES[900601] = true
W.onLog[900601] = true
ns.cdb.route = "T:route:alt"
tv = R.Evaluate()
check("Mitnahme: Abgabe mit offenem Ziel zurückgestellt, Route fertig", tv.finished == true and tv.waiting == 1,
    "fertig " .. tostring(tv.finished) .. ", wartend " .. tv.waiting)
R.Load("T:route:neu")
tv = R.Evaluate()
check("Mitnahme: Folgeroute zählt die Abgabe als wartend", tv.waiting == 1 and #tv.carried == 0,
    "wartend " .. tv.waiting .. ", mitgenommen " .. #(tv.carried or {}))
W.all[900601] = true
tv = R.Evaluate()
local shownCarry = false
for _, ref in ipairs(R.Shown(tv)) do
    if ref.route.id == "T:route:alt" and ref.si == 2 and ref.kind == "open" then shownCarry = true end
end
check("Mitnahme: Quest fertig -> Abgabe erscheint in der Folgeroute", shownCarry and tv.main == 1,
    "angezeigt " .. tostring(shownCarry) .. ", Schritt " .. tostring(tv.main))
W.onLog[900601], W.turned[900601] = nil, true
tv = R.Evaluate()
check("Mitnahme: abgegeben -> aus der Liste", #tv.carried == 0 and #(ns.cdb.carry or {}) == 0 and tv.waiting == 0,
    "Liste " .. #(ns.cdb.carry or {}))
ns.cdb.route, ns.cdb.carry = nil, {}

-- h) Wegkette (Screenshot 2026-11-17, "Reise nach Ratchet"): ein erreichter Zwischenpunkt bleibt erreicht.
--    Vorher galt er wieder als offen, sobald du seinen Radius verlassen hast, und der Pfeil schickte dich
--    zurück ("Laufe zu Ashenvale", vor und zurück).
ResetWorld(22)
do
    local g1 = { "goto", m = 1440, x = 1, y = 1, w = true, ci = 1, r = 50 }
    local g2 = { "goto", m = 1413, x = 2, y = 2, w = true, ci = 1, r = 35 }
    local g3 = { "goto", m = 1413, x = 3, y = 3, w = true, ci = 1 }
    AddRoute({ id = "T:route:wegkette", k = "route", n = "Wegkette", s = {
        { a = { g1, g2, g3, { "subzone", area = 392 } } },
    } })
    ns.cdb.route = "T:route:wegkette"
    local function Wp() return (R.Waypoint(R.Evaluate())) end
    local start = Wp()
    W.pos = g1
    local atFirst = Wp()
    W.pos = nil -- unterwegs zwischen erstem und zweitem Punkt
    local between = Wp()
    check("Wegkette: erst Punkt 1, dort Punkt 2", start == g1 and atFirst == g2)
    check("Wegkette: nach Punkt 1 unterwegs weiter Punkt 2, nicht zurück", between == g2,
        between == g1 and "zurück zu Punkt 1" or tostring(between and between.x))
    W.pos = g3
    local atEnd = Wp()
    W.pos = nil
    check("Wegkette: Endpunkt verlassen -> Pfeil wieder zum Endpunkt", atEnd == nil and Wp() == g3)
    ns.cdb.route = nil
end

-- j) Audit 2026-11-17: Mitgenommene Abgabe kommt bei der Rückkehr in ihre Route zurück (vorher verwarf die
--    Route sie, weil sie die Abgabe selbst enthält, ihr Zeiger aber schon dahinter stand: Abgabe weg)
ResetWorld(22)
ns.cdb.carry = {}
AddRoute({ id = "T:route:hin", k = "route", n = "Hin", s = {
    { a = { { "accept", q = 900701 } } },
    { a = { { "turnin", q = 900701 } } },
    { a = { { "accept", q = 900702 } } },
} })
HAS_OBJECTIVES[900701] = true
W.onLog[900701] = true
R.Load("T:route:hin")
tv = R.Evaluate()
R.Load("T:route:neu")
R.Load("T:route:hin")
tv = R.Evaluate()
check("Mitnahme: zurück in der eigenen Route wartet die Abgabe weiter", tv.waiting == 1,
    "wartend " .. tv.waiting .. ", Schritt " .. tostring(tv.main))
W.all[900701] = true
tv = R.Evaluate()
local backShown = false
for _, ref in ipairs(R.Shown(tv)) do if ref.route.id == "T:route:hin" and ref.si == 2 then backShown = true end end
check("Mitnahme: Quest fertig -> Abgabe wieder sichtbar", backShown, "Schritt " .. tostring(tv.main))
ns.cdb.route, ns.cdb.carry = nil, {}

-- k) Audit 2026-11-17: Zurückgestellte Abgabe einer abgebrochenen Quest blockiert die Route nicht (vorher
--    blieb die Folge-Annahme im selben Schritt offen, und die Route wurde nie fertig)
ResetWorld(22)
AddRoute({ id = "T:route:abbruch", k = "route", n = "Abbruch", s = {
    { a = { { "accept", q = 900801 } } },
    { a = { { "turnin", q = 900801 }, { "accept", q = 900802 } } },
} })
HAS_OBJECTIVES[900801] = true
W.onLog[900801] = true
R.Load("T:route:abbruch")
tv = R.Evaluate()
local parked = tv.waiting
W.onLog[900801] = nil -- abgebrochen
tv = R.Evaluate()
check("Zurückgestellt: abgebrochene Quest gibt die Route frei (neu annehmen statt toter Folge-Annahme)",
    parked == 1 and #tv.open == 0 and tv.main == 1,
    "geparkt " .. parked .. ", Schritt " .. tostring(tv.main) .. ", offen " .. #tv.open)
ns.cdb.route = nil

-- l) Audit 2026-11-17: Kopfbedingung der Quelle gilt ("<< Alliance Hunter"). Vorher bekam der Paladin die
--    Jäger-Route 21-23 Ashenvale/Stonetalon angeboten.
ResetWorld(21)
do
    local hunterRoute, other = false, false
    for _, r in ipairs(R.Candidates(S.Player(), "route")) do
        if r.id == "A:route:21-23 Ashenvale/Stonetalon" then hunterRoute = true end
        if r.id == "A:route:21-23 Stonetalon/Ashenvale" then other = true end
    end
    check("Routenwahl: Paladin bekommt keine Jäger-Route, aber die allgemeine", not hunterRoute and other,
        "Jäger-Route " .. tostring(hunterRoute) .. ", allgemeine " .. tostring(other))
end

-- m) Audit 2026-11-17: Neustart einer Route vergisst Ereignis-Marken (vorher galt ein früherer Flug sofort
--    als erledigt)
ResetWorld(22)
AddRoute({ id = "T:dungeonquests:neustart", k = "dungeonquests", n = "Neustart", s = {
    { a = { { "fly", to = "Wetlands" } } },
    { a = { { "accept", q = 900901 } } },
} })
P.SetMark("T:dungeonquests:neustart", 1, 1)
R.Restart("T:dungeonquests:neustart")
tv = R.Evaluate()
check("Neustart: Flug-Schritt wieder offen", tv.main == 1, "Schritt " .. tostring(tv.main))
ns.cdb.route = nil

-- n) Audit 2026-11-17: Datenupdate ändert die Schrittfolge -> gespeicherte Schrittnummern dieser Route gelten
--    nicht mehr (vorher zeigte der alte Zeiger auf falsche Schritte)
ResetWorld(22)
do
    local r = AddRoute({ id = "T:route:fassung", k = "route", n = "Fassung", v = 111, s = {
        { a = { { "accept", q = 901001 } } }, { a = { { "accept", q = 901002 } } },
    } })
    ns.cdb.ver = {}
    R.CheckVersions()
    ns.cdb.pointer["T:route:fassung"], ns.cdb.manual["T:route:fassung"] = 2, { [1] = true }
    local same = R.CheckVersions()
    local kept = ns.cdb.pointer["T:route:fassung"] == 2
    r.v = 222
    local reset = R.CheckVersions()
    check("Fassung: gleiche Daten behalten den Stand, geänderte verwerfen ihn", same == 0 and kept and reset == 1
        and ns.cdb.pointer["T:route:fassung"] == nil and ns.cdb.manual["T:route:fassung"] == nil,
        ("gleich %d, behalten %s, verworfen %d"):format(same, tostring(kept), reset))
end

-- o) Regression 2026-11-17: Rundweg (erster und letzter Punkt gleich). Am Startpunkt führt der Pfeil zu
--    Punkt 2, nicht ins Leere (das Gedächtnis sprang auf den letzten, gleichen Punkt und übersprang alles)
ResetWorld(22)
do
    local g1 = { "goto", m = 1440, x = 1, y = 1, w = true, ci = 1, r = 30 }
    local g2 = { "goto", m = 1440, x = 2, y = 2, w = true, ci = 1, r = 30 }
    local g3 = { "goto", m = 1440, x = 3, y = 3, w = true, ci = 1, r = 30 }
    AddRoute({ id = "T:route:rundweg", k = "route", n = "Rundweg", s = {
        { a = { g1, g2, g3, g1, { "complete", q = 901101, o = 1 } } },
    } })
    W.onLog[901101] = true
    HAS_OBJECTIVES[901101] = true
    ns.cdb.route = "T:route:rundweg"
    W.pos = g1
    local atStart = R.Waypoint(R.Evaluate())
    W.pos = nil
    local leaving = R.Waypoint(R.Evaluate())
    W.pos = g2
    local atTwo = R.Waypoint(R.Evaluate())
    check("Rundweg: am Start zu Punkt 2, unterwegs weiter 2, dort zu Punkt 3", atStart == g2 and leaving == g2 and atTwo == g3,
        ("Start %s, unterwegs %s, an 2 %s"):format(atStart and atStart.x or "nil", leaving and leaving.x or "nil",
            atTwo and atTwo.x or "nil"))
    ns.cdb.route = nil
end

-- p) Regression 2026-11-17: Vorlauf zu einem übersprungenen Schritt verschwindet; der Pfeil führt zum
--    nächsten Schritt (vorher blieb der Zeiger auf dem Vorlauf und der Pfeil zeigte weiter dorthin)
ResetWorld(22)
do
    local gx = { "goto", m = 1440, x = 10, y = 10, w = true, ci = 1 }
    local gx2 = { "goto", m = 1440, x = 10, y = 10, w = true, ci = 1 }
    local gy = { "goto", m = 1440, x = 20, y = 20, w = true, ci = 1 }
    AddRoute({ id = "T:route:vorlauf", k = "route", n = "Vorlauf", s = {
        { a = { gx } },
        { a = { { "accept", q = 901201 }, gx2 } },
        { a = { { "accept", q = 901202 }, gy } },
    } })
    ns.cdb.route = "T:route:vorlauf"
    local v1 = R.Evaluate()
    R.Skip(2)
    R.Evaluate()
    local v2 = R.Evaluate()
    check("Vorlauf: nach Überspringen des Ziels zeigt der Pfeil zum nächsten Schritt",
        v1.main == 2 and v2.main == 3 and #v2.lead == 0 and R.Waypoint(v2) == gy,
        ("vorher %s, nachher %s, Vorlauf %d"):format(tostring(v1.main), tostring(v2.main), #v2.lead))
    ns.cdb.route = nil
end

-- q) Regression 2026-11-17: Ein offener Dauer-Schritt hebt den Zeigerschutz nicht auf. Quest abgebrochen ->
--    der Haupt-Schritt springt nicht zurück (vorher stand der Zeiger auf dem Dauer-Schritt)
ResetWorld(22)
do
    W.onLog[901300] = true
    HAS_OBJECTIVES[901300] = true
    AddRoute({ id = "T:route:schutz", k = "route", n = "Schutz", s = {
        { st = true, a = { { "complete", q = 901300, o = 1 } } },
        { a = { { "accept", q = 901301 } } },
        { a = { { "accept", q = 901302 } } },
        { a = { { "accept", q = 901303 } } },
    } })
    ns.cdb.route = "T:route:schutz"
    W.onLog[901301], W.onLog[901302] = true, true
    local before = R.Evaluate()
    R.Evaluate()
    W.onLog[901301] = nil -- abgebrochen
    local after = R.Evaluate()
    check("Zeigerschutz: Dauer-Schritt offen, abgebrochene Quest -> Haupt-Schritt bleibt", before.main == 4
        and after.main == 4 and #after.sticky == 1,
        ("vorher %s, nachher %s, Dauer %d"):format(tostring(before.main), tostring(after.main), #after.sticky))
    ns.cdb.route = nil
end

-- r) Regression 2026-11-17: Wer schon auf der Route einer anderen Klasse steht (vor der Kopfbedingung
--    möglich), bekommt beim nächsten Abgleich eine passende Route (vorher blieb er bis Stufe hi+1 darauf)
ResetWorld(22)
ns.cdb.route = "A:route:21-23 Ashenvale/Stonetalon" -- Jäger-Route, Spieler ist Paladin
local switched = R.AutoSelect(false)
check("Routenwahl: Jäger-Route eines Paladins wird ersetzt", switched ~= nil
    and switched ~= "A:route:21-23 Ashenvale/Stonetalon" and R.Allowed(R.Get(switched), S.Player()), tostring(switched))
ns.cdb.route = nil

-- s) Regression 2026-11-17: Mitgenommene Abgabe, die auch die neue Route enthält, deren Zeiger aber schon
--    dahinter steht: erscheint weiter (vorher wurde sie gelöscht und tauchte nirgends mehr auf)
ResetWorld(22)
ns.cdb.carry = {}
do
    AddRoute({ id = "T:route:mitA", k = "route", n = "MitA", s = {
        { a = { { "accept", q = 901401 } } }, { a = { { "turnin", q = 901401 } } },
    } })
    AddRoute({ id = "T:route:mitB", k = "route", n = "MitB", s = {
        { a = { { "turnin", q = 901401 } } }, { a = { { "accept", q = 901402 } } },
    } })
    HAS_OBJECTIVES[901401] = true
    W.onLog[901401] = true
    R.Load("T:route:mitA")
    R.Evaluate()
    ns.cdb.pointer["T:route:mitB"] = 2
    R.Load("T:route:mitB")
    local waitingInB = R.Evaluate().waiting
    W.all[901401] = true
    local v = R.Evaluate()
    local shown = false
    for _, ref in ipairs(R.Shown(v)) do if ref.route.id == "T:route:mitA" and ref.si == 2 then shown = true end end
    check("Mitnahme: neue Route hat die Abgabe schon hinter sich -> Abgabe erscheint trotzdem",
        waitingInB == 1 and shown, ("wartend %d, angezeigt %s"):format(waitingInB, tostring(shown)))
    ns.cdb.route, ns.cdb.carry = nil, {}
end

-- t) Simulation 2026-11-17: Schritt mit Annahme und Abgabe derselben Quest (annehmen, sofort abgeben) gilt
--    nicht als "Reihe nie begonnen" (vorher fiel er still weg, 151 Schritte bei der Allianz)
ResetWorld(22)
W.onLog[901500] = true
AddRoute({ id = "T:route:sofort", k = "route", n = "Sofort", s = {
    { a = { { "accept", q = 901500 } } },
    { a = { { "accept", q = 901501 }, { "turnin", q = 901501 } } },
} })
ns.cdb.route = "T:route:sofort"
tv = R.Evaluate()
check("Annehmen und sofort abgeben: Schritt bleibt Haupt-Schritt", tv.main == 2, "Schritt " .. tostring(tv.main))
ns.cdb.route = nil

-- u) Simulation 2026-11-17: Optionaler Schritt gilt nicht als verpasst, nur weil ein späterer Schritt scheinbar
--    erledigt ist (Ziel einer noch nicht angenommenen Quest)
ResetWorld(22)
W.onLog[901601] = true
AddRoute({ id = "T:route:optional", k = "route", n = "Optional", s = {
    { o = true, a = { { "turnin", q = 901601 } } },
    { a = { { "complete", q = 901602, o = 1 } } },
    { a = { { "accept", q = 901603 } } },
} })
ns.cdb.route = "T:route:optional"
tv = R.Evaluate()
check("Optional: späterer Schritt nur scheinbar erledigt -> optionale Abgabe bleibt", tv.main == 1,
    "Schritt " .. tostring(tv.main))
W.turned[901602], W.onLog[901603] = true, true
tv = R.Evaluate()
ns.cdb.pointer["T:route:optional"] = nil
tv = R.Evaluate()
check("Optional: späterer Schritt wirklich gemacht -> optionale Abgabe verpasst", tv.main ~= 1,
    "Schritt " .. tostring(tv.main))
ns.cdb.route = nil

-- v) Simulation 2026-11-17: Dungeon-Vorbereitung wartet nicht auf die Quest einer anderen Klasse (Bedingung an
--    der Annahme selbst, z. B. nur Priester; vorher wurde die Vorbereitung für den Paladin nie fertig)
ResetWorld(40)
AddRoute({ id = "T:dungeonquests:klasse", k = "dungeonquests", n = "Klasse", s = {
    { a = { { "accept", q = 901701, c = "Priest" }, { "accept", q = 901702 } } },
    { a = { { "complete", q = 901701, o = 1 }, { "complete", q = 901702, o = 1 } } },
} })
W.onLog[901702] = true
check("Vorbereitung: Quest nur für Priester hält den Paladin nicht auf",
    R.PrepDone(R.Get("T:dungeonquests:klasse"), S.Player()) == true)

-- w) Regression 2026-11-17: Rechtsklick auf eine andere Zeile beendet "Zurück" nicht
ResetWorld(22)
AddRoute({ id = "T:route:zurueck2", k = "route", n = "Zurueck2", s = {
    { a = { { "accept", q = 901801 } } }, { a = { { "accept", q = 901802 } } },
    { a = { { "accept", q = 901803 } } }, { a = { { "accept", q = 901804 } } },
} })
W.onLog[901801], W.onLog[901802] = true, true
ns.cdb.route = "T:route:zurueck2"
tv = R.Evaluate()
R.Back(tv)
R.Skip(4) -- andere Zeile
tv = R.Evaluate()
check("Zurück: Überspringen einer anderen Zeile lässt den Schritt stehen", tv.main == 2, "Schritt " .. tostring(tv.main))
ns.cdb.route = nil

-- x) 2026-11-17: Riverglades-Routen der Allianz binden ihre Schritte per #include aus eigenen Guides ein. Vorher
--    hatte "38-40 Riverglades" nur 3 Schritte; jetzt die eingebundenen Quests und die Route läuft durch.
do
    local rg = R.Get("A:route:38-40 Riverglades")
    local accepts = 0
    for _, s in ipairs(rg and rg.s or {}) do
        for _, a in ipairs(s.a) do if a[1] == "accept" then accepts = accepts + 1 end end
    end
    check("Riverglades: eingebundene Schritte vorhanden", rg ~= nil and #rg.s > 100 and accepts > 50,
        rg and (#rg.s .. " Schritte, " .. accepts .. " Annahmen") or "Route fehlt")
    ResetWorld(38)
    ns.cdb.route = "A:route:38-40 Riverglades"
    local mains, stuck = PlayRoute(4 * #rg.s)
    check("Riverglades: Route läuft im Testspiel bis zum Ende", stuck == nil and mains > 30,
        stuck or (mains .. " Haupt-Schritte"))
    ns.cdb.route = nil
end

-- i) Audit 2026-11-17: Der Fortschrittszeiger überspringt keine offenen Vorlauf-, Dauer- und "erledigt mit"-
--    Schritte vor dem Haupt-Schritt (vorher sprang er auf den Haupt-Schritt, und sie verschwanden nach der
--    ersten Auswertung).
ResetWorld(22)
W.onLog[900301] = true
AddRoute({ id = "T:route:zeiger", k = "route", n = "Zeiger", s = {
    { a = { { "accept", q = 900301 } } },
    { st = true, a = { { "complete", q = 900301, o = 1 } } },
    { cw = "next", a = { { "complete", q = 900301, o = 2 } } },
    { a = { { "accept", q = 900303 } } },
} })
ns.cdb.route = "T:route:zeiger"
local z1 = R.Evaluate()
local z2 = R.Evaluate()
check("Zeiger: Dauer- und Mit-Schritt bleiben nach der zweiten Auswertung", z1.main == 4 and z2.main == 4
    and #z2.sticky == 1 and #z2.with == 1, ("1.: %d/%d, 2.: %d/%d"):format(#z1.sticky, #z1.with, #z2.sticky, #z2.with))
ns.cdb.route = nil

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
