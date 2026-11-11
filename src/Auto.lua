-- Quest-Automatik: nimmt Quests der angezeigten Schritte an und gibt sie ab. Nur Quests, die die Route
-- gerade verlangt; alles andere bleibt dir überlassen. Umschalt gedrückt halten setzt die Automatik aus.
-- Belohnungen mit Auswahl (mehr als ein Gegenstand) wählt Ultima nie selbst.
local _, ns = ...
local R, P, S = ns.Runner, ns.Progress, ns.State

-- Quests der angezeigten Schritte: accept[q] = true, turnin[q] = true
local function Wanted()
    local accept, turnin = {}, {}
    local view = ns.view
    if not (view and view.route) then return accept, turnin end
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            local a = entry.a
            if a.q and a[1] == "accept" then accept[a.q] = true end
            if a.q and a[1] == "turnin" then turnin[a.q] = true end
        end
    end
    return accept, turnin
end

local function Active()
    return ns.db and ns.db.autoQuest and not IsShiftKeyDown()
end

-- Gesprächsfenster mit Questliste (neue Art, mit Quest-IDs)
local function OnGossip()
    if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then return end
    local accept, turnin = Wanted()
    for _, info in ipairs(C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}) do
        if info.questID and turnin[info.questID] and info.isComplete and C_GossipInfo.SelectActiveQuest then
            C_GossipInfo.SelectActiveQuest(info.questID)
            return
        end
    end
    for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
        if info.questID and accept[info.questID] and C_GossipInfo.SelectAvailableQuest then
            C_GossipInfo.SelectAvailableQuest(info.questID)
            return
        end
    end
end

-- Begrüßungsfenster alter Art: nur Titel, Vergleich über den Questnamen in Client-Sprache
local function OnGreeting()
    if not (GetNumActiveQuests and GetActiveTitle and GetNumAvailableQuests and GetAvailableTitle) then return end
    local accept, turnin = Wanted()
    local function Titles(set)
        local t = {}
        for q in pairs(set) do
            local title = S.QuestTitle(q)
            if title then t[title] = true end
        end
        return t
    end
    local turninTitles, acceptTitles = Titles(turnin), Titles(accept)
    for i = 1, GetNumActiveQuests() do
        local title, complete = GetActiveTitle(i)
        if title and turninTitles[title] and complete then
            SelectActiveQuest(i)
            return
        end
    end
    for i = 1, GetNumAvailableQuests() do
        local title = GetAvailableTitle(i)
        if title and acceptTitles[title] then
            SelectAvailableQuest(i)
            return
        end
    end
end

local function OnDetail()
    local accept = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and accept[q] then AcceptQuest() end
end

local function OnProgress()
    local _, turnin = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and turnin[q] and IsQuestCompletable() then CompleteQuest() end
end

local function OnComplete()
    local _, turnin = Wanted()
    local q = GetQuestID and GetQuestID()
    if q and turnin[q] and GetNumQuestChoices() <= 1 then GetQuestReward(1) end
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
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        local handler = HANDLERS[event]
        if handler and Active() then ns.Guard("Auto " .. event, handler) end
    end)
end)
