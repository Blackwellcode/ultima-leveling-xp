-- Fortschritt: ist eine Handlung erledigt, und gilt ein Schritt ueberhaupt für diesen Charakter?
local _, ns = ...
local P = {}
ns.Progress = P
local S = ns.State

-- Handlungen, die einen Schritt erst abschliessen, wenn sie erledigt sind.
P.BLOCKING = {
    accept = true, turnin = true, complete = true, collect = true, xp = true, train = true,
    hs = true, home = true, fly = true, fp = true, zone = true, subzone = true, abandon = true,
}
-- Reise-Handlungen: gelten auch als erledigt, wenn du das Ziel auf anderem Weg erreicht hast
-- (siehe Runner, "überholt"). Ein Ruhestein auf Abklingzeit darf die Route nie anhalten.
-- home zählt dazu: Ruhestein-Orte ohne Gebiets-ID lassen sich nur über das Ereignis erkennen; bist du schon
-- am nächsten Wegpunkt, hast du dich gegen das Binden entschieden (oder warst schon gebunden).
P.TRAVEL = { hs = true, fly = true, zone = true, subzone = true, fp = true, home = true }
local DEFAULT_RADIUS = 10 -- Yards

-------------------------------------------------------------------------------
-- Berufe entlang der Route (Erste Hilfe, Kochen, Angeln), je Charakter abschaltbar (ns.cdb.professions).
-- Die Guides haben für jeden Beruf zwei Wege: einen für "Beruf vorhanden" und einen für "Beruf fehlt"
-- (Duskwood: Wölfe töten mit Fleisch fürs Kochen oder ohne). Abgeschaltet heißt deshalb: Ultima rechnet
-- mit Stufe 0, als hättest du den Beruf nie gelernt. Zusätzlich fallen Schritte weg, die den Beruf
-- beibringen oder hochziehen (Lehrer, "Kochen auf 50 bringen"), solange sie keine Quest und keine
-- Reise enthalten. Lehrer-Zauber laut Routen-Daten: "Train Cooking" 2550, "Train First Aid" 3273,
-- "Train Journeyman First Aid" 3274, "Level First Aid to 80" 7934, "Train Fishing" 7734.
-------------------------------------------------------------------------------
P.PROFESSIONS = { "firstaid", "cooking", "fishing" }
local PROFESSION_TRAIN = { [2550] = "cooking", [3273] = "firstaid", [3274] = "firstaid", [7934] = "firstaid",
    [7734] = "fishing" }
local KEEPS_STEP = { accept = true, turnin = true, complete = true, zone = true, subzone = true, fly = true,
    fp = true, hs = true, home = true }

function P.ProfessionOff(name)
    local list = ns.cdb and ns.cdb.professions
    return list ~= nil and name ~= nil and list[name] == false
end

-- Schritt dient nur einem abgeschalteten Beruf (Lehrer besuchen, Beruf hochziehen)?
local function ProfessionOnly(step)
    local hit = false
    for _, a in ipairs(step.a) do
        local tag = a[1]
        if KEEPS_STEP[tag] then return false end
        if tag == "train" and P.ProfessionOff(PROFESSION_TRAIN[a.sp]) then hit = true end
        -- Ziel "Beruf auf Stufe X" oder Hochzieh-Schritt ("zeigen, solange unter X", X > 1)
        if tag == "skill" and P.ProfessionOff(a.name) and (not a.skip or (not a.rev and (a.lvl or 0) > 1)) then
            hit = true
        end
    end
    return hit
end

-- Quest beim Questgeber nicht im Angebot (Voraussetzung fehlt, Level zu niedrig): Annahme blockiert nicht.
-- Wird beim Gespräch mit dem Questgeber gesetzt (Live.lua) und bei Levelaufstieg geleert.
local function Unavailable(q)
    return ns.cdb and ns.cdb.unavail and ns.cdb.unavail[q] == true
end

local function Mark(routeId, si, ai)
    local m = ns.cdb and ns.cdb.marks[routeId]
    return m and m[si .. ":" .. ai]
end

-- Fuer Ereignisse ohne abfragbaren Zustand (Ruhestein, Flug, Flugpunkt): Handlung als erledigt merken.
function P.SetMark(routeId, si, ai)
    local marks = ns.cdb.marks
    marks[routeId] = marks[routeId] or {}
    marks[routeId][si .. ":" .. ai] = true
end

