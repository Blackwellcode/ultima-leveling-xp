-- Runner: waehlt die Route, findet den aktuellen Schritt und wechselt zur Folge-Route.
--
-- Ein Schritt mit blockierenden Handlungen (annehmen, abgeben, Ziele, ...) ist "Haupt-Schritt".
-- Schritte ohne solche Handlungen (nur Weg, Hinweis, Händler) sind "Vorlauf": sie werden mit dem
-- naechsten offenen Haupt-Schritt angezeigt und blockieren nie. So bleibt die Route nicht an einem
-- Wegpunkt haengen, an dem du schon vorbei bist.
local _, ns = ...
local R = {}
ns.Runner = R
local P, S = ns.Progress, ns.State

local OPTIONAL_LOOKAHEAD = 15
local byId

local function FactionLetter(faction)
    return faction == "Alliance" and "A" or faction == "Horde" and "H" or "B"
end

function R.Index()
    if byId then return byId end
    byId = {}
    for _, r in ipairs(ns.routes or {}) do byId[r.id] = r end
    return byId
end

function R.Get(id) return R.Index()[id] end

-- Nach dem Nachladen oder Ergaenzen von Routen den Index neu aufbauen.
local sources -- Quest-ID -> { { route, si }, ... } (Schritte mit complete/collect dieser Quest)
function R.Reindex() byId, sources = nil, nil end

