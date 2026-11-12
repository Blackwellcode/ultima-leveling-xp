-- Stub-Test der Oberflaeche mit echten Allianz-Daten: Laden, Routenwahl, Panel, Chips, Pfeil, Befehle.
-- Aufruf aus dem Projektordner: lua tools/test-ui.lua
-- Geschaetzte Breite eines Textes in Pixeln (fuer die Ueberlappungs-Pruefung aller Sprachen)
function TextWidthEstimate(text, size)
  if type(text) ~= "string" then return 0 end
  text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  local w = 0
  for _, cp in utf8.codes(text) do w = w + ((cp >= 0x1100) and 1.0 or 0.56) end
  return w * size
end
local function P(name) local o = { _n = name }
  return setmetatable(o, { __index = function(_, k)
    if k:match("^[%l_]") then return nil end
    if k == "SetScript" then return function(s, ev, fn) s["_" .. ev] = fn end end
    if k == "Show" then return function(s) s._shown = true end end
    if k == "Hide" then return function(s) s._shown = false end end
    if k == "IsShown" then return function(s) return s._shown == true end end
    if k == "SetShown" then return function(s, v) s._shown = v and true or false end end
    if k == "SetText" then return function(s, v) s._text = v end end
    if k == "SetHeight" then return function(s, v) s._h = v end end
    if k == "SetAlpha" then return function(s, v) s._alpha = v end end
    if k == "SetValue" then return function(s, v) s._value = v end end
    if k == "SetRotation" then return function(s, v) s._rot = v end end
    if k == "GetStringHeight" then return function() return 14 end end
    if k == "GetStringWidth" then return function() return 40 end end
    if k == "GetEffectiveScale" then return function() return 1 end end
    if k == "GetWidth" then return function() return 356 end end
    if k == "GetPoint" then return function() return "TOP", nil, "TOP", 0, 0 end end
    if k == "SetFont" then return function(s, path, size) s._font = path; s._size = size end end
    if k == "GetFont" then return function(s) return s._font, s._size or 12, "" end end
    if k == "SetWidth" then return function(s, v) s._width = v end end
    if k == "SetWordWrap" then return function(s, v) s._wrap = v end end
    if k == "GetText" then return function(s) return s._text end end
    -- Textbreite geschaetzt: Latein/Kyrillisch 0,56 em je Zeichen, Hangul/CJK 1 em; Farb- und Bildcodes zaehlen nicht
    if k == "GetUnboundedStringWidth" then return function(s) return TextWidthEstimate(s._text, s._size or 12) end end
    if k == "CreateFontString" or k == "CreateTexture" or k == "CreateAnimationGroup" or k == "CreateAnimation" then
      return function() return P(k) end end
    return function() end end }) end