local function ContainsCI(haystack, needle)
    return needle and haystack ~= "" and haystack:lower():find(needle:lower(), 1, true) ~= nil
end

-- Erledigt-Pruefung je Handlung. ctx = { routeId, si, ai } für Ereignis-Marken.
function P.Done(a, ctx)
    local tag = a[1]
    if tag == "accept" then return S.OnQuest(a.q) or S.TurnedIn(a.q) or Unavailable(a.q) end
    -- Abgabe einer Quest, die nicht im Log ist: nie angenommen oder abgebrochen, nichts abzugeben
    if tag == "turnin" then return S.TurnedIn(a.q) or not S.OnQuest(a.q) end
    if tag == "complete" then
        if S.TurnedIn(a.q) then return true end
        if not S.OnQuest(a.q) then return true end -- Quest fehlt: nicht blockieren, Annahme-Schritt zeigt es
        -- Quest als Ganzes fertig: dann ist auch jedes einzelne Ziel fertig. Bei Eskorten und
        -- Ereignis-Zielen meldet der Client das einzelne Ziel teils weiter als offen (0/1).
        if S.QuestComplete(a.q) then return true end
        if a.o then
            local finished = S.Objective(a.q, a.o)
            if finished ~= nil then return finished end
        end
        return S.QuestComplete(a.q)
    end
    if tag == "collect" then
        if a.q and (S.TurnedIn(a.q) or not S.OnQuest(a.q)) then return true end
        return S.ItemCount(a.i) >= (a.n or 1)
    end
    if tag == "xp" then
        local level = S.Level()
        if not a.lvl then return true end
        if level >= a.lvl then
            if a.pct and level == a.lvl then
                local xp, max = S.XP()
                return max > 0 and xp / max >= a.pct
            end
            return true
        end
        if a.away and level == a.lvl - 1 then
            local xp, max = S.XP()
            return max - xp <= a.away
        end
        return false
    end
    if tag == "train" then return S.KnowsSpell(a.sp) end
    if tag == "abandon" then return not S.OnQuest(a.q) end
    if tag == "zone" then
        if a.zm then return S.InMap(a.zm) end
        return ContainsCI(S.ZoneText(), a.to)
    end
    if tag == "fly" then
        return (ctx and Mark(ctx.routeId, ctx.si, ctx.ai)) or ContainsCI(S.SubzoneText(), a.to)
            or ContainsCI(S.ZoneText(), a.to)
    end
    if tag == "subzone" then
        local name = S.AreaName(a.area)
        return name ~= nil and S.SubzoneText() == name
    end
    if tag == "home" then
        if a.area and S.BoundTo(a.area) then return true end
        return ctx and Mark(ctx.routeId, ctx.si, ctx.ai) or false
    end
    if tag == "fp" then
        -- schon bekannt (beim Flugmeister gemerkt): nichts zu holen
        if a.to and ns.KnowsTaxi and ns.KnowsTaxi(a.to) then return true end
        return ctx and Mark(ctx.routeId, ctx.si, ctx.ai) or false
    end
    if tag == "hs" then
        return ctx and Mark(ctx.routeId, ctx.si, ctx.ai) or false
    end
    if tag == "goto" then
        local d = S.Distance(a)
        return d ~= nil and d <= (a.r and a.r > 0 and a.r or DEFAULT_RADIUS)
    end
    return true
end

