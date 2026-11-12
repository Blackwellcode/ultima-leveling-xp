-- Live: verbindet die Engine mit dem Spiel. Laedt die Routen der eigenen Fraktion nach, wertet bei
-- Spielereignissen neu aus, setzt Ereignis-Marken (Ruhestein, Flug, Flugpunkt) und meldet "VIEW".
local _, ns = ...
local R = ns.Runner
-- Ruhestein und gleichwertige Heimkehr-Zauber: Ruhestein, Astraler Rückruf, Varianten
local HEARTHSTONE = { [8690] = true, [556] = true, [348699] = true, [184871] = true }

local pending = false
local onTaxi = false
-- Bis das Questlog nach dem Einloggen geladen ist, sieht jede Quest "nicht angenommen" aus. In der Zeit
-- darf die Engine nichts überspringen oder zurückstellen (Runner prüft ns.questsReady).
ns.questsReady = false

-- Routen-Texte in Client-Sprache (Hinweise, Routennamen, NPC-Namen) aus dem Sprach-Addon
-- UltimaLevelingXP_<Sprache>. Sie folgen der Client-Sprache, weil sie Namen aus dem Spiel nennen.
-- Ohne Sprach-Addon (Englisch, Italienisch) bleiben die englischen Texte.
function ns.ApplyRouteText()
    local loc = ns.ClientLocale()
    if loc == "enUS" then return end
    local name = ns.NAME .. "_" .. loc
    local loaded, reason = C_AddOns.LoadAddOn(name)
    if not loaded then
        -- MISSING = für diese Sprache gibt es keine übersetzten Routen-Texte; alles andere ist ein Fehler
        if reason ~= "MISSING" then print(ns.WARN .. ns.F("Route data %s not loaded: %s", name, tostring(reason))) end
        return
    end
    local data = UltimaRouteText
    UltimaRouteText = nil
    if type(data) ~= "table" then return end
    ns.npcNames = data.npc
    ns.routeTextLocale = loc
    local done = {}
    for _, r in ipairs(ns.routes) do
        local src = r.src
        if src and data.n and data.n[src] then r.n = data.n[src] end
        local steps = src and data.s and data.s[src]
        if steps and not done[src] then
            -- Fraktions-Kopien teilen ihre Schritte: jede Quelle nur einmal übersetzen
            done[src] = true
            for si, loc_s in pairs(steps) do
                local s = r.s[si]
                if s then
                    if loc_s.h then s.h = loc_s.h end
                    for ai, text in pairs(loc_s.t or {}) do
                        if s.a[ai] then s.a[ai].t = text end
                    end
                end
            end
        end
    end
end

-- Routen der eigenen Fraktion aus dem Nachlade-Addon holen.
local function LoadRoutes()
    if ns.routes then return true end
    local faction = UnitFactionGroup("player")
    local letter = faction == "Alliance" and "A" or faction == "Horde" and "H" or nil
    if not letter then return false end
    local name = ns.NAME .. "_" .. letter
    local loaded, reason = C_AddOns.LoadAddOn(name)
    if not loaded then
        print(ns.WARN .. ns.F("Route data %s not loaded: %s", name, tostring(reason)))
        return false
    end
    ns.routes = UltimaRouteData or {}
    UltimaRouteData = nil
    ns.ApplyRouteText()
    -- Eigene Zusatz-Routen (z. B. Schlafsack-Questreihe) der eigenen Fraktion anhaengen
    for _, r in ipairs(ns.BuildExtraRoutes()) do
        if r.f == letter or r.f == "B" then ns.routes[#ns.routes + 1] = r end
    end
    R.Reindex()
    ns.Fire("ROUTES_LOADED")
    return #ns.routes > 0
end

local function DoUpdate()
    -- Zusatz-Route von Hand verlassen: der Rückweg zur selben Route ist dann gegenstandslos
    if ns.cdb.returnRoute and ns.cdb.returnRoute == ns.cdb.route then ns.cdb.returnRoute = nil end
    if not ns.routes then return end
    if not ns.questsReady then return end -- Questlog noch leer: keine Route wechseln, nichts anzeigen
    if not ns.cdb.route or not R.Get(ns.cdb.route) then
        local id = R.AutoSelect(true)
        if id then print(ns.PREFIX .. ns.F("Route: %s", R.Get(id).n)) end
    end
    local view = R.Evaluate()
    if view.finished and view.route and ns.cdb.returnRoute and R.Get(ns.cdb.returnRoute) then
        -- Zusatz-Route fertig: zurück zur eigentlichen Route
        local back = ns.cdb.returnRoute
        ns.cdb.returnRoute = nil
        R.Load(back)
        print(ns.PREFIX .. ns.F("Bonus route finished, continuing with %s", R.Get(back).n or back))
        view = R.Evaluate()
    elseif view.finished and view.route then
        local nextId = R.Advance(view)
        if nextId then
            print(ns.PREFIX .. ns.F("Continuing with %s", R.Get(nextId).n or nextId))
            view = R.Evaluate()
        end
    end
    ns.view = view
    ns.Fire("VIEW", view)
end

-- Auswertung geschützt: ein Fehler erscheint einmal im Chat und hält die Route nicht dauerhaft an
function ns.Update()
    pending = false
    ns.Guard("Update", DoUpdate)
end

function ns.RequestUpdate()
    if pending then return end
    pending = true
    C_Timer.After(0.15, ns.Update)
end

local function Mark(tag)
    if ns.view and R.MarkFirst(ns.view, tag) then ns.RequestUpdate() end
end

-- Questgeber-Gespräch: Bietet der NPC eine Quest aus dem aktuellen Schritt nicht an (Voraussetzung fehlt,
-- Level zu niedrig), gilt die Annahme als nicht verfügbar und hält die Route nicht an.
local function CheckOffers()
    local view = ns.view
    if not (view and view.route and view.main) then return end
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
    local offered, known = {}, false
    for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if info.questID then offered[info.questID] = true; known = true end
    end
    for _, info in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        if info.questID then known = true end
    end
    if not known then return end -- Angebot ohne Quest-IDs: keine sichere Aussage möglich
    local npc = UnitName("npc")
    local step = view.route.s[view.main]
    local isGiver = false
    for _, a in ipairs(step.a) do
        if a[1] == "target" and a.names then
            for _, n in ipairs(a.names) do if n == npc or ns.NPC(n) == npc then isGiver = true end end
        end
    end
    if not isGiver then return end -- Name unbekannt (keine Übersetzung): nichts folgern
    local pending = ns.Progress.Pending(step, ns.State.Player(), view.route.id, view.main)
    -- Steht im selben Schritt noch eine Abgabe aus, bietet der NPC die Folgequest erst danach an:
    -- dann lässt sich aus dem Angebot nichts schließen.
    for _, entry in ipairs(pending) do
        if entry.a[1] == "turnin" then return end
    end
    for _, entry in ipairs(pending) do
        local q = entry.a.q
        if entry.a[1] == "accept" and q and not offered[q] then
            ns.cdb.unavail[q] = true
            print(ns.PREFIX .. ns.F("Quest %s is not offered here, moving on.", ns.State.QuestTitle(q) or tostring(q)))
        end
    end
    ns.RequestUpdate()
end

local frame = CreateFrame("Frame")
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "QUEST_ACCEPTED", "QUEST_TURNED_IN", "QUEST_REMOVED", "QUEST_LOG_UPDATE",
    "PLAYER_LEVEL_UP", "PLAYER_XP_UPDATE", "BAG_UPDATE_DELAYED", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA",
    "ZONE_CHANGED_INDOORS", "SPELLS_CHANGED", "HEARTHSTONE_BOUND", "UI_INFO_MESSAGE",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED", "GOSSIP_SHOW", "GET_ITEM_INFO_RECEIVED", "QUEST_WATCH_UPDATE",
}

