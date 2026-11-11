-- Leveling-Talente: liest den Talentbaum des Clients (C_Traits), ordnet die Leveling-Reihenfolge aus
-- data/Talents.lua (Zauber-IDs) den Knoten zu und bestimmt die nächsten Punkte.
-- Zuordnung ohne Sprachabhängigkeit: erst über die Zauber-ID des Knotens, sonst über den Namen des Zaubers,
-- den der Client in seiner eigenen Sprache für beide Seiten liefert.
-- Gezählt wird nach Talentpunkten, nicht nach Stufe: mit dem Legacy-Perk "Talented" kommen Punkte früher.
local _, ns = ...
local L = ns.L

local T = {}
ns.Talents = T

local MAX_POINTS = 51
T.SHOWN_NEXT = 5 -- so viele kommende Punkte zeigt die Liste

-- Namen der Varianten, wenn eine Spezialisierung mehrere Builds hat (erst beim Anzeigen übersetzt,
-- damit ein Sprachwechsel greift)
local VARIANT = {
    spellhance = function() return L["Spellhance"] end,
    elemental = function() return L["Elemental only"] end,
    solo = function() return L["Solo"] end,
    dungeon = function() return L["Dungeon"] end,
    cleave = function() return L["Single target and cleave"] end,
    single = function() return L["Safe single target"] end,
    reflection = function() return L["Reflection first"] end,
    multidot = function() return L["Multi-DoT"] end,
    hybrid = function() return L["Damage and healing"] end,
    healing = function() return L["Pure healing"] end,
}
-- Rückfall, wenn der Client die Namen der Talentbäume nicht liefert
local SPEC_NAME = {
    arms = "Arms", fury = "Fury", protection = "Protection", holy = "Holy", retribution = "Retribution",
    ["beast-mastery"] = "Beast Mastery", marksmanship = "Marksmanship", survival = "Survival",
    assassination = "Assassination", combat = "Combat", subtlety = "Subtlety", discipline = "Discipline",
    shadow = "Shadow", elemental = "Elemental", enhancement = "Enhancement", restoration = "Restoration",
    arcane = "Arcane", fire = "Fire", frost = "Frost", affliction = "Affliction", demonology = "Demonology",
    destruction = "Destruction", balance = "Balance", feral = "Feral",
}

