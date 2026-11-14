-- Quest-Automatik: nimmt Quests der angezeigten Schritte an und gibt sie ab. Nur Quests, die die Route
-- gerade verlangt; alles andere bleibt dir überlassen. Umschalt gedrückt halten setzt die Automatik aus.
-- Belohnungen mit Auswahl (mehr als ein Gegenstand) wählt Ultima nie selbst.
-- Jede Entscheidung landet kurz im Protokoll ns.db.autoLog (die letzten 40 Zeilen, in den gespeicherten
-- Daten): damit lässt sich nachvollziehen, warum die Automatik bei einem NPC etwas tat oder nicht.
local _, ns = ...
local R, P, S = ns.Runner, ns.Progress, ns.State

local LOG_MAX = 40

local function Log(event, text)
    local db = ns.db
    if not db then return end
    db.autoLog = db.autoLog or {}
    local clock = (date or os.date)("%H:%M:%S")
    db.autoLog[#db.autoLog + 1] = clock .. " " .. event .. " " .. text
    while #db.autoLog > LOG_MAX do table.remove(db.autoLog, 1) end
end

local function Ids(set)
    local list = {}
    for q in pairs(set) do list[#list + 1] = tostring(q) end
    table.sort(list)
    return "[" .. table.concat(list, ",") .. "]"
end

-- Questname laut Routen-Daten, wenn das Spiel den Titel noch nicht kennt (Quest nie gesehen): "Accept X"
local function DataTitle(a)
    if not a.t then return nil end
    local stripped = a.t:gsub("^Accept%s+", ""):gsub("^Turn%s+in%s+", "")
    if stripped ~= a.t then return stripped end
    return nil
end

-- Quests der angezeigten Schritte: accept[q] = true, turnin[q] = true; names[q] = Titel (Spiel, sonst Daten)
local function Wanted()
    local accept, turnin, names = {}, {}, {}
    local view = ns.view
    if not (view and view.route) then return accept, turnin, names end
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            local a = entry.a
            if a.q and (a[1] == "accept" or a[1] == "turnin") then
                if a[1] == "accept" then accept[a.q] = true else turnin[a.q] = true end
                names[a.q] = names[a.q] or S.QuestTitle(a.q) or DataTitle(a)
            end
        end
    end
    return accept, turnin, names
end

local function Active()
    return ns.db and ns.db.autoQuest and not IsShiftKeyDown()
end

-- Gesprächsfenster mit Questliste (neue Art, mit Quest-IDs)
local function OnGossip()
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then
        Log("GOSSIP_SHOW", "ohne C_GossipInfo, nichts getan")
        return
    end
    local accept, turnin = Wanted()
    local active, available = {}, {}
    for _, info in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        active[#active + 1] = tostring(info.questID) .. (info.isComplete and "*" or "")
        if info.questID and turnin[info.questID] and info.isComplete and C_GossipInfo.SelectActiveQuest then
            Log("GOSSIP_SHOW", "Abgabe " .. info.questID)
            C_GossipInfo.SelectActiveQuest(info.questID)
            return
        end
    end
    for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        available[#available + 1] = tostring(info.questID)
        if info.questID and accept[info.questID] and C_GossipInfo.SelectAvailableQuest then
            Log("GOSSIP_SHOW", "Annahme " .. info.questID)
            C_GossipInfo.SelectAvailableQuest(info.questID)
            return
        end
    end
    Log("GOSSIP_SHOW", ("nichts: angeboten [%s], laufend [%s], Route will annehmen %s, abgeben %s"):format(
        table.concat(available, ","), table.concat(active, ","), Ids(accept), Ids(turnin)))
end

-- Begrüßungsfenster alter Art: nur Titel, Vergleich über den Questnamen (Spiel-Cache, sonst Routen-Daten)
local function OnGreeting()
    if not (GetNumActiveQuests and GetActiveTitle and GetNumAvailableQuests and GetAvailableTitle) then
        Log("QUEST_GREETING", "ohne Titel-Abfrage, nichts getan")
        return
    end
    local accept, turnin, names = Wanted()
    local function Titles(set)
        local t = {}
        for q in pairs(set) do
            if names[q] then t[names[q]] = q end
        end
        return t
    end
    local turninTitles, acceptTitles = Titles(turnin), Titles(accept)
    local seen = {}
    for i = 1, GetNumActiveQuests() do
        local title, complete = GetActiveTitle(i)
        seen[#seen + 1] = tostring(title)
        if title and turninTitles[title] and complete then
            Log("QUEST_GREETING", "Abgabe " .. title)
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, GetNumAvailableQuests() do
        local title = GetAvailableTitle(i)
        seen[#seen + 1] = tostring(title)
        if title and acceptTitles[title] then
            Log("QUEST_GREETING", "Annahme " .. title)
            SelectAvailableQuest(i)
            return
        end
    end
    Log("QUEST_GREETING", ("nichts: angeboten [%s], Route will annehmen %s, abgeben %s"):format(
        table.concat(seen, " / "), Ids(accept), Ids(turnin)))
end

local function OnDetail()
    local accept = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and accept[q] then
        Log("QUEST_DETAIL", "Annahme " .. q)
        AcceptQuest()
    else
        Log("QUEST_DETAIL", ("nichts: Quest %s, Route will annehmen %s"):format(tostring(q), Ids(accept)))
    end
end

local function OnProgress()
    local _, turnin = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and turnin[q] and IsQuestCompletable() then
        Log("QUEST_PROGRESS", "Abgabe " .. q)
        CompleteQuest()
    else
        Log("QUEST_PROGRESS", ("nichts: Quest %s, Route will abgeben %s"):format(tostring(q), Ids(turnin)))
    end
end

local function OnComplete()
    local _, turnin = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and turnin[q] and GetNumQuestChoices() <= 1 then
        Log("QUEST_COMPLETE", "Belohnung " .. q)
        GetQuestReward(1)
    else
        Log("QUEST_COMPLETE", ("nichts: Quest %s, Auswahl %s"):format(tostring(q), tostring(GetNumQuestChoices())))
    end
end

local HANDLERS = {
    GOSSIP_SHOW = OnGossip, QUEST_GREETING = OnGreeting, QUEST_DETAIL = OnDetail,
    QUEST_PROGRESS = OnProgress, QUEST_COMPLETE = OnComplete,
}

ns.On("READY", function()
    local frame = CreateFrame("Frame")
    for event in pairs(HANDLERS) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns.missingEvents = ns.missingEvents or {}
            ns.missingEvents[#ns.missingEvents + 1] = event
            Log("REGISTER", "Ereignis fehlt im Client: " .. event)
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        local handler = HANDLERS[event]
        if not handler then return end
        if not (ns.db and ns.db.autoQuest) then
            Log(event, "aus (Einstellung)")
        elseif IsShiftKeyDown() then
            Log(event, "pausiert (Umschalt)")
        else
            ns.Guard("Auto " .. event, handler)
        end
    end)
end)