local created = {}
CreateFrame = function(_, name) local f = P(name); f._shown = true; created[#created + 1] = f; if name then _G[name] = f end; return f end
GetPhysicalScreenSize = function() return 3440, 1440 end
UIParent = P("UIParent"); GameTooltip = P("GT"); GameTooltip_Hide = function() end
STANDARD_TEXT_FONT = "f"; SlashCmdList = {}
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end, NewTicker = function() end }
local function Run() local n = 0 while #timers > 0 and n < 100 do n = n + 1; table.remove(timers, 1)() end end
local out = {}; print = function(s) out[#out + 1] = tostring(s) end
UnitRace = function() return "Human", "Human" end; UnitClass = function() return "Paladin", "PALADIN" end
UnitFactionGroup = function() return "Alliance" end; UnitLevel = function() return 14 end; UnitSex = function() return 2 end
GetLocale = function() return "enUS" end; UnitXP = function() return 620 end; UnitXPMax = function() return 1000 end
GetXPExhaustion = function() return 300 end; GetMaxPlayerLevel = function() return 60 end
C_QuestLog = { IsOnQuest = function() return false end, IsQuestFlaggedCompleted = function() return false end,
  IsComplete = function() return false end, GetQuestObjectives = function() return nil end,
  GetTitleForQuestID = function(q) return "Quest " .. q end, GetNumQuestLogEntries = function() return 0 end }
C_Item = { GetItemCount = function() return 0 end, GetItemNameByID = function(i) return "Item " .. i end }
IsSpellKnown = function() return false end; C_Spell = { GetSpellName = function(s) return "Spell " .. s end }
GetRealZoneText = function() return "Westfall" end; GetSubZoneText = function() return "" end
C_Map = { GetAreaInfo = function() return nil end, GetMapInfo = function(m) return { name = "Map " .. m } end,
  GetBestMapForUnit = function() return 1436 end }
GetBindLocation = function() return "Goldshire" end
GetUnitSpeed = function() return 7 end; GetPlayerFacing = function() return 0 end
C_UnitAuras = { GetAuraDataBySpellName = function() return nil end }
IsResting = function() return false end; IsInGroup = function() return false end; IsInInstance = function() return false, "none" end
GetTime = function() return 0 end; UIErrorsFrame = { AddMessage = function() end }
C_Container = { GetContainerNumSlots = function() return 0 end, GetContainerItemInfo = function() return nil end }
InCombatLockdown = function() return false end; debugprofilestop = function() return 0 end
C_NamePlate = { GetNamePlates = function() return {} end, GetNamePlateForUnit = function() end }
C_AddOns = { IsAddOnLoaded = function() return false end,
  LoadAddOn = function(name)
    if name ~= "UltimaLevelingXP_A" then return false, "MISSING" end
    for _, f in ipairs({ "data/Routes_A.lua", "data/Routes_B.lua" }) do assert(loadfile(f))() end
    return true
  end }
local KALIMDOR = { [1411] = true, [1413] = true, [1438] = true, [1439] = true, [1445] = true, [1446] = true }
local playerPos = { 0, 0, 0 }
local HBD = { GetPlayerWorldPosition = function() return playerPos[1], playerPos[2], playerPos[3] end,
  GetWorldVector = function() return 1.0, 350 end,
  GetWorldDistance = function(_, _, ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end,
  -- Grobe Geografie: Zonenpunkte liegen nahe ihrer echten Weltlage (Stormwind, Wetlands, Darkshore)
  GetWorldCoordinatesFromZone = function(_, x, y, m)
    local base = ({ [1453] = { 1300, -8600 }, [1437] = { -600, -3800 }, [1439] = { 850, 6450 } })[m] or { m * 10, m * 10 }
    return base[1] + x * 100, base[2] + y * 100, KALIMDOR[m] and 1 or 0
  end }
local icons = {}
LibStub = function(name)
  if name == "HereBeDragons-2.0" then return HBD end
  if name == "LibDataBroker-1.1" then return { NewDataObject = function(_, n, o) icons.obj = o; return o end } end
  if name == "LibDBIcon-1.0" then return { Register = function(_, n) icons.name = n end, Show = function() icons.hidden = false end, Hide = function() icons.hidden = true end } end
end

assert(loadfile("data/Travel.lua"))()
assert(loadfile("data/Flights.lua"))()
local ns = {}
for _, f in ipairs({ "Core.lua", "Locale/Locale.lua", "Locale/enUS.lua", "Locale/deDE.lua", "Locale/frFR.lua", "Theme.lua", "Kit.lua", "Settings.lua", "Engine/Conditions.lua", "Engine/State.lua", "Engine/Progress.lua",
    "Engine/Text.lua", "Engine/Runner.lua", "Engine/Travel.lua", "Engine/Paths.lua", "Engine/Talents.lua", "Data/Extra.lua", "Live.lua",
    "Auto.lua", "UI/Bonus.lua", "UI/Panel.lua", "UI/Item.lua", "Assist.lua", "UI/Nav.lua", "UI/Arrow.lua",
    "UI/Minimap.lua", "UI/Plates.lua", "UI/Talents.lua", "UI/Options.lua", "UI/Welcome.lua", "Slash.lua" }) do
  assert(loadfile("src/" .. f))("UltimaLevelingXP", ns)
end
assert(loadfile("data/Talents.lua"))("UltimaLevelingXP", ns)
local function fire(event, ...) for _, f in ipairs(created) do if f._OnEvent then f._OnEvent(f, event, ...) end end end

local fails = 0
local function check(label, ok, detail)
  if not ok then fails = fails + 1 end
  io.write(("%-58s %s%s\n"):format(label, ok and "OK" or "FEHLER", detail and ("  " .. detail) or ""))
end

-- Oberflächen-Sprache Deutsch (Client englisch): die Prüfungen erwarten deutsche Texte
UltimaAccountDB = { lang = "deDE", langChosen = true }
fire("ADDON_LOADED", "UltimaLevelingXP")
check("Gespeicherte Daten angelegt", UltimaAccountDB and UltimaCharDB and ns.db.questPlates.dangerDiff == 5)
check("Panel, Pfeil und Minimap gebaut", UltimaPanel ~= nil and UltimaArrow ~= nil and icons.name == "UltimaLevelingXP")
fire("PLAYER_ENTERING_WORLD", true, false); Run()
check("Allianz-Routen nachgeladen", ns.routes and #ns.routes > 200, ns.routes and (#ns.routes .. " Routen"))
check("Globale Uebergabe wieder geleert", UltimaRouteData == nil)
check("Route automatisch gewaehlt: 13-15 Westfall", ns.cdb.route == "A:route:13-15 Westfall", tostring(ns.cdb.route))
ns.Update()
local p = UltimaPanel
check("Kopf: Routenname", p.title._text == "13-15 Westfall", tostring(p.title._text))
check("Kopf: Schrittanzeige", type(p.sub._text) == "string" and p.sub._text:find("Schritt") ~= nil, tostring(p.sub._text))
check("XP-Zeile mit fehlenden XP", p.xpLeft._text and p.xpLeft._text:find("noch 380 XP") ~= nil, tostring(p.xpLeft._text))
check("Erholt 30 %", p.xpRight._text == "Erholt 30 %")
check("Hero-Karte JETZT sichtbar", p.hero._shown)
local shownRows = 0
for _, f in ipairs(created) do if f._n == nil and f.icon and f.text and f._shown then shownRows = shownRows + 1 end end
check("Handlungszeilen gezeichnet", shownRows > 0, shownRows .. " Zeilen")
check("Bonus-Chips im Panel (kein eigenes Fenster)", _G.UltimaWatcher == nil)
check("Pfeil hat Wegpunkt und dreht", (function()
  UltimaArrow._OnUpdate(UltimaArrow, 1)
  -- seit dem Hausstil: Entfernung als Zahl, Laufzeit in eigener Zeile darunter
  return UltimaArrow.tex._rot == 1.0 and UltimaArrow.dist._text == "320 m" and UltimaArrow.time._text == "0:50"
end)(), tostring(UltimaArrow.dist._text) .. " / " .. tostring(UltimaArrow.time and UltimaArrow.time._text))
local before = ns.view.main
SlashCmdList.ULTIMALEVELING("status")
check("/ultima status nennt Route", out[#out]:find("13%-15 Westfall") ~= nil or out[#out - 1]:find("13%-15 Westfall") ~= nil)
ns.Runner.Skip(before); ns.Update()
check("Ueberspringen geht zum naechsten Schritt", ns.view.main and ns.view.main > before, before .. " -> " .. tostring(ns.view.main))
ns.Runner.Back(ns.view); ns.Update()
check("Zurueck kehrt um", ns.view.main and ns.view.main < (before + 50))
-- Boni-Kacheln: Schlafsack fehlt, Level 14 -> Aktion "Questreihe" startet die Zusatz-Route
local tiles = ns.Bonus.Tiles()
check("Vier Boni-Kacheln", #tiles == 4, #tiles .. " Kacheln")
check("Schlafsack-Kachel bietet die Questreihe an", tiles[3].action and tiles[3].action.type == "route"
    and tiles[3].actionText == "Questreihe", tiles[3].actionText)
check("Kacheln sind geschützte Knöpfe mit fester Position", UltimaBonusTile3 ~= nil)
local before2 = ns.cdb.route
UltimaBonusTile3.routeAction = true
UltimaBonusTile3._PostClick(UltimaBonusTile3)
check("Klick startet Schlafsack-Route", ns.cdb.route == "A:extra:Schlafsack-Questreihe", tostring(ns.cdb.route))
check("Eigene Route wird gemerkt", ns.cdb.returnRoute == before2, tostring(ns.cdb.returnRoute))
ns.Runner.Load(before2)

-- Umlaute in sichtbaren Texten
check("Umlaute: Knopf-Hinweis 'überspringen'", (function()
  for _, f in ipairs({ "src/Locale/deDE.lua" }) do -- deutsche Texte liegen seit der Mehrsprachigkeit hier
    local h = io.open(f, "rb"); local s = h:read("a"); h:close()
    return s:find("Schritt überspringen", 1, true) ~= nil and s:find("ueberspringen", 1, true) == nil
  end
end)())

-- Wegnetz: synchron aus den echten Allianz-Routen bauen und einen Weg in Westfall suchen
ns.Paths.Build(true)
check("Wegnetz aufgebaut", ns.Paths.IsReady() and ns.Paths.stats.nodes > 1000,
  ns.Paths.stats.nodes .. " Knoten, " .. ns.Paths.stats.edges .. " Kanten")
local west = ns.Runner.Get("A:route:13-15 Westfall")
local pts = {}
for _, s in ipairs(west.s) do for _, a in ipairs(s.a) do if a[1] == "goto" and a.w then pts[#pts + 1] = a end end end
local first, last = pts[1], pts[#pts]
local path, length = ns.Paths.Find(first.ci, first.x, first.y, last.x, last.y)
local direct = math.sqrt((first.x - last.x) ^ 2 + (first.y - last.y) ^ 2)
check("Weg durch Westfall über Zwischenpunkte", path and #path > 2, path and (#path .. " Punkte"))
check("Weg nicht absurd länger als Luftlinie", path and length <= 3 * direct + 300,
  path and ("%.0f statt %.0f Yards"):format(length, direct))

fire("PLAYER_REGEN_DISABLED")
check("Kampf dimmt Panel", p._alpha == 0.6)

-- Reise: Spieler in Stormwind (Kontinent 0), Ziel in Darkshore (Kontinent 1)
playerPos[1], playerPos[2], playerPos[3] = 1300, -8600, 0
local plan = ns.Travel.Plan({ "goto", m = 1439, x = 900, y = 6500, w = true, ci = 1 })
check("Reise geplant: 3 Etappen", plan and #plan == 3, plan and (#plan .. " Etappen"))
check("Etappe 1: Hafen Stormwind, Schiff nach Darkshore", plan and plan[1].kind == "goto" and plan[1].point.m == 1453
    and plan[1].text:find("Schiff nach") ~= nil, plan and plan[1].text)
check("Etappe 2: Ueberfahrt", plan and plan[2].kind == "ride")
check("Pfeil-Ziel ist der Hafen", plan and ns.Travel.ArrowTarget(plan) == plan[1].point)
playerPos[1], playerPos[2], playerPos[3] = -600, -3800, 0
local plan2 = ns.Travel.Plan({ "goto", m = 1439, x = 900, y = 6500, w = true, ci = 1 })
check("Spieler in Wetlands: Hafen Menethil statt Stormwind", plan2 and plan2[1].point.m == 1437,
    plan2 and ("Karte " .. plan2[1].point.m))
playerPos[1], playerPos[2], playerPos[3] = 900, 6400, 1
check("Auf dem Zielkontinent keine Reise mehr", ns.Travel.Plan({ "goto", m = 1439, x = 900, y = 6500, w = true, ci = 1 }) == nil)

-- Hänger aus dem Spiel: 16-19 Darkshore, am Questgeber Thundris, "The Cliffspring River" im Log, Ziel offen
fire("PLAYER_REGEN_ENABLED")
local riverDone = false
C_QuestLog.IsOnQuest = function(q) return q == 4762 or q == 4740 end
C_QuestLog.GetQuestObjectives = function(q)
  if q == 4762 then return { { finished = riverDone, text = "Cliffspring River Sample", numFulfilled = 0, numRequired = 1 } } end
end
ns.cdb.route, ns.cdb.pointer, ns.cdb.open = "A:route:16-19 Darkshore", {}, {}
playerPos[1], playerPos[2], playerPos[3] = 492.36, 6581.08, 1
ns.Update()
local catchHint = false
for _, f in ipairs(created) do
  if f.hint and f._shown and type(f.hint._text) == "string" and f.hint._text:find("Nachholen aus 14%-16 Darkshore") then
    catchHint = true
  end
end
check("Darkshore: Nachhol-Schritt im Panel", ns.view.catchup ~= nil and catchHint)
UltimaArrow._OnUpdate(UltimaArrow, 1)
check("Darkshore: Pfeil führt zum Fluss", UltimaArrow.tex._shown and not UltimaArrow.check._shown,
  tostring(UltimaArrow.dist._text))
riverDone = true
ns.Update()
UltimaArrow._OnUpdate(UltimaArrow, 1)
check("Darkshore: Probe da, am Questgeber: Häkchen \"Am Ziel\"", ns.view.catchup == nil and ns.view.main == 4
  and UltimaArrow.check._shown and UltimaArrow.dist._text == "Am Ziel", tostring(UltimaArrow.dist._text))
-- Englische und franzoesische Oberflaeche: dieselben Elemente in der anderen Sprache
ns.db.lang = "enUS"; ns.ApplyLanguage(); ns.Update()
check("Englisch: Kopfzeile", type(p.sub._text) == "string" and p.sub._text:find("^Step %d+ of %d+") ~= nil, tostring(p.sub._text))
check("Englisch: Erholt-Anzeige", p.xpRight._text == "Rested 30 %", tostring(p.xpRight._text))
check("Englisch: Handlungstext", ns.Text.Action({ "accept", q = 1 }):find("^Accept: ") ~= nil)
ns.db.lang = "frFR"; ns.ApplyLanguage(); ns.Update()
check("Franzoesisch: Kopfzeile", type(p.sub._text) == "string" and p.sub._text:find("^Étape") ~= nil, tostring(p.sub._text))
ns.db.lang = "deDE"; ns.ApplyLanguage()
-- /ultima debug: läuft durch und meldet; Fehler im Befehl erscheinen als Chatzeile statt das Senden zu blockieren
local outBefore = #out
local okDebug = pcall(SlashCmdList.ULTIMALEVELING, "debug")
local debugText = table.concat(out, " | ", outBefore + 1)
check("/ultima debug läuft ohne Abbruch", okDebug and debugText:find("lang: deDE") ~= nil and debugText:find("title: shown=") ~= nil,
  debugText:sub(-260))
local realPaths = ns.Paths
ns.Paths = nil
outBefore = #out
local okBroken = pcall(SlashCmdList.ULTIMALEVELING, "debug")
ns.Paths = realPaths
check("Fehler in /ultima debug wird gemeldet, nicht geworfen", okBroken and table.concat(out, " | ", outBefore + 1):find("paths: Fehler") ~= nil)
local fontWarn = false
for _, line in ipairs(out) do if line:find("nicht ladbar", 1, true) then fontWarn = true end end
check("Keine falsche Schrift-Warnung, wenn die Schrift sitzt", not fontWarn)
-- Keine Ueberlappung in allen Sprachen: jedes Textfeld mit Nachbarn hat eine feste Breite und passt hinein
-- (verkleinert bis zur Mindestgroesse; darueber hinaus kuerzt WoW mit "..."). Breiten sind geschaetzt, siehe oben.
local FULL = 384 - 2 * 16
for _, code in ipairs(ns.LANGUAGES) do
  ns.db.lang = code; ns.ApplyLanguage(); ns.Update()
  local fields = { { "Titel", p.title }, { "Unterzeile", p.sub }, { "XP links", p.xpLeft }, { "XP rechts", p.xpRight } }
  for i = 1, 4 do
    local t = _G["UltimaBonusTile" .. i]
    fields[#fields + 1] = { "Kachel " .. i .. " Titel", t.title }
    fields[#fields + 1] = { "Kachel " .. i .. " Status", t.status }
  end
  local bad, shrunk, cut = {}, {}, {}
  for _, f in ipairs(fields) do
    local name, fs = f[1], f[2]
    local text = fs._text or ""
    if text ~= "" then
      local w = TextWidthEstimate(text, fs._size or 12)
      if not fs._width then
        bad[#bad + 1] = name .. " ohne Breite"
      elseif w > fs._width + 0.5 then
        cut[#cut + 1] = name .. " '" .. text .. "'"
      end
      if fs.fitBase and fs._size and fs._size < fs.fitBase then shrunk[#shrunk + 1] = name end
    end
  end
  -- XP-Zeile: links + rechts + Abstand innerhalb der Gesamtbreite
  local leftW = TextWidthEstimate(p.xpLeft._text, p.xpLeft._size or 11)
  local rightW = TextWidthEstimate(p.xpRight._text, p.xpRight._size or 11)
  if (p.xpRight._text or "") ~= "" and leftW + rightW + 10 > FULL + 0.5 then bad[#bad + 1] = "XP-Zeile ueberlappt" end
  -- Kachel-Titel sollen lesbar bleiben: nicht gekuerzt
  local titleCut = {}
  for _, c in ipairs(cut) do if c:find("Titel") then titleCut[#titleCut + 1] = c end end
  check(code .. ": keine Ueberlappung", #bad == 0 and #titleCut == 0,
    (#bad > 0 and table.concat(bad, ", ") or "") .. (#titleCut > 0 and table.concat(titleCut, ", ") or "")
      .. ("  verkleinert %d, gekuerzt %d%s"):format(#shrunk, #cut, #cut > 0 and (": " .. table.concat(cut, ", ")) or ""))
end
ns.db.lang = "deDE"; ns.ApplyLanguage(); ns.Update()
-- Buffs per Zauber-ID: Schlafsack 429959, Camp 1229741, ohne englischen Namen
C_UnitAuras.GetPlayerAuraBySpellID = function(id)
  if id == 429959 then return { spellId = id, applications = 3, expirationTime = 0 } end
  if id == 1229741 then return { spellId = id, expirationTime = 0 } end
end
local tilesById = ns.Bonus.Tiles()
check("Schlafsack-Buff per ID 429959 erkannt (3/3)", tilesById[3].state == "ok" and tilesById[3].status == "3/3",
  tostring(tilesById[3].status))
check("Camp-Buff per ID 1229741 erkannt", tilesById[4].state == "ok", tostring(tilesById[4].state))
C_UnitAuras.GetPlayerAuraBySpellID = nil
-- Kampf: der Client liefert die Geschwindigkeit als geschuetzten Wert (secret value). Vergleiche damit
-- werfen im Spiel einen Fehler; Pfeil und Panel muessen ohne ihn auskommen (BugSack 2026-11-09, 469x).
local SECRET = setmetatable({}, { __lt = function() error("attempt to compare (a secret number value)") end,
  __le = function() error("attempt to compare (a secret number value)") end })
issecretvalue = function(v) return v == SECRET end
issecrettable = issecretvalue -- der Mock-Wert ist eine Lua-Tabelle; im Spiel ist er eine geschuetzte Zahl
local realSpeed = GetUnitSpeed
GetUnitSpeed = function() return SECRET end
local outBefore2 = #out
ns.Update()
UltimaArrow._OnUpdate(UltimaArrow, 1)
local guardLines = 0
for i = outBefore2 + 1, #out do if out[i]:find("Panel:") or out[i]:find("Arrow:") then guardLines = guardLines + 1 end end
local okSpeed, speedValue = pcall(ns.RunSpeed)
check("Kampf (geschuetzte Geschwindigkeit): Panel und Pfeil ohne Fehler", guardLines == 0 and p.hero._shown
  and okSpeed and type(speedValue) == "number" and speedValue >= 1, tostring(speedValue) .. " yd/s, Pfeil: " .. tostring(UltimaArrow.dist._text))
GetUnitSpeed, issecretvalue, issecrettable = realSpeed, nil, nil
-- Ein Fehler in der Bild-Schleife erscheint genau einmal als Chatzeile, die Schleife laeuft weiter
local guardOut = #out
for _ = 1, 5 do ns.Guard("Test", function() error("Testfehler") end) end
local guardCount = 0
for i = guardOut + 1, #out do if out[i]:find("Testfehler") then guardCount = guardCount + 1 end end
check("Fehler in Bild-Schleife: genau eine Meldung statt Flut", guardCount == 1, guardCount .. " Meldungen")
-- Quest-Automatik: nimmt nur Quests des angezeigten Schritts an und gibt sie ab
ns.cdb.route, ns.cdb.pointer, ns.cdb.open = "A:route:16-19 Darkshore", {}, {}
C_QuestLog.IsOnQuest = function(q) return q == 4762 or q == 4740 end
C_QuestLog.GetQuestObjectives = function() return nil end -- 4762 abgebbar
ns.Update()
local did = {}
IsShiftKeyDown = function() return false end
C_GossipInfo = {
  GetActiveQuests = function() return { { questID = 4762, isComplete = true }, { questID = 1, isComplete = true } } end,
  GetAvailableQuests = function() return { { questID = 4763 }, { questID = 2 } } end,
  SelectActiveQuest = function(q) did[#did + 1] = "abgeben " .. q end,
  SelectAvailableQuest = function(q) did[#did + 1] = "annehmen " .. q end,
}
local questId = 4763
GetQuestID = function() return questId end
AcceptQuest = function() did[#did + 1] = "AcceptQuest " .. questId end
IsQuestCompletable = function() return true end
CompleteQuest = function() did[#did + 1] = "CompleteQuest " .. questId end
local choices = 0
GetNumQuestChoices = function() return choices end
GetQuestReward = function() did[#did + 1] = "GetQuestReward " .. questId end
fire("GOSSIP_SHOW")
check("Automatik: Gespräch wählt die Abgabe der Routen-Quest", did[1] == "abgeben 4762" and #did == 1, table.concat(did, ", "))
did = {}; fire("QUEST_DETAIL")
check("Automatik: Routen-Quest wird angenommen", did[1] == "AcceptQuest 4763", table.concat(did, ", "))
did = {}; questId = 2; fire("QUEST_DETAIL")
check("Automatik: fremde Quest bleibt unberührt", #did == 0, table.concat(did, ", "))
did = {}; questId = 4762; fire("QUEST_PROGRESS"); fire("QUEST_COMPLETE")
check("Automatik: Abgabe ohne Auswahl läuft durch", did[1] == "CompleteQuest 4762" and did[2] == "GetQuestReward 4762", table.concat(did, ", "))
did = {}; choices = 3; fire("QUEST_COMPLETE")
check("Automatik: Belohnung mit Auswahl wählt Ultima nicht", #did == 0, table.concat(did, ", "))
did = {}; choices = 0; IsShiftKeyDown = function() return true end; fire("QUEST_DETAIL")
check("Automatik: Umschalt setzt aus", #did == 0)
IsShiftKeyDown = function() return false end
did = {}; ns.db.autoQuest = false; fire("QUEST_COMPLETE")
check("Automatik: abschaltbar", #did == 0)
ns.db.autoQuest = true

-- Item-Knopf: Schritt 5 verlangt "Empty Cleansing Bowl" (12346) zu benutzen
C_QuestLog.IsOnQuest = function(q) return q == 4763 or q == 4740 end
C_QuestLog.IsQuestFlaggedCompleted = function(q) return q == 4762 end
C_Item.GetItemCount = function(i) return i == 12346 and 1 or 0 end
local attrs = {}
UltimaItemButton.SetAttribute = function(_, k, val) attrs[k] = val end
ns.Update()
check("Item-Knopf zeigt das Quest-Item des Schritts", ns.view.main == 5 and attrs.item == "item:12346" and UltimaItemButton._shown == true,
  "Schritt " .. tostring(ns.view.main) .. ", " .. tostring(attrs.item))
InCombatLockdown = function() return true end
C_Item.GetItemCount = function() return 0 end
ns.Update()
check("Item-Knopf bleibt im Kampf unverändert", attrs.item == "item:12346" and UltimaItemButton._shown == true)
InCombatLockdown = function() return false end
fire("PLAYER_REGEN_ENABLED")
check("Item-Knopf verschwindet nach dem Kampf, wenn das Item weg ist", attrs.item == nil and UltimaItemButton._shown == false)
C_Item.GetItemCount = function() return 0 end
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
-- Das Fenster traegt geschuetzte Kacheln: Groesse und Lage des Fensters selbst duerfen sich beim Zeichnen
-- nie aendern (im Kampf: ADDON_ACTION_BLOCKED UltimaPanel:SetHeight, BugGrabber 2026-11-10). Nur die Huelle waechst.
local blocked = {}
for _, m in ipairs({ "SetHeight", "SetWidth", "SetSize", "SetPoint", "ClearAllPoints", "Show", "Hide", "SetShown", "SetScale" }) do
  UltimaPanel[m] = function() blocked[#blocked + 1] = m end
end
ns.cdb.pointer = {}
ns.Update()
check("Zeichnen ruft keine geschuetzte Fenster-Methode auf", #blocked == 0, table.concat(blocked, ", "))
check("Huelle waechst mit dem Inhalt", UltimaPanel.body and (UltimaPanel.body._h or 0) > 190, tostring(UltimaPanel.body and UltimaPanel.body._h))
-- Am Ziel, NPC fehlt (Eskorte Therylune, 2026-11-10): Hinweis statt ratlosem "Am Ziel"
for _, m in ipairs({ "SetHeight", "SetWidth", "SetSize", "SetPoint", "ClearAllPoints", "Show", "Hide", "SetShown", "SetScale" }) do UltimaPanel[m] = nil end
C_QuestLog.IsOnQuest = function(q) return q == 4762 or q == 4740 end
C_QuestLog.GetQuestObjectives = function() return nil end
ns.cdb.route, ns.cdb.pointer, ns.cdb.open = "A:route:16-19 Darkshore", {}, {}
playerPos[1], playerPos[2], playerPos[3] = 492.36, 6581.08, 1
ns.db.lang = "deDE"; ns.db.langChosen = true; ns.ApplyLanguage(); ns.Update()
check("Am Ziel ohne NPC: Hinweis im Panel", ns.view.main == 4 and type(p.tip._text) == "string" and p.tip._text:find("Niemand da", 1, true) ~= nil,
  tostring(p.tip._text):sub(-90))
-- Schriften neu setzen: jedes Feld behaelt Text und bekommt wieder eine Schrift
p.title._font = nil
ns.EnsureFonts()
check("EnsureFonts setzt fehlende Schrift neu", p.title._font ~= nil and p.title._text ~= nil and p.title._text ~= "")
-- Ziel-Knopf: visiert den NPC des Schritts an (Schritt 4: Thundris Windweaver)
local tAttrs = {}
UltimaTargetButton.SetAttribute = function(_, k, val) tAttrs[k] = val end
ns.cdb.pointer = {}; ns.Update()
-- (das Makro wurde schon beim ersten Zeichnen gesetzt; geprueft wird der Zustand des Knopfs)
check("Ziel-Knopf: zeigt den Schritt-NPC an", UltimaTargetButton._shown == true and UltimaTargetButton.names
  and UltimaTargetButton.names[1] == "Thundris Windweaver", tostring(UltimaTargetButton.names and UltimaTargetButton.names[1]))
-- Lehrer: kauft nur den Zauber, den ein offener train-Schritt verlangt
local bought = {}
GetNumTrainerServices = function() return 3 end
GetTrainerServiceInfo = function(i) return ({ "Spell 111", "Spell 222", "Spell 333" })[i], nil, i == 3 and "unavailable" or "available" end
BuyTrainerService = function(i) bought[#bought + 1] = i end
local realShown = ns.Runner.Shown
ns.Runner.Shown = function() return { { route = { id = "t", s = { { a = { { "train", sp = 222 }, { "train", sp = 333 } } } } }, si = 1, kind = "main" } } end
fire("TRAINER_SHOW")
check("Lehrer: nur der verlangte, verfügbare Zauber wird gekauft", #bought == 1 and bought[1] == 2, table.concat(bought, ","))
-- Flugmeister: bekannte Punkte merken, Ziel des fly-Schritts wählen
ns.Runner.Shown = function() return { { route = { id = "t", s = { { a = { { "fly", to = "Astranaar" } } } } }, si = 1, kind = "main" } } end
local took
NumTaxiNodes = function() return 3 end
TaxiNodeName = function(i) return ({ "Auberdine, Darkshore", "Astranaar, Ashenvale", "Theramore, Dustwallow Marsh" })[i] end
TaxiNodeGetType = function(i) return ({ "CURRENT", "REACHABLE", "DISTANT" })[i] end
TakeTaxiNode = function(i) took = i end
fire("TAXIMAP_OPENED")
check("Flug: Ziel des Schritts wird gewählt", took == 2, tostring(took))
check("Flug: bekannte Flugpunkte gemerkt, unbekannte nicht", ns.KnowsTaxi("Auberdine") and ns.KnowsTaxi("Astranaar") and not ns.KnowsTaxi("Theramore"))
check("fp-Schritt für bekannten Flugpunkt gilt als erledigt", ns.Progress.Done({ "fp", to = "Auberdine" }, { routeId = "t", si = 1, ai = 1 }) == true
  and ns.Progress.Done({ "fp", to = "Theramore" }, { routeId = "t", si = 1, ai = 1 }) == false)
ns.Runner.Shown = realShown
-- Reiseplaner auf einem Kontinent: Spieler in Auberdine, Ziel bei Astranaar (echte Flugdaten)
local goal = { "goto", m = 1440, x = -300, y = 2800, w = true, ci = 1 }
playerPos[1], playerPos[2], playerPos[3] = 560, 6340, 1
C_Item.GetItemCount = function() return 0 end
ns.cdb.taxi = {}
check("Reise: ohne bekannte Flugpunkte kein Flugvorschlag", ns.Travel.Plan(goal) == nil)
ns.cdb.taxi = { ["Auberdine, Darkshore"] = true, ["Astranaar, Ashenvale"] = true }
local fp = ns.Travel.Plan(goal)
check("Reise: Flug Auberdine -> Astranaar wird vorgeschlagen", fp and #fp == 3 and fp[1].kind == "goto"
  and fp[1].text:find("Auberdine", 1, true) and fp[2].kind == "ride" and fp[2].text:find("Astranaar", 1, true)
  and ns.Travel.flyTarget == "Astranaar, Ashenvale", fp and (fp[1].text .. " | " .. fp[2].text .. " | " .. tostring(fp[3].sub)) or "kein Plan")
check("Reise: am Flugmeister ist die erste Etappe erledigt", fp and fp[1].done == true)
playerPos[1], playerPos[2] = -280, 2830
check("Reise: am Ziel-Flugpunkt kein Vorschlag mehr", ns.Travel.Plan(goal) == nil and ns.Travel.flyTarget == nil)
-- kurzer Weg: laufen
playerPos[1], playerPos[2] = 560, 6340
check("Reise: kurzer Weg ohne Flug", ns.Travel.Plan({ "goto", m = 1439, x = 500, y = 6000, w = true, ci = 1 }) == nil)
-- Ruhestein: gebunden in Astranaar, bereit, Spieler weit weg ohne Flugpunkt in der Naehe
ns.cdb.taxi = { ["Astranaar, Ashenvale"] = true }
playerPos[1], playerPos[2] = 2000, 7000
C_Item.GetItemCount = function(i) return i == 6948 and 1 or 0 end
GetBindLocation = function() return "Astranaar" end
C_Container.GetItemCooldown = function() return 0, 0 end
local hp = ns.Travel.Plan(goal)
check("Reise: Ruhestein nach Astranaar wird vorgeschlagen", hp and hp[1].kind == "ride" and hp[1].icon == "home", hp and hp[1].text or "kein Plan")
C_Container.GetItemCooldown = function() return 100, 3600 end
local hp2 = ns.Travel.Plan(goal)
check("Reise: Ruhestein auf Abklingzeit wird nicht vorgeschlagen", not (hp2 and hp2[1].icon == "home"))
GetBindLocation = function() return "Goldshire" end
C_Item.GetItemCount = function() return 0 end
ns.cdb.taxi = {}
-- Gefahr: Gegner 3+ Level ueber dem Spieler (Darkshore-Murlocs 19/20 bei Level 16, 2026-11-10)
local myLevel = UnitLevel("player")
local plateLevels = { e1 = myLevel + 4, e2 = myLevel + 3, e3 = myLevel + 1 }
C_NamePlate.GetNamePlates = function() return { { namePlateUnitToken = "e1" }, { namePlateUnitToken = "e2" }, { namePlateUnitToken = "e3" } } end
local realExists, realLevel = UnitExists, UnitLevel
UnitExists = function(u) return plateLevels[u] ~= nil or (realExists and realExists(u)) end
UnitLevel = function(u) return plateLevels[u] or realLevel(u) end
UnitCanAttack = function() return true end
UnitIsDead = function() return false end
local _, dangerAlerts = ns.Bonus.Tiles()
local danger
for _, a in ipairs(dangerAlerts) do if a.state == "bad" and a.text:find(tostring(myLevel + 4), 1, true) then danger = a end end
check("Gefahr: Warnung bei Gegnern 3+ Level drueber", danger ~= nil and danger.tip:find("2 ", 1, true) ~= nil, danger and danger.text or "keine Warnung")
plateLevels = { e3 = myLevel + 1 }
C_NamePlate.GetNamePlates = function() return { { namePlateUnitToken = "e3" } } end
_, dangerAlerts = ns.Bonus.Tiles()
local still = false
for _, a in ipairs(dangerAlerts) do if a.text:find("Gefahr", 1, true) or a.text:find("Danger", 1, true) then still = true end end
check("Gefahr: keine Warnung bei Gegnern auf deinem Level", not still)
C_NamePlate.GetNamePlates = function() return {} end
UnitExists, UnitLevel = realExists, realLevel
-- Stockwerk (Wizbang Cranktoggle im Gasthaus Auberdine, 2026-11-10): am Ziel, aber ein Stockwerk tiefer
C_QuestLog.IsOnQuest = function() return false end
C_QuestLog.IsQuestFlaggedCompleted = function(q) return q == 3524 or q == 963 end
ns.cdb.route, ns.cdb.pointer, ns.cdb.open = "A:route:14-16 Darkshore", { ["A:route:14-16 Darkshore"] = 7 }, {}
playerPos[1], playerPos[2], playerPos[3] = 519.74, 6406.1, 1
ns.db.lang = "deDE"; ns.ApplyLanguage(); ns.Update()
UltimaArrow._OnUpdate(UltimaArrow, 1)
check("Stockwerk: Daten kennzeichnen Schritt 7 als oben", ns.view.main == 7 and ns.view.route.s[7].fl == "up", "Schritt " .. tostring(ns.view.main))
check("Stockwerk: Pfeil sagt \"Oben\" statt \"Am Ziel\"", UltimaArrow.dist._text == "Oben", tostring(UltimaArrow.dist._text))
check("Stockwerk: Tipp nennt das Stockwerk", type(p.tip._text) == "string" and p.tip._text:find("Stockwerk über dir", 1, true) ~= nil, tostring(p.tip._text):sub(-70))
local rowSays = false
for _, f in ipairs(created) do if f.text and f._shown and type(f.text._text) == "string" and f.text._text:find("Oben", 1, true) then rowSays = true end end
check("Stockwerk: Ziel-Zeile trägt den Zusatz \"Oben\"", rowSays)
-- Rundgang mit drei Wegpunkten und zwei Gegnerarten: je eine Zeile, nicht drei bzw. zwei (Screenshot 2026-11-10)
local realShown2 = ns.Runner.Shown
local loop = { id = "loop", n = "Loop", s = { { a = {
  { "goto", m = 1439, x = 100, y = 100, w = true, ci = 1 }, { "goto", m = 1439, x = 200, y = 200, w = true, ci = 1 },
  { "goto", m = 1439, x = 300, y = 300, w = true, ci = 1 }, { "complete", q = 983, o = 1 },
  { "mob", names = { "Pygmy Tide Crawler" } }, { "mob", names = { "Young Reef Crawler" } } } } } }
ns.Runner.Shown = function() return { { route = loop, si = 1, kind = "main" } } end
ns.db.lang = "enUS"; ns.ApplyLanguage(); ns.Update()
local gotoRows, enemyRows, enemyText = 0, 0, nil
for _, f in ipairs(created) do
  -- f.full ist der ganze Satz der Zeile; seit dem Hausstil steht das Verb in einer eigenen Spalte
  if f.icon and f.text and f._shown and type(f.full) == "string" then
    if f.full:find("^Go to ") then gotoRows = gotoRows + 1 end
    if f.full:find("^Enemies: ") then enemyRows = enemyRows + 1; enemyText = f.full end
  end
end
check("Rundgang: genau eine Wegzeile", gotoRows == 1, gotoRows .. " Zeilen")
check("Rundgang: eine Gegner-Zeile mit beiden Namen", enemyRows == 1 and enemyText:find("Pygmy Tide Crawler", 1, true)
  and enemyText:find("Young Reef Crawler", 1, true) ~= nil, tostring(enemyText))
ns.Runner.Shown = realShown2
ns.db.lang = "deDE"; ns.ApplyLanguage(); ns.Update()
-- Auto-Skalierung nach UI-Hoehe (Aufloesung und UI-Skalierung stecken in UIParent:GetHeight)
local uiHeight = 1181
UIParent.GetHeight = function() return uiHeight end
check("Auto-Skalierung: 3440x1440 bei UI-Skalierung 0,65 (Hoehe 1181) -> 0,83", ns.AutoScale() == 0.83, tostring(ns.AutoScale()))
uiHeight = 1000
check("Auto-Skalierung: Hoehe 1000 -> 0,70", ns.AutoScale() == 0.7, tostring(ns.AutoScale()))
uiHeight = 400
check("Auto-Skalierung: untere Grenze 0,60", ns.AutoScale() == 0.6, tostring(ns.AutoScale()))
uiHeight = 3000
check("Auto-Skalierung: obere Grenze 1,30", ns.AutoScale() == 1.3, tostring(ns.AutoScale()))
uiHeight = 1181
local appliedScale
UltimaPanel.SetScale = function(_, v) appliedScale = v end
ns.db.window.autoScale = true
ns.ApplySettings()
check("Einstellungen: Auto-Massstab wird auf das Fenster angewendet", appliedScale == 0.83 and ns.db.window.scale == 0.83, tostring(appliedScale))
ns.db.window.autoScale, ns.db.window.scale = false, 1.25
ns.ApplySettings()
check("Einstellungen: fester Massstab bleibt", appliedScale == 1.25, tostring(appliedScale))
InCombatLockdown = function() return true end
ns.db.window.scale = 0.8
ns.ApplySettings()
check("Einstellungen: im Kampf wird die Fenstergroesse nicht angefasst", appliedScale == 1.25, tostring(appliedScale))
InCombatLockdown = function() return false end
fire("PLAYER_REGEN_ENABLED")
check("Einstellungen: nach dem Kampf wird nachgeholt", appliedScale == 0.8, tostring(appliedScale))
UltimaPanel.SetScale = nil
ns.db.window.autoScale = true

-- Optionsfenster: jede Einstellung hat eine Vorgabe, das Fenster laesst sich bauen und zeigen
local noDefault, optionCount = {}, 0
for _, category in ipairs(ns.OPTION_CATEGORIES) do
  for _, opt in ipairs(category.options) do
    if opt.path then
      optionCount = optionCount + 1
      -- "char.<Pfad>" sind Einstellungen je Charakter (Vorgaben in DEFAULTS.char), seit der Berufe-Seite
      local t, path = ns.DEFAULTS.account, opt.path
      if path:sub(1, 5) == "char." then t, path = ns.DEFAULTS.char, path:sub(6) end
      for key in path:gmatch("[^%.]+") do if type(t) == "table" then t = t[key] else t = nil end end
      if t == nil then noDefault[#noDefault + 1] = opt.path end
    end
  end
end
check("Optionen: jede Einstellung hat eine Vorgabe", #noDefault == 0, #noDefault > 0 and table.concat(noDefault, ", ") or (optionCount .. " Einstellungen in " .. #ns.OPTION_CATEGORIES .. " Kategorien"))
UISpecialFrames = {}
ns.ToggleOptions()
check("Optionen: Fenster oeffnet", UltimaOptions ~= nil and UltimaOptions._shown == true)
ns.ToggleOptions()
check("Optionen: Fenster schliesst", UltimaOptions._shown == false)
-- Kacheln ausblendbar
ns.db.tiles.shown = false
UltimaBonusTile1.IsShown = function(s) return s._shown ~= false end
ns.Update()
check("Optionen: Kacheln lassen sich ausblenden", UltimaBonusTile1._shown == false)
ns.db.tiles.shown = true
ns.Update()
-- Flugpunkte ueber Knoten-ID: deutscher Client, Namen passen nicht zu den englischen Flugdaten
ns.cdb.taxi, ns.cdb.taxiIds = {}, {}
C_TaxiMap = { GetAllTaxiNodes = function() return { { slotIndex = 1, nodeID = 26 }, { slotIndex = 2, nodeID = 28 }, { slotIndex = 3, nodeID = 32 } } end }
NumTaxiNodes = function() return 3 end
TaxiNodeName = function(i) return ({ "Auberdine, Dunkelküste", "Astranaar, Eschental", "Theramore, Düstermarschen" })[i] end
TaxiNodeGetType = function(i) return ({ "CURRENT", "REACHABLE", "DISTANT" })[i] end
local tookId
TakeTaxiNode = function(i) tookId = i end
playerPos[1], playerPos[2], playerPos[3] = 560, 6340, 1
local realShown3 = ns.Runner.Shown
ns.Runner.Shown = function() return {} end
fire("TAXIMAP_OPENED")
check("Flug per ID: bekannte Knoten gemerkt (26, 28), unbekannter nicht (32)", ns.cdb.taxiIds[26] and ns.cdb.taxiIds[28] and not ns.cdb.taxiIds[32])
check("Flug per ID: fp-Schritt 'Auberdine' gilt trotz deutschem Namen als bekannt", ns.KnowsTaxi("Auberdine") == true and ns.KnowsTaxi("Theramore") == false)
local goal2 = { "goto", m = 1440, x = -300, y = 2800, w = true, ci = 1 }
local fp2 = ns.Travel.Plan(goal2)
check("Flug per ID: Reiseplan nutzt die IDs", fp2 and #fp2 == 3 and ns.Travel.flyTargetId == 28, fp2 and fp2[2].text or "kein Plan")
tookId = nil
fire("TAXIMAP_OPENED")
check("Flug per ID: geplantes Ziel wird gewählt (Platz 2)", tookId == 2, tostring(tookId))
local planA, planB = ns.Travel.Plan(goal2), ns.Travel.Plan(goal2) -- zweimal ohne Aenderung dazwischen
check("Reiseplan wird innerhalb einer Sekunde wiederverwendet", planA ~= nil and planA == planB)
ns.Runner.Shown = realShown3
ns.cdb.taxi, ns.cdb.taxiIds = {}, {}
C_TaxiMap = nil
-- Buff-Essen im Rucksack (2026-11-11 nicht erkannt): Tooltip anfangs nicht geladen, dann mit "well fed"
local FOOD_ID = 2684
local tipLoaded = false
C_Container.GetContainerNumSlots = function(bag) return bag == 0 and 2 or 0 end
C_Container.GetContainerItemInfo = function(bag, slot) if bag == 0 and slot == 2 then return { itemID = FOOD_ID } end end
C_TooltipInfo = { GetBagItem = function(bag, slot)
  if bag ~= 0 or slot ~= 2 then return nil end
  if not tipLoaded then return { lines = { { leftText = "Retrieving item information" } } } end
  return { lines = { { leftText = "Coyote Steak" }, { leftText = "Use: Restores 243 health over 21 sec. Must remain seated while eating. If you spend at least 10 seconds eating you will become well fed and gain 4 Stamina and Spirit for 15 min." } } }
end }
C_Item.GetItemNameByID = function(i) return i == FOOD_ID and "Coyote Steak" or nil end
C_Item.GetItemIconByID = function() return 134021 end
ns.Bonus.BagsChanged()
local t1 = ns.Bonus.Tiles()
check("Essen: Tooltip noch nicht geladen -> (noch) keine Aktion", t1[2].action == nil)
tipLoaded = true
fire("GET_ITEM_INFO_RECEIVED")
local t2 = ns.Bonus.Tiles()
check("Essen: nach dem Laden erkannt, Kachel bietet Essen an", t2[2].action and t2[2].action.item == FOOD_ID,
  t2[2].action and tostring(t2[2].action.item) or "keine Aktion")
local outBefore3 = #out
SlashCmdList.ULTIMALEVELING("debug")
local bagsLine = table.concat(out, " | ", outBefore3 + 1)
check("Essen: /ultima debug nennt das gefundene Essen", bagsLine:find("food Coyote Steak", 1, true) ~= nil, bagsLine:match("bags: [^|]*") or "keine bags-Zeile")
C_Container.GetContainerNumSlots = function() return 0 end
ns.Bonus.BagsChanged()
-- Leveling-Talente: Karte neben dem Talentfenster (Paladin, Stufe 14, ein Punkt frei), Befehl, keine
-- Ueberlappung in allen Sprachen
local tnodes, torder = {}, {}
for _, b in ipairs(ns.TalentBuilds.PALADIN) do
  for id, rank in b.order:gmatch("(%d+):(%d+)") do
    id, rank = tonumber(id), tonumber(rank)
    if not tnodes[id] then tnodes[id] = { max = rank, ranks = 0 }; torder[#torder + 1] = id
    elseif rank > tnodes[id].max then tnodes[id].max = rank end
  end
end
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
  GetConfigInfo = function() return { treeIDs = { 10 } } end,
  GetGroupDisplayInfoByTreeID = function() return { { orderIndex = 0, displayName = "Heilig" },
    { orderIndex = 1, displayName = "Schutz" }, { orderIndex = 2, displayName = "Vergeltung" } } end,
  GetTreeNodes = function() return torder end,
  GetNodeInfo = function(_, id) return { ID = id, maxRanks = tnodes[id].max, ranksPurchased = tnodes[id].ranks, entryIDs = { id } } end,
  GetEntryInfo = function(_, id) return { definitionID = id } end,
  GetDefinitionInfo = function(id) return { spellID = id } end,
  GetTreeCurrencyInfo = function() return { { quantity = 1 } } end,
}
local talentButtons = {}
for _, id in ipairs(torder) do
  local b = P("TalentButton")
  b.GetNodeID = function() return id end
  b.IsVisible = function() return true end
  b.GetFrameLevel = function() return 5 end
  b.GetWidth = function() return 38 end
  talentButtons[#talentButtons + 1] = b
end
local talentsFrame = P("TalentsFrame")
talentsFrame.IsVisible = function() return true end
talentsFrame.EnumerateAllTalentButtons = function() local i = 0; return function() i = i + 1; return talentButtons[i] end end
PlayerSpellsFrame = P("PlayerSpellsFrame"); PlayerSpellsFrame.TalentsFrame = talentsFrame
hooksecurefunc = function() end
ns.db.lang = "deDE"; ns.ApplyLanguage()
fire("ADDON_LOADED", "Blizzard_PlayerSpells")
Run()
local card = _G.UltimaTalentCard
check("Talente: Karte neben dem Talentfenster", card ~= nil and card._shown == true)
check("Talente: Build aus dem Baumnamen des Clients", card and card.build._text == "Vergeltung 14/6/31", card and tostring(card.build._text))
check("Talente: erster Punkt bereit", card and card.rows[1] and card.rows[1].info._text == "Jetzt verteilen"
  and card.rows[1].name._text:find("Spell 20101", 1, true) ~= nil, card and card.rows[1] and tostring(card.rows[1].name._text))
local outBeforeTalents = #out
SlashCmdList.ULTIMALEVELING("talents")
local talentLines = table.concat(out, " | ", outBeforeTalents + 1)
check("Talente: /ultima talents nennt Build und Punkte", talentLines:find("Build: Vergeltung 14/6/31", 1, true) ~= nil
  and talentLines:find("Freie Talentpunkte: 1", 1, true) ~= nil, talentLines)
ns.db.talents.overlay = false
ns.RefreshTalents(); Run()
check("Talente: Option aus blendet die Karte aus", card._shown == false)
ns.db.talents.overlay = true
for _, code in ipairs(ns.LANGUAGES) do
  ns.db.lang = code; ns.ApplyLanguage()
  ns.cdb.talentBuild = 1 -- Heilig: Liste beginnt erst bei Punkt 6, Zeilen mit Stufenangabe
  ns.RefreshTalents(); Run()
  local fields = { { "Titel", card.title }, { "Build", card.build }, { "Variante", card.mode }, { "Punkte", card.points },
    { "Verteilt", card.spent } }
  for i, row in ipairs(card.rows) do
    if row._shown then
      fields[#fields + 1] = { "Zeile " .. i, row.name }
      fields[#fields + 1] = { "Zeile " .. i .. " Info", row.info }
    end
  end
  local bad, cut = {}, {}
  for _, f in ipairs(fields) do
    local text = f[2]._text or ""
    if text ~= "" then
      if not f[2]._width then bad[#bad + 1] = f[1] .. " ohne Breite"
      elseif TextWidthEstimate(text, f[2]._size or 12) > f[2]._width + 0.5 then cut[#cut + 1] = f[1] .. " '" .. text .. "'" end
    end
  end
  check(code .. ": Talent-Karte ohne Ueberlappung", #bad == 0 and #cut == 0, table.concat(bad, ", ") .. table.concat(cut, ", "))
end
ns.cdb.talentBuild = nil
ns.db.lang = "deDE"; ns.ApplyLanguage()

-- Ereignisbus: ein fehlerhafter Listener stoppt die übrigen nicht und wird einmal gemeldet
local busHits, busOut = 0, #out
ns.On("TEST_BUS", function() error("kaputt") end)
ns.On("TEST_BUS", function(v) busHits = busHits + v end)
ns.Fire("TEST_BUS", 2); ns.Fire("TEST_BUS", 3)
local busMsgs = 0
for i = busOut + 1, #out do if out[i]:find("kaputt", 1, true) then busMsgs = busMsgs + 1 end end
check("Ereignisbus: Fehler stoppt andere Listener nicht", busHits == 5, tostring(busHits))
check("Ereignisbus: Fehler einmal gemeldet", busMsgs == 1, busMsgs .. " Meldungen")

-- Balken: OnUpdate hängt sich nach Ankunft ab und bei neuem Ziel wieder an
ns.Update()
check("Balken: Gleiten aktiv nach neuem Ziel", p._OnUpdate ~= nil)
for _ = 1, 3 do if p._OnUpdate then p._OnUpdate(p, 1) end end
check("Balken: OnUpdate nach Ankunft entfernt", p._OnUpdate == nil)
ns.Update()
check("Balken: neues Rendern hängt wieder an", p._OnUpdate ~= nil)

-- Wegnetz: der Aufbau-Treiber hängt nur, solange gebaut wird
ns.Paths.Build()
local driver
for _, f in ipairs(created) do
  if f._OnUpdate and debug.getinfo(f._OnUpdate, "S").source:find("Paths.lua", 1, true) then driver = f end
end
check("Wegnetz: Treiber beim Aufbau angehängt", driver ~= nil)
if driver then driver._OnUpdate(driver) end
check("Wegnetz: Treiber nach Aufbau entfernt", driver ~= nil and driver._OnUpdate == nil and ns.Paths.IsReady())

-- QuestSource: passende Questie-Struktur liefert Ziele, eine geänderte schaltet die Quelle ab statt zu werfen
local origLoaded = C_AddOns.IsAddOnLoaded
C_AddOns.IsAddOnLoaded = function(n) return n == "Questie" end
QuestieLoader = { ImportModule = function() return { lookupByKey = {
  m_42 = { { objective = { Update = function() end, Completed = false, Needed = 5, Collected = 2 } } },
  m_43 = { { objective = { Update = function() error("struct changed") end } } } } } end }
ns.QuestSource.Attach()
local qFirst = ns.QuestSource.Objectives("42")
check("QuestSource: Ziel aus Questie gelesen", qFirst and qFirst.Needed == 5)
local qBad = ns.QuestSource.Objectives("43")
check("QuestSource: fremde Struktur schaltet ab", qBad == nil and type(ns.questieIncompatible) == "string"
  and ns.questieIncompatible:find("struct changed", 1, true) ~= nil, tostring(ns.questieIncompatible))
check("QuestSource: danach keine Abfragen mehr", ns.QuestSource.Objectives("42") == nil)
C_AddOns.IsAddOnLoaded = origLoaded
QuestieLoader = nil
ns.questieIncompatible = nil

-- Schritt nur mit Zonen-Reise ("Reise nach Steinkrallengebirge", Screenshot 2026-11-12): in Westfall darf
-- Ultima weder "Am Ziel" melden noch den Hinweis "Niemand da?" zeigen
do
  local zoneOnly = { id = "t:zone", s = { { a = { { "zone", to = "Stonetalon Mountains", zm = 1442 }, { "turnin", q = 79192 } } } } }
  local zoneView = { route = zoneOnly, main = 1, lead = {}, sticky = {}, with = {}, open = {} }
  check("Zonen-Schritt ausserhalb der Zone ist nicht am Ziel", ns.Runner.AtGoal(zoneView) == false,
    "AtGoal=" .. tostring(ns.Runner.AtGoal(zoneView)))
  -- Schlafsack-Route: jede Station hat einen Wegpunkt (Koordinaten aus zwei Guides, siehe src/Data/Extra.lua)
  local bag = ns.Runner.Get("A:extra:Schlafsack-Questreihe")
  local expect = { [3] = { 1442, 40.6 }, [4] = { 1442, 39.6 }, [5] = { 1432, 49.45 }, [6] = { 1424, 87.36 } }
  for si, e in pairs(expect) do
    local view = { route = bag, main = si, lead = {}, sticky = {}, with = {}, open = {} }
    local wp = bag and ns.Runner.Waypoint(view)
    check(("Schlafsack Schritt %d: Pfeil-Ziel Karte %d bei x %.2f"):format(si, e[1], e[2]),
      wp ~= nil and wp.m == e[1] and wp.x == e[2] and ns.Runner.AtGoal(view) == false, tostring(wp and wp.m))
  end
end

-- Schlafsack-Route neu starten mit altem Zeiger (Spielstand 2026-11-12: pointer = 6, Kette steht bei
-- "Stepping Stones"): die Route muss beim Questzustand weitermachen, nicht sofort "fertig" melden
do
  local bagId = "A:extra:Schlafsack-Questreihe"
  local onQuest, flagged = C_QuestLog.IsOnQuest, C_QuestLog.IsQuestFlaggedCompleted
  C_QuestLog.IsOnQuest = function(q) return q == 79192 end
  C_QuestLog.IsQuestFlaggedCompleted = function(q) return q == 79008 end
  ns.Runner.Load("A:route:13-15 Westfall")
  ns.cdb.returnRoute = nil
  ns.cdb.pointer[bagId] = 6
  local outBefore = #out
  UltimaBonusTile3.routeAction = true
  UltimaBonusTile3._PostClick(UltimaBonusTile3)
  ns.Update()
  local finishedMsg = table.concat(out, " | ", outBefore + 1):find("Bonus route finished", 1, true) ~= nil
    or table.concat(out, " | ", outBefore + 1):find("Zusatz-Route", 1, true) ~= nil
  check("Schlafsack-Start mit altem Zeiger: Route bleibt aktiv", ns.cdb.route == bagId and not finishedMsg, tostring(ns.cdb.route))
  check("Schlafsack-Start mit altem Zeiger: Schritt 3 (Stepping Stones abgeben)", ns.view.main == 3, tostring(ns.view.main))
  -- Kette nie begonnen: Start in Westfall (Schritt 1), auch mit altem Zeiger
  local function Restart(pointer, onQ, done)
    C_QuestLog.IsOnQuest = function(q) return onQ[q] == true end
    C_QuestLog.IsQuestFlaggedCompleted = function(q) return done[q] == true end
    ns.Runner.Load("A:route:13-15 Westfall")
    ns.cdb.returnRoute = nil
    ns.cdb.pointer[bagId] = pointer
    UltimaBonusTile3._PostClick(UltimaBonusTile3)
    ns.Update()
    return ns.cdb.route, ns.view.main
  end
  local r1, m1 = Restart(6, {}, {})
  check("Schlafsack nie begonnen: Start bei Schritt 1", r1 == bagId and m1 == 1, tostring(r1) .. " " .. tostring(m1))
  -- Scramble abgebrochen (79192 abgegeben, 79980 weder im Log noch fertig): Schritt 3 nimmt Scramble wieder an
  local r2, m2 = Restart(6, {}, { [79008] = true, [79192] = true })
  check("Schlafsack Scramble abgebrochen: Schritt 3", r2 == bagId and m2 == 3, tostring(r2) .. " " .. tostring(m2))
  C_QuestLog.IsOnQuest, C_QuestLog.IsQuestFlaggedCompleted = onQuest, flagged
end

-- Berufe abschalten (Willkommensfenster): Muster aus den Routen-Daten (Erhebung 2026-11-12)
do
  local P, S = ns.Progress, ns.State
  local player = S.Player()
  local skillLevel = S.SkillLevel
  local levels = { cooking = 60, firstaid = 0 }
  S.SkillLevel = function(name) return levels[name] end
  local train = { a = { { "goto", m = 1453, x = 40, y = 40 }, { "target", names = { "Trainer" } }, { "train", sp = 3273 } } }
  local farm = { a = { { "collect", i = 769, n = 50 }, { "mob", names = { "Boar" } }, { "skill", name = "cooking", lvl = 50, skip = true } } }
  local withMeat = { a = { { "complete", q = 1, o = 1 }, { "skill", name = "cooking", lvl = 50, rev = true, skip = true } } }
  local noMeat = { a = { { "complete", q = 1, o = 1 }, { "skill", name = "cooking", lvl = 50, skip = true } } }
  local cookQuest = { a = { { "accept", q = 2 }, { "skill", name = "cooking", lvl = 50, skip = true } } }
  ns.cdb.professions = { firstaid = true, cooking = true, fishing = true }
  levels.cooking = 10
  check("Berufe an: Lehrer-Schritt Erste Hilfe gilt", P.Applies(train, player))
  check("Berufe an, Kochen 10: Hochzieh-Schritt gilt", P.Applies(farm, player))
  ns.cdb.professions.firstaid = false
  ns.cdb.professions.cooking = false
  levels.cooking = 60
  check("Erste Hilfe aus: Lehrer-Schritt entfällt", not P.Applies(train, player))
  check("Kochen aus: Hochzieh-Schritt entfällt", not P.Applies(farm, player))
  check("Kochen aus (gelernt 60): Weg mit Fleisch entfällt", not P.Applies(withMeat, player))
  check("Kochen aus (gelernt 60): Weg ohne Fleisch gilt", P.Applies(noMeat, player))
  check("Kochen aus: Schritt mit Quest bleibt", P.Applies(cookQuest, player))
  -- echte Route: Duskwood mit Kochquests, an und aus im Vergleich
  local duskwood
  for _, r in ipairs(ns.routes) do if r.n == "24-27 Duskwood/Redridge" then duskwood = r end end
  local function Count()
    local n = 0
    for _, s in ipairs(duskwood.s) do if P.Applies(s, player) then n = n + 1 end end
    return n
  end
  local off = duskwood and Count()
  ns.cdb.professions = { firstaid = true, cooking = true, fishing = true }
  levels.cooking = 0
  local on = duskwood and Count()
  check("Echte Route Duskwood: Kochen aus zeigt weniger Schritte als Kochen an", duskwood ~= nil and off < on,
    tostring(off) .. " / " .. tostring(on))
  S.SkillLevel = skillLevel
  ns.cdb.professions = { firstaid = true, cooking = true, fishing = true }
end

-- Willkommensfenster: erscheint beim ersten Start des Charakters, Schalter wirken auf die Einstellungen
do
  check("Willkommen: nach dem Start gebaut und offen", UltimaWelcome ~= nil and UltimaWelcome._shown == true,
    tostring(UltimaWelcome and UltimaWelcome._shown))
  ns.cdb.professions = { firstaid = true, cooking = true, fishing = true }
  ns.ShowWelcome()
  local switches = UltimaWelcome.choices and UltimaWelcome.choices.switches or {}
  check("Willkommen: Seite Route mit fünf Schaltern (drei Berufe, zwei Dungeon-Schalter)", #switches == 5, #switches .. " Schalter")
  local helpers = UltimaWelcome.helpers and UltimaWelcome.helpers.switches or {}
  check("Willkommen: Seite Hilfen mit neun Schaltern", #helpers == 9, #helpers .. " Schalter")
  local train = ns.db.autoTrain
  if helpers[2] then helpers[2]._OnClick(helpers[2]) end
  check("Willkommen: Schalter Zauber kaufen wirkt auf die Einstellung", ns.db.autoTrain == not train)
  ns.db.autoTrain = train
  if switches[1] then switches[1]._OnClick(switches[1]) end
  check("Willkommen: Schalter Erste Hilfe schaltet nur diesen Charakter", ns.cdb.professions.firstaid == false
    and ns.db.professions == nil)
  UltimaWelcome:Hide()
  if UltimaWelcome._OnHide then UltimaWelcome._OnHide(UltimaWelcome) end
  check("Willkommen: Schließen merkt sich den Charakter", ns.cdb.welcomed == true)
  ns.cdb.professions = { firstaid = true, cooking = true, fishing = true }
end

-- Dungeon-Vorbereitung: Liste, Start als Zusatz-Route, Verschachtelung mit dem Schlafsack, Rückkehr
do
  local R = ns.Runner
  local onQuest, flagged = C_QuestLog.IsOnQuest, C_QuestLog.IsQuestFlaggedCompleted
  C_QuestLog.IsOnQuest = function() return false end
  C_QuestLog.IsQuestFlaggedCompleted = function() return false end
  local list = R.DungeonList()
  local names, era, empty = {}, false, false
  for _, e in ipairs(list) do
    names[#names + 1] = e.name
    if e.route.era then era = true end
    if e.total == 0 then empty = true end
  end
  check("Dungeons: Forever-Liste der Allianz ohne Classic-Doppel und ohne leere", #list >= 20 and not era and not empty,
    #list .. " Dungeons")
  check("Dungeons: Anzeigename ohne Nummer, Reihenfolge der Quelle", names[1] == "Hall of Thanes" and names[3] == "The Deadmines",
    tostring(names[1]) .. ", " .. tostring(names[3]))
  local deadmines
  for _, e in ipairs(list) do if e.name == "The Deadmines" then deadmines = e end end
  check("Dungeons: Deadmines mit 13 Quests, keine erledigt", deadmines and deadmines.total == 13 and deadmines.done == 0,
    deadmines and (deadmines.total .. "/" .. deadmines.done))
  -- Start aus der Leveling-Route, dann Schlafsack: Rückweg bleibt die Leveling-Route
  R.Load("A:route:13-15 Westfall")
  R.StartBonus(deadmines.route.id)
  check("Dungeons: Start merkt die Leveling-Route", ns.cdb.route == deadmines.route.id and ns.cdb.returnRoute == "A:route:13-15 Westfall",
    tostring(ns.cdb.returnRoute))
  R.StartBonus("A:extra:Schlafsack-Questreihe")
  check("Dungeons: Schlafsack danach behält den Rückweg zur Leveling-Route", ns.cdb.returnRoute == "A:route:13-15 Westfall",
    tostring(ns.cdb.returnRoute))
  R.StartBonus(deadmines.route.id)
  check("Dungeons: Levelaufstieg wechselt die Vorbereitung nicht", R.AutoSelect(false) == deadmines.route.id)
  -- Alles abgegeben: Vorbereitung fertig, zurück zur Leveling-Route
  C_QuestLog.IsQuestFlaggedCompleted = function() return true end
  ns.Update()
  check("Dungeons: fertig -> zurück zur Leveling-Route", ns.cdb.route == "A:route:13-15 Westfall" and ns.cdb.returnRoute == nil,
    tostring(ns.cdb.route))
  -- Mittendrin: 65 und 132 schon abgegeben (Redridge erledigt), du stehst in Westfall. Kein Flug nach
  -- Redridge mehr, weiter mit der nächsten offenen Quest (135 in Westfall, Schritt 6)
  C_QuestLog.IsQuestFlaggedCompleted = function(q) return q == 65 or q == 132 end
  R.StartBonus(deadmines.route.id)
  ns.Update()
  check("Dungeons: Reise zu erledigten Quests entfällt", ns.cdb.route == deadmines.route.id and ns.view.main == 6,
    tostring(ns.view.main))
  -- Von Hand verlassen
  C_QuestLog.IsQuestFlaggedCompleted = function() return false end
  R.StartBonus(deadmines.route.id)
  check("Dungeons: von Hand zurück", R.EndBonus() == "A:route:13-15 Westfall" and ns.cdb.route == "A:route:13-15 Westfall")
  -- Oberfläche: /ultima dungeon zeigt die Liste, ein Klick startet die Vorbereitung, die Routenwahl bietet den Rückweg
  if UltimaRoutePicker then UltimaRoutePicker:Hide() end
  SlashCmdList.ULTIMALEVELING("dungeon")
  local shown = {}
  for _, b in ipairs(UltimaRoutePicker and UltimaRoutePicker.buttons or {}) do
    if b._shown then shown[#shown + 1] = b end
  end
  local dmButton
  for _, b in ipairs(shown) do if (b.label._text or ""):find("^The Deadmines") then dmButton = b end end
  check("Dungeons: Liste zeigt jeden Dungeon mit Fortschritt", #shown == #list and dmButton ~= nil
    and dmButton.right._text == "0 von 13 erledigt", #shown .. " Einträge, " .. tostring(dmButton and dmButton.right._text))
  if dmButton then dmButton._OnClick(dmButton) end
  ns.Update()
  check("Dungeons: Klick startet die Vorbereitung, Kopf ohne Nummer", ns.cdb.route == deadmines.route.id
    and UltimaPanel.title._text == "The Deadmines" and (UltimaPanel.sub._text or ""):find("^Dungeon%-Quests") ~= nil,
    tostring(UltimaPanel.title._text) .. " / " .. tostring(UltimaPanel.sub._text))
  ns.ToggleRoutePicker()
  local first = UltimaRoutePicker.buttons[1]
  check("Dungeons: Routenwahl bietet den Rückweg zuerst", first and (first.label._text or ""):find("^Zurück zu 13%-15 Westfall") ~= nil,
    tostring(first and first.label._text))
  UltimaRoutePicker:Hide()
  R.EndBonus()
  C_QuestLog.IsOnQuest, C_QuestLog.IsQuestFlaggedCompleted = onQuest, flagged
end

-- Knopfleiste: acht Knöpfe aus ns.PANEL_BUTTONS, jeder tut, was die Willkommens-Seite erklärt
do
  local by = UltimaPanel.buttonByKey or {}
  local n = 0
  for _ in pairs(by) do n = n + 1 end
  check("Knöpfe: acht Knöpfe im Fenster", n == 8 and #ns.PANEL_BUTTONS == 8, n .. " Knöpfe")
  if UltimaRoutePicker then UltimaRoutePicker:Hide() end
  by.dungeon._OnClick(by.dungeon)
  check("Knöpfe: Dungeon-Knopf öffnet die Dungeon-Liste", UltimaRoutePicker._shown == true and UltimaRoutePicker.mode == "dungeons")
  UltimaRoutePicker:Hide()
  local shownBefore = ns.db.arrow.shown
  by.arrow._OnClick(by.arrow)
  check("Knöpfe: Pfeil-Knopf schaltet den Pfeil", ns.db.arrow.shown == not shownBefore)
  by.arrow._OnClick(by.arrow)
  UltimaWelcome:Hide()
  by.help._OnClick(by.help)
  check("Knöpfe: Hilfe-Knopf öffnet die Anleitung", UltimaWelcome._shown == true)
  check("Knöpfe: Anleitung erklärt jeden Knopf", UltimaWelcome.buttonsPage ~= nil and #UltimaWelcome.buttonsPage.items == 8,
    tostring(UltimaWelcome.buttonsPage and #UltimaWelcome.buttonsPage.items))
  UltimaWelcome:Hide()
end

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