local function Clean(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return (GetSpellInfo(id)) end
    return nil
end
T.SpellName = SpellName

local function SpellIcon(id)
    if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
    if GetSpellTexture then return GetSpellTexture(id) end
    return nil
end
T.SpellIcon = SpellIcon

-- Vergleichsform eines Namens: klein, ohne Leer- und Satzzeichen
local function Norm(s)
    if type(s) ~= "string" then return nil end
    return (s:lower():gsub("[%s%p]", ""))
end

-------------------------------------------------------------------------------
-- Daten
-------------------------------------------------------------------------------
local parsed = {}
-- "20101:1 20101:2" -> { { spell = 20101, rank = 1 }, ... } (einmal je Liste)
local function Parse(list)
    local steps = parsed[list]
    if steps then return steps end
    steps = {}
    for id, rank in list:gmatch("(%d+):(%d+)") do steps[#steps + 1] = { spell = tonumber(id), rank = tonumber(rank) } end
    parsed[list] = steps
    return steps
end

function T.PlayerClass()
    local _, class = UnitClass("player")
    return class
end

function T.Level() return UnitLevel("player") or 1 end

-- Builds der Klasse des Spielers (leer, wenn es keine gibt)
function T.Builds()
    return ns.TalentBuilds and ns.TalentBuilds[T.PlayerClass()] or {}
end

-- Liste, die auf dieser Stufe gilt: die Vorphase bis preUntil, danach die Hauptliste.
-- Liefert Schritte, Nummer des ersten Punkts, Vorphase ja/nein
function T.ActiveList(build, level)
    if build.pre and level < build.preUntil then return Parse(build.pre), 1, true end
    return Parse(build.order), build.first or 1, false
end

-------------------------------------------------------------------------------
-- Talentbaum des Clients
-------------------------------------------------------------------------------
local tree

-- Nach jeder Änderung an Talenten, Punkten oder Stufe neu lesen
function T.Invalidate() tree = nil end

function T.Tree()
    if tree then return tree end
    if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits and C_Traits.GetConfigInfo
        and C_Traits.GetTreeNodes and C_Traits.GetNodeInfo) then
        return nil, "C_Traits missing"
    end
    local configID = Clean(C_ClassTalents.GetActiveConfigID())
    if not configID then return nil, "no talent config" end
    local config = C_Traits.GetConfigInfo(configID)
    local treeID = config and config.treeIDs and config.treeIDs[1]
    if not treeID then return nil, "no talent tree" end

    local t = { configID = configID, treeID = treeID, nodes = {}, byId = {}, bySpell = {}, byName = {}, groupName = {} }
    if C_Traits.GetGroupDisplayInfoByTreeID then
        -- Namen der drei Bäume (Reihenfolge wie im Talentfenster)
        for _, g in ipairs(C_Traits.GetGroupDisplayInfoByTreeID(treeID) or {}) do
            local order, name = Clean(g.orderIndex), Clean(g.displayName)
            if order and name then t.groupName[order + 1] = name end
        end
    end
    for _, nodeID in ipairs(C_Traits.GetTreeNodes(treeID) or {}) do
        local info = C_Traits.GetNodeInfo(configID, nodeID)
        if info and info.ID and info.ID ~= 0 then
            local entryID = info.activeEntry and info.activeEntry.entryID or (info.entryIDs and info.entryIDs[1])
            local entry = entryID and C_Traits.GetEntryInfo and C_Traits.GetEntryInfo(configID, entryID)
            local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo and C_Traits.GetDefinitionInfo(entry.definitionID)
            local spell = def and (def.spellID or def.overriddenSpellID)
            local node = {
                id = nodeID, spell = spell,
                name = (def and def.overrideName) or (spell and SpellName(spell)),
                max = Clean(info.maxRanks) or 1,
                ranks = Clean(info.ranksPurchased) or Clean(info.currentRank) or 0,
            }
            t.nodes[#t.nodes + 1] = node
            t.byId[nodeID] = node
            if spell then t.bySpell[spell] = node end
            local key = Norm(node.name)
            if key then t.byName[key] = node end
        end
    end
    if #t.nodes == 0 then return nil, "talent tree empty" end
    tree = t
    return t
end

-- Knoten zu einer Zauber-ID aus den Daten: erst über die ID, sonst über den Namen in Client-Sprache
function T.Node(t, spell)
    local node = t.bySpell[spell]
    if node then return node end
    local key = Norm(SpellName(spell))
    return key and t.byName[key] or nil
end

-- Talentpunkte gesamt (verteilt + frei) und davon verteilt
function T.Points(t)
    local spent = 0
    for _, n in ipairs(t.nodes) do spent = spent + n.ranks end
    local free
    if C_Traits.GetTreeCurrencyInfo then
        local list = C_Traits.GetTreeCurrencyInfo(t.configID, t.treeID, false)
        local currency = type(list) == "table" and list[1]
        free = currency and Clean(currency.quantity)
    end
    local total = free and (spent + free) or math.max(spent, T.Level() - 9)
    return math.min(math.max(total, 0), MAX_POINTS), spent
end

-- Wie viele Punkte früher als üblich (Legacy-Perk "Talented"): 0 bis 5
function T.Bonus(total, level)
    if level >= 60 then return 0 end
    return math.max(0, math.min(5, total - (level - 9)))
end

-- Zielränge je Knoten nach den ersten upTo Punkten einer Liste; dazu die Zahl nicht gefundener Schritte
local function Targets(t, steps, first, upTo)
    local want, missing = {}, 0
    for i, step in ipairs(steps) do
        if first + i - 1 > upTo then break end
        local node = T.Node(t, step.spell)
        if node then
            if step.rank > (want[node.id] or 0) then want[node.id] = step.rank end
        else
            missing = missing + 1
        end
    end
    return want, missing
end

-------------------------------------------------------------------------------
-- Build-Wahl
-------------------------------------------------------------------------------
-- Gewählter Build: eigene Wahl des Charakters, sonst der Build, zu dem die verteilten Punkte am besten passen,
-- sonst der Vorschlag der Klasse. Liefert Build und seinen Index.
function T.Choose()
    local builds = T.Builds()
    if #builds == 0 then return nil end
    local chosen = ns.cdb and ns.cdb.talentBuild
    if chosen and builds[chosen] then return builds[chosen], chosen end
    local t = T.Tree()
    if t then
        local level = T.Level()
        local total = T.Points(t)
        local best, bestIndex, bestScore = nil, nil, 0
        for i, build in ipairs(builds) do
            -- Vergleich mit den Zielrängen bei der aktuellen Punktzahl: passende Ränge zählen,
            -- Ränge außerhalb des Builds abziehen. Gleichstand: der Vorschlag der Klasse gewinnt.
            local steps, first = T.ActiveList(build, level)
            local want = Targets(t, steps, first, total)
            local score = 0
            for _, n in ipairs(t.nodes) do
                local target = want[n.id] or 0
                score = score + math.min(n.ranks, target) - math.max(0, n.ranks - target)
            end
            if score > bestScore or (score == bestScore and score > 0 and build.default) then
                best, bestIndex, bestScore = build, i, score
            end
        end
        if best then return best, bestIndex end
    end
    for i, build in ipairs(builds) do
        if build.default then return build, i end
    end
    return builds[1], 1
end

-- Eigene Wahl setzen (nil = wieder automatisch)
function T.Select(index)
    if not ns.cdb then return end
    local builds = T.Builds()
    ns.cdb.talentBuild = (index and builds[index]) and index or nil
end

-- Name des Baums mit den meisten Punkten (aus dem Client, also in Client-Sprache) und die Aufteilung
function T.SpecName(build, t)
    local points, main = {}, 1
    for n in build.split:gmatch("%d+") do points[#points + 1] = tonumber(n) end
    for i = 2, #points do if points[i] > points[main] then main = i end end
    local name = (t and t.groupName[main]) or SPEC_NAME[build.spec] or build.spec
    return name .. " " .. build.split
end

-- Name der Variante oder nil
function T.VariantName(build)
    local fn = build.label and VARIANT[build.label]
    return fn and fn() or nil
end

-- Anzeigename in einer Zeile: Baum, Aufteilung, Variante
function T.BuildName(build, t)
    local variant = T.VariantName(build)
    return T.SpecName(build, t) .. (variant and (" · " .. variant) or "")
end

-------------------------------------------------------------------------------
-- Stand des Builds
-------------------------------------------------------------------------------
-- plan = {
--   build, index, tree, total, spent, free, level, bonus,
--   want     [nodeID] = Zielrang bei der aktuellen Punktzahl
--   final    [nodeID] = Zielrang im fertigen Build (alle 51 Punkte)
--   next     kommende Schritte: { node, spell, rank, point, level, ready }
--   wrong    Knoten mit mehr Rängen als vorgesehen
--   missing  Schritte, deren Talent im Baum nicht gefunden wurde
--   early    Vorphase aktiv; respec: Stufe der Neuverteilung ist erreicht und Punkte liegen falsch
-- }
function T.Plan()
    local t, err = T.Tree()
    if not t then return nil, err end
    local build, index = T.Choose()
    if not build then return nil, "no build for this class" end
    local level = T.Level()
    local total, spent = T.Points(t)
    local steps, first, early = T.ActiveList(build, level)
    local want, missing = Targets(t, steps, first, total)
    local final = Targets(t, steps, first, MAX_POINTS)
    local bonus = T.Bonus(total, level)
    local plan = {
        build = build, index = index, tree = t, total = total, spent = spent, free = math.max(0, total - spent),
        level = level, bonus = bonus, want = want, final = final, missing = missing,
        next = {}, wrong = {}, early = early,
    }
    for _, n in ipairs(t.nodes) do
        if n.ranks > (want[n.id] or 0) then plan.wrong[#plan.wrong + 1] = n end
    end
    plan.respec = build.pre ~= nil and not early and #plan.wrong > 0
    -- Schritte in Reihenfolge, die noch fehlen; "ready" für so viele, wie Punkte frei sind
    local ready = 0
    for i, step in ipairs(steps) do
        local node = T.Node(t, step.spell)
        if not (node and node.ranks >= step.rank) then
            local point = first + i - 1
            local isReady = node ~= nil and point <= total and ready < plan.free
            if isReady then ready = ready + 1 end
            plan.next[#plan.next + 1] = {
                node = node, spell = step.spell, rank = step.rank, point = point,
                level = math.max(1, point + 9 - bonus), ready = isReady,
            }
            if #plan.next >= T.SHOWN_NEXT then break end
        end
    end
    return plan
end
