-- Sprachen: ns.L["English text"] liefert den Text in der gewählten Oberflächen-Sprache.
-- Fehlt eine Übersetzung, erscheint der englische Schlüssel, nie eine Lücke.
-- Sprache: ns.db.lang = "auto" (Client-Sprache) oder ein Code wie "deDE". Format-Platzhalter (%s, %d)
-- bleiben in jeder Übersetzung in derselben Reihenfolge.
local _, ns = ...

local LOCALES = {}
ns.LOCALES = LOCALES
ns.LANG = "enUS"

-- Client-Sprachen, die WoW meldet, und die Tabelle, die sie nutzen
local ALIAS = { enGB = "enUS", esMX = "esES", ptPT = "ptBR" }
ns.LANGUAGES = { "enUS", "deDE", "frFR", "esES", "itIT", "ptBR", "ruRU", "koKR", "zhCN", "zhTW" }
-- Diese Schriften brauchen die Client-Schrift (Fira Sans hat keine Zeichen dafür)
ns.CJK = { koKR = true, zhCN = true, zhTW = true }

function ns.RegisterLocale(code, strings)
    LOCALES[code] = strings
end

ns.L = setmetatable({}, {
    __index = function(_, key)
        local t = LOCALES[ns.LANG]
        local v = t and t[key]
        if v == nil then return key end
        return v
    end,
    __newindex = function() error("ns.L ist schreibgeschützt, Übersetzungen über ns.RegisterLocale") end,
})

function ns.ClientLocale()
    local loc = GetLocale and GetLocale() or "enUS"
    return ALIAS[loc] or loc
end

-- Wirksame Oberflächen-Sprache aus der Einstellung bestimmen.
function ns.ApplyLanguage()
    local wanted = ns.db and ns.db.lang or "auto"
    if wanted == "auto" then wanted = ns.ClientLocale() end
    wanted = ALIAS[wanted] or wanted
    if wanted ~= "enUS" and not LOCALES[wanted] then wanted = "enUS" end
    ns.LANG = wanted
    return wanted
end

-- Übersetzen mit Formatierung: ns.F("Step %d of %d", 3, 10)
function ns.F(key, ...)
    return ns.L[key]:format(...)
end
