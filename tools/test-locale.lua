-- Offline-Test der Mehrsprachigkeit: Sprachtabellen vollständig und formatgleich, Sprachwahl, Umstellung
-- alter Installationen, übersetzte Routen-Texte und NPC-Namen aus den Sprach-Addons.
-- Aufruf aus dem Projektordner: lua tools/test-locale.lua
local fails = 0
local function check(label, ok, detail)
    if not ok then fails = fails + 1 end
    io.write(("%-66s %s%s\n"):format(label, ok and "OK" or "FEHLER", detail and ("  " .. detail) or ""))
end

-- Minimale Spielumgebung für Core und Live
local clientLocale = "enUS"
GetLocale = function() return clientLocale end
local frames = {}
CreateFrame = function()
    local f = { RegisterEvent = function() end, RegisterUnitEvent = function() end, UnregisterEvent = function() end }
    f.SetScript = function(self, _, fn) self.onEvent = fn end
    frames[#frames + 1] = f
    return f
end
C_Timer = { After = function() end, NewTicker = function() end }
local loadedAddon
C_AddOns = { LoadAddOn = function(name)
    local loc = name:match("^UltimaLevelingXP_(%a%a%u%u)$")
    local f = loc and io.open("data/Text_" .. loc .. ".lua", "rb")
    if not f then return false, "MISSING" end
    f:close()
    assert(loadfile("data/Text_" .. loc .. ".lua"))()
    loadedAddon = name
    return true
end }

local ns = {}
local LOCALE_FILES = { "Locale", "enUS", "deDE", "frFR", "esES", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
assert(loadfile("src/Core.lua"))("UltimaLevelingXP", ns)
for _, f in ipairs(LOCALE_FILES) do assert(loadfile("src/Locale/" .. f .. ".lua"))("UltimaLevelingXP", ns) end

-------------------------------------------------------------------------------
-- 1. Jeder im Code benutzte Schlüssel steht in der englischen Haupttabelle
-------------------------------------------------------------------------------
local en = ns.LOCALES.enUS
-- Schl�sselsuche liegt in tools/locale-keys.lua (kennt auch die Daten-Eintr�ge des Optionsfensters)
local missingEn = {}
local used, usedF = dofile("tools/locale-keys.lua").Used()
for k, path in pairs(used) do if en[k] == nil then missingEn[#missingEn + 1] = k .. " (" .. path .. ")" end end
local usedCount = 0
for _ in pairs(used) do usedCount = usedCount + 1 end
check("Alle Schlüssel aus dem Code in enUS", #missingEn == 0,
    #missingEn > 0 and table.concat(missingEn, " | ") or (usedCount .. " Schlüssel"))
local enCount, unused = 0, {}
for k in pairs(en) do
    enCount = enCount + 1
    if not used[k] then unused[#unused + 1] = k end
end
check("enUS ohne verwaiste Schlüssel", #unused == 0, #unused > 0 and table.concat(unused, " | ") or (enCount .. " Schlüssel"))

-------------------------------------------------------------------------------
-- 2. Jede Sprache vollständig, ohne Fremdschlüssel, mit denselben Platzhaltern in derselben Reihenfolge
-------------------------------------------------------------------------------
local function Placeholders(s)
    local list = {}
    for p in s:gmatch("%%[%d%.]*[%a%%]") do list[#list + 1] = p end
    return table.concat(list, " ")
end
for _, code in ipairs(ns.LANGUAGES) do
    local t = ns.LOCALES[code]
    local missing, extra, bad = {}, {}, {}
    if t then
        for k in pairs(en) do
            if t[k] == nil then missing[#missing + 1] = k
            elseif Placeholders(t[k]) ~= Placeholders(k) then bad[#bad + 1] = k end
        end
        for k in pairs(t) do if en[k] == nil then extra[#extra + 1] = k end end
    end
    check(code .. ": vorhanden und vollständig", t ~= nil and #missing == 0,
        #missing > 0 and (#missing .. " fehlen: " .. missing[1]) or nil)
    check(code .. ": keine unbekannten Schlüssel", #extra == 0, #extra > 0 and extra[1] or nil)
    check(code .. ": Platzhalter gleich", #bad == 0, #bad > 0 and bad[1] or nil)
end

-------------------------------------------------------------------------------
-- 3. Sprachwahl und Formatierung
-------------------------------------------------------------------------------
local function Lang(setting, client)
    clientLocale = client
    ns.db = { lang = setting }
    return ns.ApplyLanguage()
end
check("auto + deutscher Client -> deDE", Lang("auto", "deDE") == "deDE")
check("auto + englischer Client (enGB) -> enUS", Lang("auto", "enGB") == "enUS")
check("auto + mexikanischer Client -> esES", Lang("auto", "esMX") == "esES")
check("auto + unbekannte Sprache -> enUS", Lang("auto", "xxXX") == "enUS")
check("Einstellung deDE schlägt englischen Client", Lang("deDE", "enUS") == "deDE")
Lang("auto", "enUS")
check("enUS: Text", ns.F("Accept: %s", "X") == "Accept: X")
Lang("deDE", "enUS")
check("deDE: Text", ns.F("Accept: %s", "X") == "Annehmen: X", ns.F("Accept: %s", "X"))
check("deDE: Prozent bleibt Prozent", ns.F("Rested %d %%", 30) == "Erholt 30 %", ns.F("Rested %d %%", 30))
Lang("frFR", "frFR")
check("frFR: Text", ns.L["NOW"] == "MAINTENANT")
check("Fehlender Schlüssel zeigt den englischen Text", ns.L["Ultima-Test ohne Übersetzung"] == "Ultima-Test ohne Übersetzung")
-- Jede Formatzeile (ns.F) lässt sich in jeder Sprache mit Beispielwerten formatieren
local formatErrors = {}
for _, code in ipairs(ns.LANGUAGES) do
    for k, v in pairs(ns.LOCALES[code]) do
      if usedF[k] then
        local args = {}
        for p in k:gmatch("%%[%d%.]*([%a])") do args[#args + 1] = (p == "s") and "x" or 1 end
        local ok = pcall(string.format, v, table.unpack(args))
        if not ok then formatErrors[#formatErrors + 1] = code .. ": " .. k end
      end
    end
end
check("Alle Übersetzungen formatierbar", #formatErrors == 0, formatErrors[1])

-------------------------------------------------------------------------------
-- 4. Vorgabe: Client-Sprache, solange keine eigene Wahl gespeichert ist (2026-11-09:
--    englischer Client soll englische Oberfläche zeigen; die frühere Festlegung auf deDE ist verworfen)
-------------------------------------------------------------------------------
clientLocale = "enUS"
local old = { window = { collapsed = false }, lang = "deDE" } -- von der verworfenen Umstellung automatisch gesetzt
ns.InitDB(old, {})
check("Automatisch gesetztes deDE ohne eigene Wahl -> Client-Sprache", old.lang == "auto" and ns.LANG == "enUS",
    tostring(old.lang) .. " / " .. ns.LANG)
local fresh = {}
ns.InitDB(fresh, {})
check("Neue Installation -> auto (Client)", fresh.lang == "auto" and ns.LANG == "enUS", tostring(fresh.lang))
local chosen = { lang = "deDE", langChosen = true }
ns.InitDB(chosen, {})
check("Eigene Wahl deDE bleibt im englischen Client", chosen.lang == "deDE" and ns.LANG == "deDE", ns.LANG)

-------------------------------------------------------------------------------
-- 5. Routen-Texte und NPC-Namen aus dem Sprach-Addon (deutscher Client)
-------------------------------------------------------------------------------
-- Live braucht Runner und State nur als Tabellen
ns.Runner, ns.State = { Reindex = function() end }, {}
assert(loadfile("src/Live.lua"))("UltimaLevelingXP", ns)
for _, f in ipairs({ "data/Routes_A.lua", "data/Routes_B.lua" }) do assert(loadfile(f))() end
ns.routes = UltimaRouteData
local function Find(id) for _, r in ipairs(ns.routes) do if r.id == id then return r end end end
local ds = Find("A:route:16-19 Darkshore")
local englishHint = ds.s[4].h and ds.s[4].h[1]
clientLocale = "deDE"
ns.ApplyRouteText()
check("Sprach-Addon für deDE geladen", loadedAddon == "UltimaLevelingXP_deDE" and UltimaRouteText == nil)
check("NPC-Name übersetzt: Thundris Windweaver",
    ns.npcNames and ns.npcNames["Thundris Windweaver"] == "Thundris Windwirker",
    ns.npcNames and tostring(ns.npcNames["Thundris Windweaver"]))
local germanHint = ds.s[4].h and ds.s[4].h[1]
check("Routen-Hinweis übersetzt (16-19 Darkshore, Schritt 4)", germanHint and germanHint ~= englishHint,
    tostring(englishHint) .. " -> " .. tostring(germanHint))
check("Routenname übersetzt", ds.n ~= "16-19 Darkshore", ds.n)
check("Routen-ID bleibt englisch (gespeicherter Fortschritt)", ds.id == "A:route:16-19 Darkshore")
-- Englischer Client lädt kein Sprach-Addon
loadedAddon = nil
clientLocale = "enUS"
ns.ApplyRouteText()
check("Englischer Client lädt kein Sprach-Addon", loadedAddon == nil)
-- Italienisch: keine Routen-Übersetzung in der Quelle, kein Fehler
clientLocale = "itIT"
ns.ApplyRouteText()
check("Italienischer Client ohne Sprach-Addon: kein Fehler", loadedAddon == nil)

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