-- Ueberspring-Bedingungen eines Schritts. true = Schritt gilt nicht (wird uebersprungen).
local function SkipByAction(a)
    local tag = a[1]
    if tag == "isOnQuest" then
        for _, q in ipairs(a.ids) do if S.OnQuest(q) then return false end end
        return true
    end
    if tag == "isQuestTurnedIn" then
        for _, q in ipairs(a.ids) do if S.TurnedIn(q) then return false end end
        return true
    end
    if tag == "isQuestAvailable" then
        for _, q in ipairs(a.ids) do if S.TurnedIn(q) or S.OnQuest(q) then return true end end
        return false
    end
    if tag == "isQuestComplete" then
        for _, q in ipairs(a.ids) do if S.OnQuest(q) and S.QuestComplete(q) then return false end end
        return true
    end
    if tag == "isNotOnQuest" then
        for q in tostring(a.raw or ""):gmatch("%d+") do if S.OnQuest(tonumber(q)) then return true end end
        return false
    end
    if tag == "isQuestNotComplete" then
        for q in tostring(a.raw or ""):gmatch("%d+") do
            q = tonumber(q)
            if S.OnQuest(q) and S.QuestComplete(q) then return true end
        end
        return false
    end
    if tag == "maxlevel" then
        local n = tonumber(tostring(a.raw or ""):match("%d+"))
        return n ~= nil and S.Level() > n
    end
    if tag == "itemcount" then return S.ItemCount(a.i) < (a.n or 1) end
    if tag == "skill" and a.skip and a.lvl then
        -- Schritt entfällt, sobald die Bedingung erfüllt ist ("Kochen 10 farmen" bei Kochen 38)
        -- abgeschalteter Beruf zählt als nie gelernt (Stufe 0), siehe P.ProfessionOff
        local level = P.ProfessionOff(a.name) and 0 or S.SkillLevel(a.name)
        if level == nil then return false end -- Stufe unbekannt: Schritt lieber zeigen
        return (level >= a.lvl) ~= (a.rev == true)
    end
    if tag == "zoneskip" then
        local inZone
        if a.zm then inZone = S.InMap(a.zm) else inZone = ContainsCI(S.ZoneText(), a.to) end
        if a.flag and tonumber(a.flag) and tonumber(a.flag) % 2 == 1 then return not inZone end
        return inZone
    end
    if tag == "dungeon" then return not (ns.db and (ns.db.dungeonSteps or ns.db.dungeons[a.to])) end
    return false
end

-- Gilt der Schritt für diesen Charakter und Zustand?
function P.Applies(step, player)
    if not ns.Cond.Eval(step.c, player) then return false end
    if ProfessionOnly(step) then return false end
    for _, a in ipairs(step.a) do
        if ns.Cond.Eval(a.c, player) and SkipByAction(a) then return false end
    end
    return true
end

-- Handlungen, die für diesen Charakter gelten.
function P.Actions(step, player)
    local list = {}
    for i, a in ipairs(step.a) do
        if ns.Cond.Eval(a.c, player) then list[#list + 1] = { a = a, i = i } end
    end
    return list
end

-- Schritt erledigt? Liefert erledigt, hatBlockierendeHandlung.
function P.StepDone(step, player, routeId, si)
    local blocking = false
    for _, entry in ipairs(P.Actions(step, player)) do
        local a = entry.a
        if P.BLOCKING[a[1]] then
            blocking = true
            if not P.Done(a, { routeId = routeId, si = si, ai = entry.i }) then return false, true end
        end
    end
    return blocking, blocking
end

-- Offene blockierende Handlungen eines Schritts: Liste von { a, i }.
function P.Pending(step, player, routeId, si)
    local list = {}
    for _, entry in ipairs(P.Actions(step, player)) do
        if P.BLOCKING[entry.a[1]] and not P.Done(entry.a, { routeId = routeId, si = si, ai = entry.i }) then
            list[#list + 1] = entry
        end
    end
    return list
end

-- Hängt der Schritt an einer Abgabe, deren Quest im Log steht, aber noch nicht fertig ist?
-- Dann liefert die Funktion die Quest-ID. Annahmen im selben Schritt hängen meist an dieser Abgabe
-- (Folgequest) und zählen mit; jede andere offene Handlung macht den Schritt zu einem normalen Schritt.
function P.WaitsOnQuest(pending)
    local q
    for _, entry in ipairs(pending) do
        local a = entry.a
        if a[1] == "turnin" and S.OnQuest(a.q) and S.HasOpenObjectives(a.q) then
            q = q or a.q
        elseif a[1] ~= "accept" then
            return nil
        end
    end
    return q
end

-- Folgequest einer nie begonnenen Reihe? Offen sind nur Annahmen, und der Schritt gibt eine Quest ab,
-- die weder im Log steht noch je abgegeben wurde. Dann bietet der NPC die Folgequest nicht an.
function P.ChainNotStarted(step, player, pending)
    if #pending == 0 then return false end
    for _, entry in ipairs(pending) do
        if entry.a[1] ~= "accept" then return false end
    end
    for _, entry in ipairs(P.Actions(step, player)) do
        local a = entry.a
        if a[1] == "turnin" and a.q and not S.OnQuest(a.q) and not S.TurnedIn(a.q) then return true end
    end
    return false
end

-- Sind nur noch Reise-Handlungen offen (Ruhestein, Flug, Zone, Flugpunkt)?
function P.OnlyTravel(pending)
    if #pending == 0 then return false end
    for _, entry in ipairs(pending) do
        if not P.TRAVEL[entry.a[1]] then return false end
    end
    return true
end
