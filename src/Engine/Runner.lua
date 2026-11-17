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
-- Gilt die Route für diesen Charakter? Kopfbedingung der Quelle ("<< Alliance Hunter"): sonst bekäme
-- z. B. ein Krieger die Jäger-Route.
function R.Allowed(r, player)
    return not r.c or ns.Cond.Eval(r.c, player)
end

function R.Candidates(player, kind)
    local f = FactionLetter(player.faction)
    local list = {}
    for _, r in ipairs(ns.routes or {}) do
        if (r.f == f or r.f == "B") and r.k == kind and r.lo and r.hi and R.Allowed(r, player)
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
        -- doppelte Labels: das letzte gilt (wie in der Quelle), sonst endet ein "erledigt mit" zu früh
        for i, s in ipairs(route.s) do if s.lb == label then route.labels[label] = i end end
        -- Label eines Schritts, den der Konverter entfernt hat (andere Inhaltsphase): Verweis der Route
        if not route.labels[label] and route.la and route.la[label] then route.labels[label] = route.la[label] end
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
    -- Lineare Questreihe (Schlafsack): kein Schritt gilt als "Reihe nie begonnen" und keine Abgabe wird
    -- zurückgestellt. Sonst bleibt kein offener Schritt übrig und die Kette meldet sich mittendrin fertig
    -- ("Bonus route finished"), etwa wenn die Quest ein offenes Ziel hat oder das Abgabe-Flag nachhinkt.
    local chain = route.chain == true
    -- Erst wenn das Questlog geladen ist, darf die Auswertung Zustand schreiben (Zeiger, Zurückgestellt).
    local ready = ns.questsReady ~= false
    ns.cdb.open = ns.cdb.open or {}
    local open = ns.cdb.open[route.id] or {}

    -- Dungeon-Vorbereitung: offene Annahmen gelten nie als übersprungen oder hinter dem Zeiger
    local prepOpen = route.k == "dungeonquests" and R.PrepOpenSteps(route, player) or {}
    -- Von Hand übersprungene Annahmen holt die Vorbereitung erst zurück, wenn sonst nichts mehr offen ist:
    -- "Überspringen" wirkt sofort, gesammelt wird die Quest trotzdem noch.
    local unskipped = false
    for si in pairs(prepOpen) do if not manual[si] then unskipped = true end end
    if unskipped then
        for si in pairs(prepOpen) do if manual[si] then prepOpen[si] = nil end end
    end
    -- "Zurück": dieser Schritt bleibt Haupt-Schritt, auch wenn er schon erledigt ist, bis du weiterklickst
    local forced = active and ns.cdb.back and ns.cdb.back[route.id]

    local function IsDone(si)
        if doneAt[si] == nil then
            local s = steps[si]
            if (manual[si] and not prepOpen[si]) or not P.Applies(s, player) then
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
    -- Beleg, dass du einen späteren Schritt wirklich gemacht hast: eine seiner Quests ist angenommen oder
    -- abgegeben. "Erledigt", nur weil die Quest nie im Log war (Ziel einer nicht angenommenen Quest), zählt nicht.
    local function QuestEvidence(s)
        for _, entry in ipairs(P.Actions(s, player)) do
            local a = entry.a
            local tag = a[1]
            if a.q and (tag == "accept" or tag == "turnin" or tag == "complete" or tag == "collect") then
                if S.TurnedIn(a.q) then return true end
                if tag ~= "turnin" and S.OnQuest(a.q) and P.Done(a) then return true end
            end
        end
        return false
    end

    local function PassedOptional(si)
        for j = si + 1, math.min(#steps, si + OPTIONAL_LOOKAHEAD) do
            local s = steps[j]
            if not s.o and P.Applies(s, player) and Blocking(s) and IsDone(j) and not manual[j]
                and QuestEvidence(s) then
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

    -- Dungeon-Vorbereitung: führt eine Reise ins Leere? Die Schritte nach ihr bis zur nächsten Reise
    -- enthalten keine offene Quest-Arbeit mehr (alles schon angenommen, erledigt oder abgegeben). Dann
    -- entfällt sie, sonst fliegst du für eine Quest, die du längst hast, quer über den Kontinent.
    local QUEST_WORK = { accept = true, turnin = true, complete = true, collect = true }
    local function TravelLeadsNowhere(si)
        if route.k ~= "dungeonquests" then return false end
        -- Ein Ruhestein vor einer Flugstrecke bringt dich erst zum Flugmeister: den ersetzt der Flug nicht
        local ownHs = false
        for _, entry in ipairs(P.Pending(steps[si], player, route.id, si)) do
            if entry.a[1] == "hs" then ownHs = true end
        end
        for j = si + 1, #steps do
            local s = steps[j]
            if P.Applies(s, player) and not IsDone(j) then
                local pending = P.Pending(s, player, route.id, j)
                if P.OnlyTravel(pending) then
                    -- Eine spätere Flugstrecke (von jedem Flugmeister) oder ein Ruhestein macht diese Reise
                    -- überflüssig. Laufwege und Flugpunkte bauen auf dem Ort davor auf: weitersuchen.
                    for _, entry in ipairs(pending) do
                        local tag = entry.a[1]
                        if tag == "hs" or (tag == "fly" and not ownHs) then return true end
                    end
                else
                    for _, entry in ipairs(pending) do
                        if QUEST_WORK[entry.a[1]] then return false end
                    end
                end
            end
        end
        return true
    end

    -- Zurückgestellte Abgaben: erledigt -> vergessen; jetzt abgebbar -> anzeigen; sonst weiter warten.
    for si, q in pairs(open) do
        local s = steps[si]
        -- abgebrochen (weder im Log noch abgegeben): die Abgabe gibt es nicht mehr, auch nicht eine
        -- Folge-Annahme im selben Schritt
        local abandoned = type(q) == "number" and not S.OnQuest(q) and not S.TurnedIn(q)
        if not s or IsDone(si) or abandoned then
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

    -- Aus früheren Routen mitgenommene Abgaben: fertig -> anzeigen, sonst warten; abgegeben, verschwunden
    -- oder von dieser Route selbst abgedeckt -> aus der Liste
    view.carried = {}
    if active and ns.cdb.carry then
        local keep = {}
        for _, c in ipairs(ns.cdb.carry) do
            local r = R.Get(c.r)
            local s = r and r.s[c.si]
            -- Die aktive Route gibt dieselbe Quest selbst noch ab (Abgabe ab ihrem Zeiger): nur ausblenden, nicht
            -- löschen; liegt ihre Abgabe schon dahinter, zeigt die Mitnahme sie weiter
            local own = c.q and R.HasTurnin(route, c.q)
            local covered = own and own >= (ns.cdb.pointer[route.id] or 1)
            -- oder die Route hat dieselbe Abgabe selbst zurückgestellt: nicht doppelt zeigen
            if own and not covered then
                for _, q in pairs(open) do if q == c.q then covered = true end end
            end
            local drop = not s
                or (c.q and not S.OnQuest(c.q) and not S.TurnedIn(c.q))
                or not P.Applies(s, player) or P.StepDone(s, player, r.id, c.si)
            if drop then
                if not ready then keep[#keep + 1] = c end
            elseif covered then
                keep[#keep + 1] = c
            else
                keep[#keep + 1] = c
                if P.WaitsOnQuest(P.Pending(s, player, r.id, c.si)) then
                    view.waiting = view.waiting + 1
                else
                    view.carried[#view.carried + 1] = { route = r, si = c.si }
                end
            end
        end
        ns.cdb.carry = keep
    end

    -- Fortschrittszeiger: Schritte vor dem Zeiger gelten als erledigt, auch wenn sich der Spielzustand
    -- zurueckdreht (Quest abgebrochen, Items verbraucht). Er läuft nur vorwaerts, ausser per "Zurück".
    local start = active and ns.cdb.pointer[route.id] or 1
    for si in pairs(prepOpen) do if si < start then start = si end end
    if forced and forced < start then start = forced end
    -- Begleiter vor dem Zeiger (Vorlauf, Dauer-, "erledigt mit"-Schritte der letzten Auswertung): weiter
    -- zeigen, solange sie offen sind. Der Zeiger selbst bleibt beim Haupt-Schritt und schützt ihn.
    local comp = active and ns.cdb.comp and ns.cdb.comp[route.id]
    if comp then
        table.sort(comp)
        for _, si in ipairs(comp) do
            local s = steps[si]
            if s and si < start and not manual[si] and not open[si] and P.Applies(s, player) then
                if Blocking(s) then
                    if not IsDone(si) and #P.Pending(s, player, route.id, si) > 0 then
                        if s.cw then view.with[#view.with + 1] = si
                        elseif s.st then view.sticky[#view.sticky + 1] = si end
                    end
                else
                    local reached = false
                    for _, entry in ipairs(P.Actions(s, player)) do
                        if entry.a[1] == "goto" and P.Done(entry.a) then reached = true end
                    end
                    if not reached then view.lead[#view.lead + 1] = si end
                end
            end
        end
    end
    for si = start, #steps do
        local s = steps[si]
        if si == forced and steps[si] then
            view.main = si
            break
        elseif (manual[si] and not prepOpen[si]) or open[si] then
            -- übersprungen oder zurückgestellt: ein Vorlauf davor führte zu diesem Schritt, nicht weiter
            if Blocking(s) then view.lead = {} end
        elseif P.Applies(s, player) then
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
                    view.lead = {}
                elseif P.OnlyTravel(pending) and (Overtaken(si) or TravelLeadsNowhere(si)) then
                    -- schon am Ziel der Reise oder Reise ohne Quest dahinter, weiter
                    view.lead = {}
                elseif ready and not chain and P.ChainNotStarted(s, player, pending) then
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
                    elseif active and ready and not chain then
                        open[si] = waitsOn
                        ns.cdb.open[route.id] = open
                        view.waiting = view.waiting + 1
                        view.lead = {}
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
    -- Dungeon-Vorbereitung endet, sobald alle Quests für den Dungeon im Questlog sind (Dungeon und Abgabe
    -- gehören nicht mehr dazu)
    if route.k == "dungeonquests" and ready and R.PrepDone(route, player) then view.finished = true end
    -- "Zurück" gilt nur, solange der erzwungene Schritt auch Haupt-Schritt ist (eine frühere Vorbereitung oder
    -- ein Nachholen hat Vorrang): sonst hinge er später unerklärlich als erledigter Schritt in der Route
    if forced and active and ready and view.main ~= forced and ns.cdb.back then ns.cdb.back[route.id] = nil end
    -- Zeiger auf den Haupt-Schritt (Schutz gegen Rückfall); Begleiter davor merken, sonst wären sie ab der
    -- nächsten Auswertung verschwunden
    if active and ready and view.main then
        ns.cdb.pointer[route.id] = view.main
        local keep = {}
        for _, list in ipairs({ view.lead, view.sticky, view.with }) do
            for _, si in ipairs(list) do if si < view.main then keep[#keep + 1] = si end end
        end
        ns.cdb.comp = ns.cdb.comp or {}
        ns.cdb.comp[route.id] = #keep > 0 and keep or nil
    end
    return view
end

-------------------------------------------------------------------------------
-- Steuerung
-------------------------------------------------------------------------------
-- Gespeicherte Schrittnummern gehören zu einer Fassung der Route (Fingerabdruck v aus tools/convert.lua).
-- Ändert ein Datenupdate die Schrittfolge, zeigten Zeiger, Skips, Marken und geparkte Abgaben sonst auf
-- falsche Schritte. Dann wird der Stand dieser Route verworfen; erledigte Quests erkennt die Auswertung
-- weiter am Questlog. Erster Lauf ohne gemerkte Fassung: nur merken, nichts verwerfen.
local STEP_TABLES = { "pointer", "manual", "marks", "open", "back", "comp" }
function R.CheckVersions()
    local cdb = ns.cdb
    if not cdb then return 0 end
    cdb.ver = cdb.ver or {}
    local reset, changed = 0, {}
    for _, r in ipairs(ns.routes or {}) do
        if r.v then
            local old = cdb.ver[r.id]
            if old and old ~= r.v then
                changed[r.id] = true
                reset = reset + 1
                for _, name in ipairs(STEP_TABLES) do
                    if cdb[name] then cdb[name][r.id] = nil end
                end
                R.ResetPassed(r.id)
            end
            cdb.ver[r.id] = r.v
        end
    end
    if cdb.carry and next(changed) then
        local keep = {}
        for _, c in ipairs(cdb.carry) do
            if not changed[c.r] then keep[#keep + 1] = c end
        end
        cdb.carry = keep
    end
    return reset
end

-- Zurückgestellte Abgaben einer Route in die Mitnahme-Liste verschieben (Routenwechsel): sie erscheinen
-- in jeder folgenden Route, sobald die Quest fertig ist, bis sie abgegeben oder verschwunden sind.
function R.CarryOpen(fromId)
    local open = ns.cdb.open and ns.cdb.open[fromId]
    if not open then return end
    ns.cdb.carry = ns.cdb.carry or {}
    for si, q in pairs(open) do
        local known = false
        for _, c in ipairs(ns.cdb.carry) do
            if c.r == fromId and c.si == si then known = true end
        end
        if not known then ns.cdb.carry[#ns.cdb.carry + 1] = { r = fromId, si = si, q = q } end
    end
    ns.cdb.open[fromId] = nil
end

-- Enthält die Route eine Abgabe dieser Quest? Liefert den letzten Schritt mit dieser Abgabe oder nil.
function R.HasTurnin(route, q)
    if not route.turnins then
        local set = {}
        for si, s in ipairs(route.s) do
            for _, a in ipairs(s.a) do
                if a[1] == "turnin" and a.q then set[a.q] = si end
            end
        end
        route.turnins = set
    end
    return route.turnins[q]
end

function R.Load(id)
    local route = R.Get(id)
    if not route then return false end
    local old = ns.cdb.route
    if old and old ~= id then R.CarryOpen(old) end
    -- zurück in eine Route, aus der Abgaben mitgenommen wurden: sie gehören wieder ihr (ihr Zeiger steht
    -- schon dahinter, sonst gingen sie verloren)
    if ns.cdb.carry then
        local keep = {}
        for _, c in ipairs(ns.cdb.carry) do
            if c.r == id then
                ns.cdb.open[id] = ns.cdb.open[id] or {}
                ns.cdb.open[id][c.si] = c.q or true
            else
                keep[#keep + 1] = c
            end
        end
        ns.cdb.carry = keep
    end
    ns.cdb.route = id
    -- eine eigentliche Route von Hand gewählt: ein gemerkter Rückweg aus einer Zusatz-Route ist hinfällig
    if not R.BONUS[route.k] then ns.cdb.returnRoute = nil end
    return true
end

-- Route frisch starten: Zeiger, übersprungene und zurückgestellte Schritte vergessen, dann laden. Für
-- Zusatz-Routen (Schlafsack-Questreihe): sonst beginnt ein neuer Start beim alten Zeiger, die Schritte
-- dort gelten als "Kette nie begonnen", und die Route meldet sich sofort als fertig. Wo die Kette
-- wirklich steht, ergibt sich ohne Zeiger aus dem Questlog.
function R.Restart(id)
    if not R.Get(id) then return false end
    ns.cdb.pointer[id] = nil
    if ns.cdb.manual then ns.cdb.manual[id] = nil end
    if ns.cdb.back then ns.cdb.back[id] = nil end
    if ns.cdb.open then ns.cdb.open[id] = nil end
    -- Ereignis-Marken (Flug, Ruhestein, Flugpunkt) gehören zum alten Durchlauf: sonst gilt ein Flug sofort als
    -- erledigt und die Reise fehlt
    if ns.cdb.marks then ns.cdb.marks[id] = nil end
    if ns.cdb.comp then ns.cdb.comp[id] = nil end
    R.ResetPassed(id)
    return R.Load(id)
end

-------------------------------------------------------------------------------
-- Zusatz-Routen: Schlafsack-Questreihe (extra) und Dungeon-Vorbereitung (dungeonquests). Sie laufen
-- neben der eigentlichen Route; ist eine fertig, geht es mit der gemerkten Route weiter (Live.lua).
-------------------------------------------------------------------------------
R.BONUS = { extra = true, dungeonquests = true }

function R.IsBonus(route)
    return route ~= nil and R.BONUS[route.k] == true
end

-- Zusatz-Route frisch starten. Läuft schon eine Zusatz-Route, bleibt die gemerkte eigentliche Route
-- erhalten (Schlafsack, dann Dungeon: danach geht es mit der Leveling-Route weiter, nicht mit dem Schlafsack).
function R.StartBonus(id)
    if not R.Get(id) then return false end
    local current = ns.cdb.route and R.Get(ns.cdb.route)
    if current and current.id ~= id and not R.IsBonus(current) then ns.cdb.returnRoute = current.id end
    if ns.cdb.route ~= id then return R.Restart(id) end
    return true
end

-- Zusatz-Route verlassen: zurück zur gemerkten Route. Liefert deren ID oder nil.
function R.EndBonus()
    local back = ns.cdb.returnRoute
    if not (back and R.Get(back)) then return nil end
    ns.cdb.returnRoute = nil
    R.Load(back)
    return back
end

-- Anzeigename: "03. The Deadmines" -> "The Deadmines" (die Nummer sortiert nur die Quelle)
function R.DisplayName(route)
    if not route then return nil end
    if route.k == "dungeonquests" then return (route.n:gsub("^%d+%a?%.?%s+", "")) end
    return route.n
end

-- Dungeons mit Quest-Vorbereitung für diesen Charakter: Forever-eigene Liste (ohne Classic-Doppel),
-- nur mit mindestens einer Quest, in Reihenfolge der Quelle. Je Eintrag: route, name, range (grobe Stufe
-- laut Quelle), total (Quests der Vorbereitung), done (abgegeben), active (im Questlog).
-- Vorquests eines Schritts erfüllt (.isQuestTurnedIn)? Sonst bietet der Questgeber die Quest nicht an.
local function PrereqMet(s, player)
    for _, a in ipairs(s.a) do
        if a[1] == "isQuestTurnedIn" and ns.Cond.Eval(a.c, player) then
            local any = false
            for _, q in ipairs(a.ids or {}) do if S.TurnedIn(q) then any = true end end
            if not any then return false end
        end
    end
    return true
end

function R.DungeonList(player)
    player = player or S.Player()
    local f = FactionLetter(player.faction)
    local list = {}
    for _, r in ipairs(ns.routes or {}) do
        if r.k == "dungeonquests" and not r.era and (r.f == f or r.f == "B") and R.Allowed(r, player) then
            local seen, total, done, active = {}, 0, 0, 0
            for _, s in ipairs(r.s) do
                if ns.Cond.Eval(s.c, player) and PrereqMet(s, player) then
                    for _, a in ipairs(s.a) do
                        if a[1] == "accept" and a.q and not seen[a.q] and ns.Cond.Eval(a.c, player) then
                            seen[a.q] = true
                            total = total + 1
                            if S.TurnedIn(a.q) then done = done + 1 elseif S.OnQuest(a.q) then active = active + 1 end
                        end
                    end
                end
            end
            if total > 0 then
                list[#list + 1] = { route = r, name = R.DisplayName(r), range = r.sg, total = total, done = done,
                    active = active, order = tonumber(r.n:match("^(%d+)")) or 999 }
            end
        end
    end
    table.sort(list, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    return list
end

-- Quests, die im Dungeon erledigt werden: eine Quest mit Ziel (complete), deren Annahme in der Route vor
-- oder bei ihrem ersten Ziel steht. Je Quest die Schritte ihrer Annahme. Einmal je Route berechnet.
-- Gilt die Annahme dieser Dungeon-Quest im Schritt si für den Charakter? Schritt- und Handlungsbedingung.
local function PrepApplies(route, q, si, player)
    if not P.Applies(route.s[si], player) then return false end
    local c = route.prepCond and route.prepCond[q] and route.prepCond[q][si]
    return not c or ns.Cond.Eval(c, player)
end

local function PrepQuests(route)
    if route.prepQuests then return route.prepQuests end
    local accepts, firstComplete = {}, {}
    route.prepCond = {} -- [q][si] = Bedingung der Annahme selbst (z. B. nur Priester)
    for si, s in ipairs(route.s) do
        for _, a in ipairs(s.a) do
            if a.q and a[1] == "accept" then
                accepts[a.q] = accepts[a.q] or {}
                accepts[a.q][#accepts[a.q] + 1] = si
                route.prepCond[a.q] = route.prepCond[a.q] or {}
                route.prepCond[a.q][si] = a.c or false
            elseif a.q and a[1] == "complete" and not firstComplete[a.q] then
                firstComplete[a.q] = si
            end
        end
    end
    local list = {}
    for q, si in pairs(firstComplete) do
        local steps = accepts[q]
        if steps and steps[1] <= si then list[q] = steps end
    end
    route.prepQuests = list
    return list
end

-- Alle Quests für den Dungeon gesammelt? Jede ist im Log, schon abgegeben, beim Questgeber nicht im Angebot,
-- oder ihre Annahme wurde übersprungen bzw. gilt für diesen Charakter nicht.
function R.PrepDone(route, player)
    local any = false
    for q, steps in pairs(PrepQuests(route)) do
        any = true
        if not P.Done({ "accept", q = q }) then
            -- gilt die Annahme für diesen Charakter (Klasse, Rasse)? Übersprungen zählt nicht als gesammelt.
            for _, si in ipairs(steps) do
                if PrepApplies(route, q, si, player) then return false end
            end
        end
    end
    return any
end

-- Schritte mit noch offener Annahme einer Dungeon-Quest: set[si] = true. Die Vorbereitung führt dorthin
-- zurück, auch wenn der Schritt übersprungen wurde oder der Zeiger schon weiter ist.
function R.PrepOpenSteps(route, player)
    local set = {}
    for q, steps in pairs(PrepQuests(route)) do
        if not P.Done({ "accept", q = q }) then
            for _, si in ipairs(steps) do
                if PrepApplies(route, q, si, player) then set[si] = true end
            end
        end
    end
    return set
end

-- Quest-Namen einer Vorbereitung (für den Tooltip): { { q = id, text = "Annehmen: X" }, ... }
function R.DungeonQuests(route, player)
    player = player or S.Player()
    local list, seen = {}, {}
    for _, s in ipairs(route.s) do
        if ns.Cond.Eval(s.c, player) and PrereqMet(s, player) then
            for _, a in ipairs(s.a) do
                if a[1] == "accept" and a.q and not seen[a.q] and ns.Cond.Eval(a.c, player) then
                    seen[a.q] = true
                    list[#list + 1] = { q = a.q, a = a }
                end
            end
        end
    end
    return list
end

-- Folge-Route laden, wenn die aktuelle fertig ist. Liefert die neue ID oder nil.
function R.Advance(view)
    if not (view and view.finished and view.route) then return nil end
    local player = S.Player()
    for _, nx in ipairs(view.route.nx or {}) do
        if R.Get(nx.id) and ns.Cond.Eval(nx.c, player) and R.Allowed(R.Get(nx.id), player) then
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
    -- Route einer anderen Klasse oder Rasse (vor 2026-11-17 möglich): nicht behalten
    if current and not R.Allowed(current, player) then current, force = nil, true end
    if current and not force and current.hi and player.level <= current.hi + 1 then return current.id end
    -- eine gestartete Zusatz-Route (Schlafsack, Dungeon-Vorbereitung) ersetzt kein Levelaufstieg
    if current and not force and R.IsBonus(current) then return current.id end
    local best = R.FindRoute(player)
    if best then R.Load(best.id) return best.id end
    return nil
end

function R.Skip(si)
    local id = ns.cdb.route
    if not id then return end
    ns.cdb.manual[id] = ns.cdb.manual[id] or {}
    ns.cdb.manual[id][si] = true
    -- nur das Überspringen des "Zurück"-Schritts selbst beendet "Zurück", nicht eine andere Zeile
    if ns.cdb.back and ns.cdb.back[id] == si then ns.cdb.back[id] = nil end
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
                    ns.cdb.back = ns.cdb.back or {}
                    ns.cdb.back[route.id] = si
                    local m = ns.cdb.manual[route.id]
                    if m then m[si] = nil end
                    local o = ns.cdb.open and ns.cdb.open[route.id]
                    if o then o[si] = nil end
                    R.ResetPassed(route.id) -- zurück heißt: die Wegkette dieses Schritts wieder von vorn
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
    for _, c in ipairs(view.carried or {}) do add(c.route, c.si, "open") end
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

-- Zu welchem NPC gehört ein Wegpunkt? Die Quelle schreibt ".target X" vor oder nach das ".goto" desselben
-- Ortes ("Shoni ... goto A ... accept ... goto B, target Wilder"). Regel: der letzte NPC seit dem vorigen
-- Wegpunkt; gibt es keinen, der erste NPC danach (bis zum nächsten Wegpunkt). actions aus P.Actions.
-- Annahmen, die der angesprochene NPC nicht im Angebot hat. Ein Schritt kann Quests mehrerer NPCs
-- enthalten: zuständig ist der NPC im selben Abschnitt (Handlungen zwischen zwei Wegpunkten). Abschnitte
-- mit einem anderen oder mehreren NPCs oder mit offener Abgabe (Folgequest kommt erst danach) lassen
-- keinen Schluss zu. actions: Einträge aus P.Actions; isOpen(entry): Handlung noch offen;
-- isNpc(name): Name passt zum NPC; offered[q]: im Angebot. Liefert eine Liste von Quest-IDs.
function R.NotOffered(actions, isOpen, isNpc, offered)
    local missing, seg = {}, { accepts = {} }
    local function flush()
        if seg.npc and not seg.other and not seg.turnin then
            for _, q in ipairs(seg.accepts) do
                if not offered[q] then missing[#missing + 1] = q end
            end
        end
        seg = { accepts = {} }
    end
    for _, entry in ipairs(actions) do
        local a = entry.a
        if a[1] == "goto" then
            flush()
        elseif a[1] == "target" and a.names and a.names[1] then
            local match = false
            for _, n in ipairs(a.names) do if isNpc(n) then match = true end end
            if match then seg.npc = true else seg.other = true end
        elseif a[1] == "accept" and a.q and isOpen(entry) then
            seg.accepts[#seg.accepts + 1] = a.q
        elseif a[1] == "turnin" and isOpen(entry) then
            seg.turnin = true
        end
    end
    flush()
    return missing
end

function R.GotoNpc(actions, gotoEntry)
    local before, at
    for i, entry in ipairs(actions) do
        local a = entry.a
        if entry == gotoEntry then
            at = i
            break
        elseif a[1] == "goto" then
            before = nil
        elseif a[1] == "target" and a.names and a.names[1] then
            before = a.names[1]
        end
    end
    if not at then return nil end
    if before then return before end
    for i = at + 1, #actions do
        local a = actions[i].a
        if a[1] == "goto" then return nil end
        if a[1] == "target" and a.names and a.names[1] then return a.names[1] end
    end
    return nil
end

-- Naechster Wegpunkt für den Pfeil: erster nicht erreichter goto in Vorlauf, Nachholen, Haupt-Schritt
-- und abgebbaren zurückgestellten Quests.
-- Ist die Arbeit an einem Wegpunkt schon getan? Zum Wegpunkt gehören die Handlungen seit dem vorigen
-- Wegpunkt ("annehmen bei Shoni, dann goto Shoni"); gibt es davor keine, die danach bis zum nächsten
-- ("goto, dann annehmen"). Reine Wege (nur Wegpunkte hintereinander) haben keine Arbeit und zählen nie
-- als getan. ctx: { routeId, si } für Ereignis-Marken. Zweiter Wert: hat der Wegpunkt überhaupt Arbeit?
function R.GotoWorkDone(actions, gotoEntry, ctx)
    local work, at = {}, nil
    for i, entry in ipairs(actions) do
        if entry == gotoEntry then
            at = i
            break
        elseif entry.a[1] == "goto" then
            work = {}
        elseif P.BLOCKING[entry.a[1]] then
            work[#work + 1] = entry
        end
    end
    if not at then return false end
    if #work == 0 then
        for i = at + 1, #actions do
            local entry = actions[i]
            if entry.a[1] == "goto" then break end
            if P.BLOCKING[entry.a[1]] then work[#work + 1] = entry end
        end
    end
    if #work == 0 then return false, false end
    for _, entry in ipairs(work) do
        if not P.Done(entry.a, { routeId = ctx.routeId, si = ctx.si, ai = entry.i }) then return false, true end
    end
    return true, true
end

-- Wegketten: der weiteste erreichte Wegpunkt je Schritt (nur für diese Sitzung). Ein reiner Zwischenpunkt
-- (ohne Arbeit, nicht der letzte des Schritts) bis dahin bleibt erreicht, auch wenn du seinen Radius
-- wieder verlässt; sonst schickt der Pfeil dich zum vorigen Punkt zurück (Grenze Ashenvale/Brachland).
local passed = {}
function R.ResetPassed(routeId)
    if not routeId then passed = {} return end
    local prefix = routeId .. "#"
    for key in pairs(passed) do
        if key:sub(1, #prefix) == prefix then passed[key] = nil end
    end
end

function R.Waypoint(view)
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        local actions = P.Actions(ref.route.s[ref.si], player)
        local ctx = { routeId = ref.route.id, si = ref.si }
        local key = ref.route.id .. "#" .. ref.si
        -- Der Reihe nach vorrücken: nur der nächste Punkt nach dem bisher weitesten zählt als neu erreicht. Bei
        -- Rundwegen liegt der letzte Punkt am Start; ein Sprung auf ihn übersprang sonst den ganzen Rundweg.
        -- Einen ausgelassenen Punkt überspringen (Abkürzung) nur, wenn du keine schon passierte Stelle mehr
        -- berührst: am Start eines Rundwegs ist der gleiche Endpunkt erreicht, zählt aber noch nicht.
        local last
        local far = passed[key] or 0
        local gotos = {}
        for _, entry in ipairs(actions) do
            if entry.a[1] == "goto" then
                last = entry.i
                gotos[#gotos + 1] = entry
            end
        end
        local moved = true
        while moved do
            moved = false
            local atPassed, nextOpen, laterReached = false, nil, nil
            for _, entry in ipairs(gotos) do
                local done = P.Done(entry.a)
                if entry.i <= far then
                    if done then atPassed = true end
                elseif not nextOpen then
                    if done then
                        far, moved = entry.i, true
                        break
                    end
                    nextOpen = entry
                elseif done and not laterReached then
                    laterReached = entry
                end
            end
            if not moved and nextOpen and laterReached and not atPassed then
                far, moved = laterReached.i, true
            end
        end
        if far > 0 then passed[key] = far end
        for _, entry in ipairs(actions) do
            if entry.a[1] == "goto" and not P.Done(entry.a) then
                -- Wegpunkte, an denen nichts mehr zu tun ist, überspringen (Quest dort schon angenommen)
                local workDone, hasWork = R.GotoWorkDone(actions, entry, ctx)
                local behind = not hasWork and entry.i <= far and entry.i ~= last
                if not workDone and not behind then return entry.a, ref.si, ref end
            end
        end
    end
    return nil
end

-- Steht der Spieler am Ziel des Haupt-Schritts (alle Wegpunkte erreicht, Handlungen noch offen)?
-- Eine offene Reise in eine Zone ohne Koordinaten ("Reise nach Steinkrallengebirge") zählt wie ein offener
-- Wegpunkt: außerhalb der Zone ist niemand am Ziel.
function R.AtGoal(view)
    if not (view.route ~= nil and view.main ~= nil and R.Waypoint(view) == nil) then return false end
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            local tag = entry.a[1]
            if (tag == "zone" or tag == "subzone") and not P.Done(entry.a) then return false end
        end
    end
    return true
end