ns.On("READY", function()
    -- Nicht jedes Ereignis gibt es in jedem Client: fehlende werden gemerkt (/ultima status), nicht verschwiegen.
    ns.missingEvents = {}
    for _, event in ipairs(EVENTS) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then ns.missingEvents[#ns.missingEvents + 1] = event end
    end
    -- Questlog-Änderungen nur des Spielers (sonst feuert jedes Gruppenmitglied eine Auswertung)
    if not pcall(frame.RegisterUnitEvent, frame, "UNIT_QUEST_LOG_CHANGED", "player") then
        ns.missingEvents[#ns.missingEvents + 1] = "UNIT_QUEST_LOG_CHANGED"
    end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end)

local function OnEvent(_, event, a1, a2, a3)
    if event == "PLAYER_ENTERING_WORLD" then
        ns.EnsureFonts()
        C_Timer.After(3, function() ns.Guard("Fonts", ns.EnsureFonts) end)
        if not LoadRoutes() then return end
        -- Rückfall, falls QUEST_LOG_UPDATE ausbleibt: nach 5 Sekunden gilt das Questlog als geladen
        C_Timer.After(5, function()
            if not ns.questsReady then
                ns.questsReady = true
                ns.RequestUpdate()
            end
        end)
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not ns.IsSecret(a3) and a3 and HEARTHSTONE[a3] then Mark("hs") end
        return
    elseif event == "HEARTHSTONE_BOUND" then
        Mark("home")
        return
    elseif event == "UI_INFO_MESSAGE" then
        if a2 == ERR_NEWTAXIPATH then Mark("fp") end
        return
    elseif event == "GOSSIP_SHOW" then
        CheckOffers()
        return
    elseif event == "QUEST_LOG_UPDATE" and not ns.questsReady then
        ns.questsReady = true
    elseif event == "PLAYER_LEVEL_UP" then
        -- Neues Level: zuvor nicht angebotene Quests erneut versuchen
        ns.cdb.unavail = {}
    elseif event == "BAG_UPDATE_DELAYED" or event == "GET_ITEM_INFO_RECEIVED" then
        ns.Bonus.BagsChanged()
    elseif event == "PLAYER_CONTROL_LOST" then
        C_Timer.After(1, function() onTaxi = UnitOnTaxi("player") end)
        return
    elseif event == "PLAYER_CONTROL_GAINED" then
        if onTaxi then
            onTaxi = false
            Mark("fly")
        end
    end
    ns.RequestUpdate()
end
frame:SetScript("OnEvent", function(...) ns.Guard("Event", OnEvent, ...) end)

-- Wegpunkte erreicht man ohne Ereignis, daher jede Sekunde pruefen.
C_Timer.NewTicker(1, function()
    if ns.routes and ns.view and ns.view.route then ns.RequestUpdate() end
end)
