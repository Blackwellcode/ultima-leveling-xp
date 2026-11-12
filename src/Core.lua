-- Ultima Leveling XP: Kern. Namensraum, gespeicherte Daten, Ereignisbus.
-- Alle Module teilen den Namensraum "ns" (local addonName, ns = ...).
local addonName, ns = ...

ns.NAME = addonName
ns.GAME = "FOREVER"
ns.PREFIX = "|cff33d6b0Ultima:|r "
ns.WARN = "|cffff4040Ultima:|r "

local DEFAULTS = {
    account = {
        -- window.point und arrow.point entstehen beim Verschieben; ohne sie gilt die Ausgangslage
        window = { collapsed = false, autoScale = true, scale = 1, alpha = 1, combatAlpha = 0.6, locked = false },
        arrow = { shown = true, scale = 1 },
        minimap = { hide = false },
        questPlates = { enabled = true, border = true, dangerDiff = 5, eliteDangerDiff = 3 },
        routeKind = "route",   -- route, dungeonroute
        predecessorFirst = true, -- unfertige Vorgänger-Route zuerst wählen
        dungeonSteps = false,  -- Schritte zeigen, die in einen Dungeon führen (alle Dungeons)
        dungeons = {},         -- einzelne Dungeons (Kürzel -> true), zusätzlich zu dungeonSteps
        hints = true,          -- Hinweistexte unter den Handlungen zeigen
        hintCount = 3,         -- so viele Hinweise je Schritt
        showNext = true,       -- Vorschau auf den nächsten Schritt
        autoQuest = true,      -- Quests der Route automatisch annehmen und abgeben (Umschalt setzt aus)
        autoTrain = true,      -- beim Lehrer die verlangten Zauber kaufen
        autoFly = true,        -- beim Flugmeister das Ziel wählen
        travel = { flights = true, minSaving = 90 }, -- Reiseplaner: Flug/Ruhestein ab so vielen Sekunden Ersparnis
        tiles = { shown = true },
        announce = true,       -- verlorene Boni und Gefahren in der Bildschirmmitte melden
        dangerWarn = true, dangerGap = 3, groupWarn = true,
        pins = { world = true, minimap = true, dots = 8 },
        buttons = { item = true, target = true },
        talents = { overlay = true, remind = true }, -- Leveling-Talente im Talentfenster, Erinnerung an freie Punkte
        lang = "auto",         -- Oberflächen-Sprache: "auto" = Client-Sprache, sonst Code wie "deDE"
        auraIds = {},          -- im Spiel gelernte Zauber-IDs der Forever-Buffs (Schlüssel -> spellId)
        campItems = {},        -- im Spiel gelernte Lagerfeuer-Items (itemID -> true)
    },
    char = {
        -- route (aktive Routen-ID) und returnRoute entstehen bei der Routenwahl;
        -- talentBuild (Index des gewählten Leveling-Builds) bei eigener Wahl im Talentfenster, sonst automatisch
        manual = {},           -- [routeId] = { [stepIndex] = true } von Hand abgehakt
        pointer = {},          -- [routeId] = Index des aktuellen Haupt-Schritts (läuft nur vorwaerts)
        marks = {},            -- [routeId] = { [stepIndex .. ":" .. actionIndex] = true } Ereignis-Marken
        open = {},             -- [routeId] = { [stepIndex] = questId } zurückgestellte Abgaben
        unavail = {},          -- [questId] = true: beim Questgeber nicht im Angebot (bis zum nächsten Level)
        taxi = {},             -- [Name] = true: bekannte Flugpunkte (Name in Client-Sprache, Rückfall)
        taxiIds = {},          -- [Knoten-ID] = true: bekannte Flugpunkte, sprachunabhängig
    },
}

ns.DEFAULTS = DEFAULTS

local function Fill(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then target[key] = {} end
            Fill(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-------------------------------------------------------------------------------
-- Ereignisbus: Module koppeln sich über Namen, nicht über direkte Aufrufe.
-------------------------------------------------------------------------------
local listeners = {}
function ns.On(name, fn)
    listeners[name] = listeners[name] or {}
    table.insert(listeners[name], fn)
end
-- Jeder Listener läuft geschützt: ein Fehler in einem Modul bricht die übrigen Listener nicht ab. Er
-- erscheint einmal je Meldung im Chat und geht an den Fehler-Handler (BugSack), statt still zu verschwinden.
local busReported = {}
local function ReportListenerError(name, err)
    local text = tostring(err)
    local key = name .. text
    if busReported[key] then return end
    busReported[key] = true
    print(ns.WARN .. name .. ": " .. text)
    local handler = geterrorhandler and geterrorhandler()
    if handler then pcall(handler, text) end
end

function ns.Fire(name, ...)
    local list = listeners[name]
    if not list then return end
    for _, fn in ipairs(list) do
        local ok, err = pcall(fn, ...)
        if not ok then ReportListenerError(name, err) end
    end
end

-------------------------------------------------------------------------------
-- Gespeicherte Daten
-------------------------------------------------------------------------------
function ns.InitDB(account, char)
    -- Oberflächen-Sprache folgt dem Client, bis du mit /ultima sprache selbst wählst (langChosen).
    -- So wird auch ein früher automatisch gesetztes "deDE" wieder zur Client-Sprache.
    if not account.langChosen then account.lang = "auto" end
    Fill(account, DEFAULTS.account)
    Fill(char, DEFAULTS.char)
    ns.db, ns.cdb = account, char
    if ns.ApplyLanguage then ns.ApplyLanguage() end
end

if CreateFrame then
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ADDON_LOADED")
    loader:SetScript("OnEvent", function(self, _, name)
        if name ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        UltimaAccountDB = UltimaAccountDB or {}
        UltimaCharDB = UltimaCharDB or {}
        ns.InitDB(UltimaAccountDB, UltimaCharDB)
        ns.Fire("READY")
    end)
end