-------------------------------------------------------------------------------
-- Routenwahl (Locator)
-------------------------------------------------------------------------------
-- Alle Routen, die für diesen Charakter gelten, nach Startlevel sortiert.
function R.Candidates(player, kind)
    local f = FactionLetter(player.faction)
    local list = {}
    for _, r in ipairs(ns.routes or {}) do
        if (r.f == f or r.f == "B") and r.k == kind and r.lo and r.hi
            and (not r.df or ns.Cond.Eval(r.df, player)) then
            list[#list + 1] = r
        end
    end
    table.sort(list, function(a, b)
        if a.lo ~= b.lo then return a.lo < b.lo end
        if (a.era and 1 or 0) ~= (b.era and 1 or 0) then return not a.era end
        return a.n < b.n
    end)
    return list
end

-- Beste Route für das Level: die frueheste noch nicht abgeschlossene Route, deren Bereich das Level
-- enthaelt. Forever-eigene Routen vor Classic-Routen. So bleibt die Reihenfolge der Kette erhalten
-- (Westfall vor Darkshore), und bereits erledigte Routen werden uebersprungen.
-- Wie viele Quests einer Route sind für diesen Charakter noch zu holen (weder im Log noch abgegeben)?
-- Maß dafür, ob sich eine Vorgänger-Route noch lohnt; Reise- und Trainer-Schritte zählen nicht.
local PREDECESSOR_MIN = 3
function R.OpenQuests(route, player)
    local open, seen = 0, {}
    for _, s in ipairs(route.s) do
        if ns.Cond.Eval(s.c, player) then
            for _, a in ipairs(s.a) do
                if a[1] == "accept" and a.q and not seen[a.q] and ns.Cond.Eval(a.c, player) then
                    seen[a.q] = true
                    if not S.OnQuest(a.q) and not S.TurnedIn(a.q) then open = open + 1 end
                end
            end
        end
    end
    return open
end

function R.FindRoute(player, kind)
    kind = kind or (ns.db and ns.db.routeKind) or "route"
    local fallback
    -- Erst Routen, in denen das Level echt innen liegt (am Bereichsende lohnt die Route kaum noch),
    -- dann Routen, an deren Ende du stehst.
    for _, inside in ipairs({ true, false }) do
        for _, pass in ipairs({ "forever", "era" }) do
            for _, r in ipairs(R.Candidates(player, kind)) do
                local upper
                if inside then upper = player.level < r.hi else upper = player.level <= r.hi end
                local fits = r.lo <= player.level and upper
                if (pass == "forever") == (not r.era) and fits then
                    fallback = fallback or r
                    if not R.Evaluate(r.id).finished then
                        -- Vorgänger zuerst: führt eine noch unfertige Route in diese hinein und passt dein
                        -- Level noch in ihren Bereich, spielst du erst die zu Ende. Sonst fehlen dir ihre
                        -- Level und Quests, und die Folge-Route schickt dich zu viel zu starken Gegnern.
                        for _, p in ipairs(ns.db.predecessorFirst and R.Candidates(player, kind) or {}) do
                            if p.id ~= r.id and p.lo <= player.level and player.level <= p.hi then
                                for _, nx in ipairs(p.nx or {}) do
                                    if nx.id == r.id and ns.Cond.Eval(nx.c, player) and R.OpenQuests(p, player) >= PREDECESSOR_MIN then
                                        return p
                                    end
                                end
                            end
                        end
                        return r
                    end
                end
            end
        end
    end
    if not fallback and kind ~= "route" then return R.FindRoute(player, "route") end
    return fallback
end

-------------------------------------------------------------------------------
-- Auswertung
-------------------------------------------------------------------------------
local function LabelIndex(route, label)
    route.labels = route.labels or {}
    if route.labels[label] == nil then
        route.labels[label] = false
        for i, s in ipairs(route.s) do if s.lb == label then route.labels[label] = i break end end
    end
    return route.labels[label] or nil
end

-------------------------------------------------------------------------------
-- Nachholen: Quellen für Questziele aus allen Routen
-------------------------------------------------------------------------------
local function FirstGoto(step)
    for _, a in ipairs(step.a) do
        if a[1] == "goto" then return a end
    end
end

function R.QuestSources(q)
    if not sources then
        sources = {}
        for _, r in ipairs(ns.routes or {}) do
            for si, s in ipairs(r.s) do
                for _, a in ipairs(s.a) do
                    if (a[1] == "complete" or a[1] == "collect") and a.q then
                        local list = sources[a.q] or {}
                        sources[a.q] = list
                        if list[#list] == nil or list[#list].route ~= r or list[#list].si ~= si then
                            list[#list + 1] = { route = r, si = si }
                        end
                    end
                end
            end
        end
    end
    return sources[q] or {}
end

-- Bester offener Schritt aus irgendeiner Route, der die Ziele von Quest q erledigt.
-- Nur Quellen in derselben Zone wie der hängende Schritt: so holst du nach, was am Weg liegt,
-- statt quer über den Kontinent geschickt zu werden.
local function CatchUp(q, route, step, player)
    local here = FirstGoto(step)
    local zone = here and here.m
    local best, bestScore
    for _, src in ipairs(R.QuestSources(q)) do
        local s = src.route.s[src.si]
        local g = FirstGoto(s)
        if g and zone and g.m == zone and P.Applies(s, player)
            and not P.StepDone(s, player, src.route.id, src.si) then
            local score = 0
            if src.route.k == route.k then score = score + 2 end
            if src.route.f == route.f then score = score + 1 end
            if not bestScore or score > bestScore then best, bestScore = src, score end
        end
    end
    return best
end

-- Ergebnis: { route, main = Index, lead = {Index...}, sticky = {...}, with = {...}, finished = bool,
--   catchup = { route, si, q } (Nachhol-Schritt vor dem Haupt-Schritt),
--   open = { Index... } (zurückgestellte Abgaben, die jetzt möglich sind), waiting = Anzahl zurückgestellt }
-- routeId: optional eine andere als die aktive Route pruefen (für die Routenwahl).
local OVERTAKE_LOOKAHEAD = 6
local OVERTAKE_RADIUS = 60 -- Yards

function R.Evaluate(routeId)
    local id = routeId or ns.cdb.route
    local route = id and R.Get(id)
    local view = { route = route, lead = {}, sticky = {}, with = {}, open = {}, waiting = 0 }
    if not route then return view end
    local player = S.Player()
    local manual = ns.cdb.manual[route.id] or {}
    local steps = route.s
    local doneAt = {}
    local active = route.id == ns.cdb.route
    -- Erst wenn das Questlog geladen ist, darf die Auswertung Zustand schreiben (Zeiger, Zurückgestellt).
    local ready = ns.questsReady ~= false
    ns.cdb.open = ns.cdb.open or {}
    local open = ns.cdb.open[route.id] or {}

    local function IsDone(si)
        if doneAt[si] == nil then
            local s = steps[si]
            if manual[si] or not P.Applies(s, player) then
                doneAt[si] = true
            else
                local done = P.StepDone(s, player, route.id, si)
                doneAt[si] = done and true or false
            end
        end
        return doneAt[si]
    end

    local function Blocking(s)
        for _, entry in ipairs(P.Actions(s, player)) do
            if P.BLOCKING[entry.a[1]] then return true end
        end
        return false
    end

    -- Ist irgendein spaeterer Haupt-Schritt schon erledigt? Dann gilt ein optionaler Schritt als verpasst.
    local function PassedOptional(si)
        for j = si + 1, math.min(#steps, si + OPTIONAL_LOOKAHEAD) do
            local s = steps[j]
            if not s.o and P.Applies(s, player) and Blocking(s) and IsDone(j) and not manual[j] then
                return true
            end
        end
        return false
    end

    -- Reise-Schritt überholt? Du stehst schon an einem späteren Wegpunkt: dann bist du angekommen,
    -- egal ob per Ruhestein, Flug, Boot oder zu Fuß. Nur der Ort zählt, nicht der Questzustand
    -- (eine früher angenommene Quest sagt nichts darüber, wo du gerade bist).
    local function Overtaken(si)
        for j = si + 1, math.min(#steps, si + OVERTAKE_LOOKAHEAD) do
            local s = steps[j]
            if P.Applies(s, player) then
                for _, entry in ipairs(P.Actions(s, player)) do
                    local a = entry.a
                    if a[1] == "goto" then
                        local d = S.Distance(a)
                        if d and d <= math.max(a.r or 0, OVERTAKE_RADIUS) then return true end
                    end
                end
            end
        end
        return false
    end

    -- Zurückgestellte Abgaben: erledigt -> vergessen; jetzt abgebbar -> anzeigen; sonst weiter warten.
    for si in pairs(open) do
        local s = steps[si]
        if not s or IsDone(si) then
            if ready and active then open[si] = nil end
        else
            local pending = P.Pending(s, player, route.id, si)
            if P.WaitsOnQuest(pending) then
                view.waiting = view.waiting + 1
            else
                view.open[#view.open + 1] = si
            end
        end
    end
    table.sort(view.open)

    -- Fortschrittszeiger: Schritte vor dem Zeiger gelten als erledigt, auch wenn sich der Spielzustand
    -- zurueckdreht (Quest abgebrochen, Items verbraucht). Er läuft nur vorwaerts, ausser per "Zurück".
    local start = active and ns.cdb.pointer[route.id] or 1
    for si = start, #steps do
        local s = steps[si]
        if not manual[si] and not open[si] and P.Applies(s, player) then
            if Blocking(s) then
                local pending = (not IsDone(si)) and P.Pending(s, player, route.id, si) or nil
                local waitsOn = pending and P.WaitsOnQuest(pending)
                if not pending then
                    view.lead = {}
                elseif s.cw then
                    view.with[#view.with + 1] = si
                elseif s.st then
                    view.sticky[#view.sticky + 1] = si
                elseif s.o and PassedOptional(si) then
                    -- verpasst, weiter
                elseif P.OnlyTravel(pending) and Overtaken(si) then
                    -- schon am Ziel der Reise, weiter
                    view.lead = {}
                elseif ready and P.ChainNotStarted(s, player, pending) then
                    -- Folgequest einer Reihe, die du nie angefangen hast: gibt es nicht, weiter
                    view.lead = {}
                elseif waitsOn then
                    -- Abgabe, deren Quest noch nicht fertig ist: Ziel in dieser Zone nachholen,
                    -- sonst zurückstellen und mit der Route weitermachen.
                    local src = CatchUp(waitsOn, route, s, player)
                    if src then
                        view.catchup = { route = src.route, si = src.si, q = waitsOn }
                        view.main = si
                        break
                    elseif active and ready then
                        open[si] = waitsOn
                        ns.cdb.open[route.id] = open
                        view.waiting = view.waiting + 1
                    else
                        view.main = si
                        break
                    end
                else
                    view.main = si
                    break
                end
            else
                -- Vorlauf: Weg oder Hinweis. Erreichte Wegpunkte fallen heraus.
                local reached = false
                for _, entry in ipairs(P.Actions(s, player)) do
                    if entry.a[1] == "goto" and P.Done(entry.a) then reached = true end
                end
                if not reached then view.lead[#view.lead + 1] = si end
            end
        end
    end

    -- "erledigt mit"-Schritte nur, solange ihr Ziel noch nicht vorbei ist
    if view.main then
        local keep = {}
        for _, si in ipairs(view.with) do
            local cw = steps[si].cw
            local target = cw == "next" and si + 1 or LabelIndex(route, cw)
            if not target or target >= view.main then keep[#keep + 1] = si end
        end
        view.with = keep
    end
    -- Fertig erst, wenn auch nichts mehr zurückgestellt ist: sonst wechselt die Route und die
    -- geparkten Abgaben tauchen nie wieder auf.
    view.finished = view.main == nil and #view.sticky == 0 and #view.open == 0
    if active and ready and view.main then ns.cdb.pointer[route.id] = view.main end
    return view
end

-------------------------------------------------------------------------------
-- Steuerung
-------------------------------------------------------------------------------
function R.Load(id)
    if not R.Get(id) then return false end
    ns.cdb.route = id
    return true
end

-- Folge-Route laden, wenn die aktuelle fertig ist. Liefert die neue ID oder nil.
function R.Advance(view)
    if not (view and view.finished and view.route) then return nil end
    local player = S.Player()
    for _, nx in ipairs(view.route.nx or {}) do
        if R.Get(nx.id) and ns.Cond.Eval(nx.c, player) then
            R.Load(nx.id)
            return nx.id
        end
    end
    local best = R.FindRoute(player)
    if best and best.id ~= view.route.id then
        R.Load(best.id)
        return best.id
    end
    return nil
end

-- Waehlt eine Route, falls keine aktiv ist oder die aktive nicht mehr zum Level passt.
function R.AutoSelect(force)
    local player = S.Player()
    local current = ns.cdb.route and R.Get(ns.cdb.route)
    if current and not force and current.hi and player.level <= current.hi + 1 then return current.id end
    local best = R.FindRoute(player)
    if best then R.Load(best.id) return best.id end
    return nil
end

function R.Skip(si)
    local id = ns.cdb.route
    if not id then return end
    ns.cdb.manual[id] = ns.cdb.manual[id] or {}
    ns.cdb.manual[id][si] = true
end

-- Einen Haupt-Schritt zurück: Zeiger auf den vorigen geltenden Schritt mit blockierenden Handlungen.
function R.Back(view)
    local route = view and view.route
    if not (route and view.main) then return end
    local player = S.Player()
    for si = view.main - 1, 1, -1 do
        local s = route.s[si]
        if P.Applies(s, player) then
            for _, entry in ipairs(P.Actions(s, player)) do
                if P.BLOCKING[entry.a[1]] then
                    ns.cdb.pointer[route.id] = si
                    local m = ns.cdb.manual[route.id]
                    if m then m[si] = nil end
                    local o = ns.cdb.open and ns.cdb.open[route.id]
                    if o then o[si] = nil end
                    return si
                end
            end
        end
    end
end

-- Angezeigte Schritte in Reihenfolge: Vorlauf, Dauerläufer, "erledigt mit", Nachholen, Haupt-Schritt,
-- jetzt abgebbare zurückgestellte Quests. Jeder Eintrag: { route, si, kind }.
-- full = false lässt Dauerläufer und "erledigt mit" weg (für Pfeil und Ereignis-Marken).
function R.Shown(view, full)
    local list = {}
    local route = view.route
    if not route then return list end
    local function add(r, si, kind) list[#list + 1] = { route = r, si = si, kind = kind } end
    for _, si in ipairs(view.lead) do add(route, si, "lead") end
    if full ~= false then
        for _, si in ipairs(view.sticky) do add(route, si, "sticky") end
        for _, si in ipairs(view.with) do add(route, si, "with") end
    end
    if view.catchup then add(view.catchup.route, view.catchup.si, "catchup") end
    if view.main then add(route, view.main, "main") end
    for _, si in ipairs(view.open or {}) do add(route, si, "open") end
    return list
end

-- Erste offene Handlung einer Art in den angezeigten Schritten als Ereignis-Marke setzen.
function R.MarkFirst(view, tag)
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            if entry.a[1] == tag and not P.Done(entry.a, { routeId = ref.route.id, si = ref.si, ai = entry.i }) then
                P.SetMark(ref.route.id, ref.si, entry.i)
                return true
            end
        end
    end
    return false
end

-- Naechster Wegpunkt für den Pfeil: erster nicht erreichter goto in Vorlauf, Nachholen, Haupt-Schritt
-- und abgebbaren zurückgestellten Quests.
function R.Waypoint(view)
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            if entry.a[1] == "goto" and not P.Done(entry.a) then return entry.a, ref.si, ref end
        end
    end
    return nil
end

-- Steht der Spieler am Ziel des Haupt-Schritts (alle Wegpunkte erreicht, Handlungen noch offen)?
function R.AtGoal(view)
    return view.route ~= nil and view.main ~= nil and R.Waypoint(view) == nil
end
