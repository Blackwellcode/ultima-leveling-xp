-- Helfer rund um den aktuellen Schritt:
--   Ziel-Knopf   geschützter Knopf, der den NPC oder Gegner des Schritts anvisiert (/targetexact)
--   Lehrer       kauft beim Lehrer genau die Zauber, die der Schritt verlangt
--   Flugmeister  merkt sich bekannte Flugpunkte und wählt das Flugziel des Schritts
-- Lehrer und Flug gehören zur Automatik (/ultima quests schaltet sie ab, Umschalt setzt sie aus).
local _, ns = ...
local R, P, S = ns.Runner, ns.Progress, ns.State

-- Offene Handlungen einer Art in den angezeigten Schritten
local function PendingOf(tag)
    local list = {}
    local view = ns.view
    if not (view and view.route) then return list end
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Pending(ref.route.s[ref.si], player, ref.route.id, ref.si)) do
            if entry.a[1] == tag then list[#list + 1] = entry.a end
        end
    end
    return list
end

-------------------------------------------------------------------------------
-- Ziel-Knopf
-------------------------------------------------------------------------------
local button, shownMacro, wantedMacro, wantedNames

-- Namen zum Anvisieren: Ansprechpartner, sonst Gegner des Haupt-Schritts (höchstens 3), in Client-Sprache
local function StepNames(view)
    if not (view and view.route) then return nil end
    local player = S.Player()
    local names, seen = {}, {}
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            local a = entry.a
            if (a[1] == "target" or a[1] == "mob" or a[1] == "unitscan") and a.names then
                for _, n in ipairs(a.names) do
                    local name = ns.NPC(n)
                    if not seen[name] and #names < 3 then
                        seen[name] = true
                        names[#names + 1] = name
                    end
                end
            end
        end
    end
    return #names > 0 and names or nil
end

local function ApplyTarget()
    if not button or InCombatLockdown() then return end -- im Kampf gesperrt, wird danach nachgeholt
    if wantedMacro == shownMacro then return end
    shownMacro = wantedMacro
    if shownMacro then
        button:SetAttribute("type", "macro")
        button:SetAttribute("macrotext", shownMacro)
        button.names = wantedNames
        button:Show()
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("macrotext", nil)
        button:Hide()
    end
end

local function BuildTarget()
    if not ns.panel then return end
    button = CreateFrame("Button", "UltimaTargetButton", ns.panel, "SecureActionButtonTemplate")
    button:SetSize(40, 40)
    button:SetPoint("TOPRIGHT", ns.panel, "TOPLEFT", -8, -62) -- unter dem Item-Knopf
    button:RegisterForClicks("AnyUp", "AnyDown")
    ns.Round(button, "round", ns.Theme.radius.control, ns.COLORS.panel, "BACKGROUND")
    ns.Round(button, "ring", ns.Theme.radius.control, ns.COLORS.cardBorder, "BORDER")
    button.icon = ns.Icon(button, 28)
    button.icon:SetPoint("CENTER")
    button.icon:SetTexture("Interface/Icons/Ability_Hunter_SniperShot")
    button:SetScript("OnEnter", function(self)
        if not self.names then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.F("Target: %s", table.concat(self.names, ", ")), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:SetScript("OnEvent", function() ns.Guard("Target", ApplyTarget) end)
end

ns.On("READY", BuildTarget)
ns.On("VIEW", function(view)
    wantedNames = ns.db.buttons.target and StepNames(view) or nil
    if wantedNames then
        local lines = { "/cleartarget" }
        for _, n in ipairs(wantedNames) do lines[#lines + 1] = "/targetexact " .. n end
        wantedMacro = table.concat(lines, "\n")
    else
        wantedMacro = nil
    end
    ns.Guard("Target", ApplyTarget)
end)

-------------------------------------------------------------------------------
-- Lehrer: verlangte Zauber kaufen
-------------------------------------------------------------------------------
local function OnTrainer()
    if not (GetNumTrainerServices and GetTrainerServiceInfo and BuyTrainerService) then return end
    local wanted = {}
    for _, a in ipairs(PendingOf("train")) do
        local name = a.sp and S.SpellName(a.sp)
        if name then wanted[name] = true end
    end
    if not next(wanted) then return end
    -- von hinten nach vorn: beim Kauf rutschen die Einträge darunter nach
    for i = GetNumTrainerServices(), 1, -1 do
        local name, _, category = GetTrainerServiceInfo(i)
        if name and wanted[name] and category == "available" then BuyTrainerService(i) end
    end
end

-------------------------------------------------------------------------------
-- Flugmeister: bekannte Flugpunkte merken, Flugziel des Schritts wählen
-------------------------------------------------------------------------------
local function Contains(haystack, needle)
    return haystack and needle and haystack:lower():find(needle:lower(), 1, true) ~= nil
end

-- Knoten-IDs je Platz auf der Flugkarte. Die IDs sind in jeder Client-Sprache gleich und passen zu
-- den Flugdaten; fehlt die Abfrage im Client, bleibt es beim Namen.
local function SlotIds()
    local ids = {}
    if not (C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_Map and C_Map.GetBestMapForUnit) then return ids end
    local map = C_Map.GetBestMapForUnit("player")
    for _, node in ipairs(map and C_TaxiMap.GetAllTaxiNodes(map) or {}) do
        if node.slotIndex and node.nodeID then ids[node.slotIndex] = node.nodeID end
    end
    return ids
end

-- Flugpunkte der eigenen Fraktion, deren englischer Name den gesuchten Text enthält: { [Knoten-ID] = true }
local function NodesNamed(text)
    local set = {}
    for id, node in pairs(ns.Travel.Flights()) do
        if Contains(node.n, text) then set[id] = true end
    end
    return set
end

local function OnTaxi()
    if not (NumTaxiNodes and TaxiNodeName and TaxiNodeGetType) then return end
    local ids = SlotIds()
    local reachable = {}
    for i = 1, NumTaxiNodes() do
        local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
        if name and (kind == "CURRENT" or kind == "REACHABLE") then
            ns.cdb.taxi[name] = true
            if ids[i] then ns.cdb.taxiIds[ids[i]] = true end
            if kind == "REACHABLE" then reachable[#reachable + 1] = { i = i, name = name, id = ids[i] } end
        end
    end
    ns.Travel.knowledge = ns.Travel.knowledge + 1 -- gemerkte Reisepläne sind damit überholt
    ns.RequestUpdate()
    if not (ns.db.autoFly and not IsShiftKeyDown() and TakeTaxiNode) then return end
    -- Flugziel aus dem Reiseplaner (Flug spart Laufweg), sonst das Ziel eines fly-Schritts der Route
    local planned, plannedId = ns.Travel.flyTarget, ns.Travel.flyTargetId
    if planned then
        for _, node in ipairs(reachable) do
            if (node.id and node.id == plannedId) or node.name == planned then
                print(ns.PREFIX .. ns.F("Fly to %s", node.name))
                TakeTaxiNode(node.i)
                return
            end
        end
    end
    for _, a in ipairs(PendingOf("fly")) do
        local wanted = NodesNamed(a.to)
        for _, node in ipairs(reachable) do
            if (node.id and wanted[node.id]) or Contains(node.name, a.to) then
                print(ns.PREFIX .. ns.F("Fly to %s", node.name))
                TakeTaxiNode(node.i)
                return
            end
        end
    end
end

-- Kennt der Charakter einen Flugpunkt, dessen Name den gesuchten enthält? (für fp-Schritte)
function ns.KnowsTaxi(name)
    for id in pairs(NodesNamed(name)) do
        if ns.cdb.taxiIds[id] then return true end
    end
    for known in pairs(ns.cdb.taxi) do
        if Contains(known, name) then return true end
    end
    return false
end

-- Kennt der Charakter diesen Flugpunkt der Flugdaten? Erst über die ID, dann über den Namen.
function ns.KnowsNode(id, node)
    return ns.cdb.taxiIds[id] == true or ns.cdb.taxi[node.n] == true
end

ns.On("READY", function()
    local frame = CreateFrame("Frame")
    local handlers = { TRAINER_SHOW = function() if ns.db.autoTrain and not IsShiftKeyDown() then OnTrainer() end end,
        TAXIMAP_OPENED = OnTaxi }
    for event in pairs(handlers) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns.missingEvents = ns.missingEvents or {}
            ns.missingEvents[#ns.missingEvents + 1] = event
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        local handler = handlers[event]
        if handler then ns.Guard("Assist " .. event, handler) end
    end)
end)
