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
ns.cdb.route = nil
local best = R.FindRoute(S.Player())
check("Routenwahl Level 13 Mensch Paladin: 13-15 Westfall", best and best.n == "13-15 Westfall", best and best.n)

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
check("Darkshore: Ziel wird aus 14-16 Darkshore nachgeholt",
    v.catchup and v.catchup.route.id == "A:route:14-16 Darkshore" and v.catchup.si == 185,
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

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
