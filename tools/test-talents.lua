-- Offline-Test der Leveling-Talente: Daten aus data/Talents.lua und die Logik in src/Engine/Talents.lua
-- gegen einen simulierten Talentbaum (C_Traits wie im Forever-Client).
-- Aufruf aus dem Projektordner: lua tools/test-talents.lua
local fails = 0
local function check(label, ok, detail)
    if not ok then fails = fails + 1 end
    io.write(("%-70s %s%s\n"):format(label, ok and "OK" or "FEHLER", detail and ("  " .. detail) or ""))
end

-------------------------------------------------------------------------------
-- Simulierter Client
-------------------------------------------------------------------------------
local W = { class = "PALADIN", level = 10, free = 0, nodes = {}, order = {}, renamed = {} }
GetLocale = function() return "deDE" end
UnitClass = function() return "Paladin", W.class end
UnitLevel = function() return W.level end
-- Zaubernamen: "Spell <ID>"; renamed bildet eine abweichende Knoten-ID auf den Namen der Daten-ID ab
C_Spell = {
    GetSpellName = function(id) return "Spell " .. tostring(W.renamed[id] or id) end,
    GetSpellTexture = function() return 134400 end,
}
C_ClassTalents = { GetActiveConfigID = function() return 1 end }
C_Traits = {
    GetConfigInfo = function() return { treeIDs = { 10 } } end,
    GetGroupDisplayInfoByTreeID = function()
        return { { orderIndex = 0, displayName = "Baum1" }, { orderIndex = 1, displayName = "Baum2" }, { orderIndex = 2, displayName = "Baum3" } }
    end,
    GetTreeNodes = function() return W.order end,
    GetNodeInfo = function(_, id)
        local n = W.nodes[id]
        return { ID = id, maxRanks = n.max, ranksPurchased = n.ranks, entryIDs = { id } }
    end,
    GetEntryInfo = function(_, id) return { definitionID = id } end,
    GetDefinitionInfo = function(id) return { spellID = W.nodes[id].spell } end,
    GetTreeCurrencyInfo = function() return { { quantity = W.free } } end,
}

local ns = {}
for _, f in ipairs({ "src/Core.lua", "src/Locale/Locale.lua", "src/Locale/enUS.lua", "src/Locale/deDE.lua",
    "src/Engine/Talents.lua", "data/Talents.lua" }) do
    assert(loadfile(f))("UltimaLevelingXP", ns)
end
ns.InitDB({ lang = "deDE", langChosen = true }, {})
local T = ns.Talents

-- Baum einer Klasse aus allen Talenten ihrer Builds (Höchstrang = höchster Rang in den Daten)
local function MakeTree(class)
    W.class, W.nodes, W.order, W.renamed = class, {}, {}, {}
    local max = {}
    for _, b in ipairs(ns.TalentBuilds[class]) do
        for _, list in ipairs({ b.pre or "", b.order }) do
            for id, rank in list:gmatch("(%d+):(%d+)") do
                id, rank = tonumber(id), tonumber(rank)
                if not max[id] or rank > max[id] then max[id] = rank end
            end
        end
    end
    for id, m in pairs(max) do
        W.nodes[id] = { spell = id, max = m, ranks = 0 }
        W.order[#W.order + 1] = id
    end
    table.sort(W.order)
    ns.cdb.talentBuild = nil
    T.Invalidate()
end

-- Die ersten n Punkte einer Liste verteilen
local function Spend(list, n)
    local i = 0
    for id, rank in list:gmatch("(%d+):(%d+)") do
        i = i + 1
        if i > n then break end
        W.nodes[tonumber(id)].ranks = tonumber(rank)
    end
    T.Invalidate()
end

local function Find(class, spec, label)
    for i, b in ipairs(ns.TalentBuilds[class]) do
        if b.spec == spec and (label == nil or b.label == label) then return b, i end
    end
end

-------------------------------------------------------------------------------
-- 1. Daten
-------------------------------------------------------------------------------
local CLASSES = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
local total, sum, weighted, builds = 0, 0, 0, 0
local countOk, splitOk, rankOk, defaultOk = true, true, true, true
local detail = {}
for _, class in ipairs(CLASSES) do
    local defaults = 0
    for _, b in ipairs(ns.TalentBuilds[class] or {}) do
        builds = builds + 1
        if b.default then defaults = defaults + 1 end
        local n = 0
        for _ in b.order:gmatch("%d+:%d+") do n = n + 1 end
        if n ~= 51 - b.first + 1 then countOk = false; detail[#detail + 1] = class .. " " .. b.spec .. " " .. n end
        local a, c, d = b.split:match("^(%d+)/(%d+)/(%d+)$")
        if not a or a + c + d ~= 51 then splitOk = false; detail[#detail + 1] = class .. " " .. b.spec .. " " .. b.split end
        for _, list in ipairs({ b.pre or "", b.order }) do
            -- Ränge eines Talents kommen lückenlos aufsteigend (1, 2, 3 ...)
            local seen = {}
            for id, rank in list:gmatch("(%d+):(%d+)") do
                id, rank = tonumber(id), tonumber(rank)
                if rank ~= (seen[id] or 0) + 1 or rank > 5 then rankOk = false; detail[#detail + 1] = class .. " " .. id .. ":" .. rank end
                seen[id] = rank
                total = total + 1
                sum = sum + id
                weighted = weighted + rank * ((total % 7) + 1)
            end
        end
    end
    if defaults ~= 1 then defaultOk = false; detail[#detail + 1] = class .. " Vorschläge " .. defaults end
end
check("Daten: 9 Klassen, 35 Builds", builds == 35, tostring(builds))
check("Daten: Punkte je Liste = 51 ab erstem Punkt", countOk, #detail > 0 and table.concat(detail, ", ") or nil)
check("Daten: Aufteilung je Baum ergibt 51", splitOk)
check("Daten: Ränge lückenlos aufsteigend, höchstens 5", rankOk)
check("Daten: genau ein Vorschlag je Klasse", defaultOk)
-- Prüfsumme der Daten (Stand 2026-11-11): erkennt versehentliche Änderungen
check("Daten: Prüfsumme unverändert", ("%d %d %d"):format(total, sum, weighted) == "1821 427943526 16533",
    ("%d %d %d"):format(total, sum, weighted))

-------------------------------------------------------------------------------
-- 2. Stufe 10, nichts verteilt, ein Punkt frei
-------------------------------------------------------------------------------
MakeTree("PALADIN")
W.level, W.free = 10, 1
local ret, retIndex = Find("PALADIN", "retribution")
local plan = T.Plan()
check("Ohne verteilte Punkte: Vorschlag der Klasse (Vergeltung)", plan and plan.build == ret)
check("Erster Punkt: Benediction 1/5, bereit", plan.next[1].spell == 20101 and plan.next[1].rank == 1 and plan.next[1].ready)
check("Nur so viele Punkte bereit, wie frei sind", plan.next[2] and not plan.next[2].ready)
check("Anzeigename aus dem Baumnamen des Clients", T.BuildName(ret, plan.tree) == "Baum3 14/6/31", T.BuildName(ret, plan.tree))
check("Zielränge: Benediction 1 bei einem Punkt", plan.want[20101] == 1 and plan.final[20101] == 5)

-------------------------------------------------------------------------------
-- 3. Verteilen nach Liste, Stufe ohne und mit "Talented"
-------------------------------------------------------------------------------
Spend(ret.order, 5)
W.level, W.free = 14, 0
plan = T.Plan()
check("5 Punkte nach Liste: nichts falsch, kein Punkt bereit", #plan.wrong == 0 and not plan.next[1].ready)
check("Nächster Punkt 6 auf Stufe 15", plan.next[1].point == 6 and plan.next[1].level == 15,
    plan.next[1].point .. " / " .. plan.next[1].level)
W.level, W.free = 10, 1 -- Legacy-Perk: Punkte ab Stufe 5, mit Stufe 10 schon 6 Punkte
plan = T.Plan()
check("Talented: 5 Punkte früher erkannt", plan.bonus == 5 and plan.total == 6, plan.bonus .. " / " .. plan.total)
check("Talented: Punkt 7 schon auf Stufe 11", plan.next[2].point == 7 and plan.next[2].level == 11)

-------------------------------------------------------------------------------
-- 4. Abweichungen und Zuordnung
-------------------------------------------------------------------------------
W.nodes[20127].ranks = 1 -- Schutz-Talent, im Vergeltungs-Build nicht vorgesehen
W.free = 0
T.Invalidate()
plan = T.Plan()
check("Talent außerhalb des Builds wird als abweichend gemeldet", #plan.wrong == 1 and plan.wrong[1].id == 20127)
W.nodes[20127].ranks = 0

-- Knoten mit anderer Zauber-ID, aber gleichem Namen in Client-Sprache (Zuordnung über den Namen)
W.nodes[25956].spell = 999001
W.renamed[999001] = 25956
T.Invalidate()
plan = T.Plan()
check("Zuordnung über den Namen, wenn die Zauber-ID abweicht", T.Node(plan.tree, 25956) ~= nil and plan.missing == 0)
W.renamed[999001] = nil
T.Invalidate()
plan = T.Plan()
check("Talent nicht im Baum: wird gezählt, nicht verschwiegen", T.Node(plan.tree, 25956) == nil and plan.final[25956] == nil)
-- mit allen Punkten: das fehlende Talent liegt mit mehreren Rängen im Bereich, gemeldet wird es einmal
local freeBefore = W.free
W.free = 51
T.Invalidate()
plan = T.Plan()
check("Fehlendes Talent zählt einmal, nicht je Rang (Audit 2026-11-16)", plan.missing == 1, tostring(plan.missing) .. " gezählt")
W.free = freeBefore
W.nodes[25956].spell = 25956
W.free = 1
T.Invalidate()
plan = T.Plan()
check("Nicht gefundene Schritte gezählt (nur bis zur Punktzahl)", plan.missing == 0)

-------------------------------------------------------------------------------
-- 5. Build-Wahl
-------------------------------------------------------------------------------
MakeTree("PALADIN")
local prot, protIndex = Find("PALADIN", "protection")
Spend(prot.order, 12)
W.level, W.free = 21, 0
local chosen, chosenIndex = T.Choose()
check("Automatisch: Build, zu dem die Punkte passen (Schutz)", chosen == prot and chosenIndex == protIndex)
T.Select(retIndex)
chosen = T.Choose()
check("Eigene Wahl gilt vor der Automatik", chosen == ret)
plan = T.Plan()
check("Eigene Wahl: Schutz-Punkte gelten als abweichend", #plan.wrong > 0)
T.Select(nil)
check("Wahl zurück auf automatisch", ns.cdb.talentBuild == nil and T.Choose() == prot)
T.Select(99)
check("Ungültige Wahl wird verworfen", ns.cdb.talentBuild == nil)
-- gespeicherte Nummer, die es nach einem Datenupdate nicht mehr gibt (Audit 2026-11-16)
ns.cdb.talentBuild = 99
T.Choose()
check("Gespeicherte ungültige Wahl wird auf automatisch zurückgesetzt", ns.cdb.talentBuild == nil, tostring(ns.cdb.talentBuild))

-------------------------------------------------------------------------------
-- 6. Builds mit Vorphase und Neuverteilung (Schamane Spellhance, Magier Frost)
-------------------------------------------------------------------------------
MakeTree("SHAMAN")
local spell, spellIndex = Find("SHAMAN", "elemental", "spellhance")
T.Select(spellIndex)
W.level, W.free = 20, 0
Spend(spell.pre, 11)
plan = T.Plan()
check("Vorphase bis Stufe 31 aktiv", plan.early and #plan.wrong == 0 and not plan.respec)
check("Variante im Namen", T.BuildName(spell, plan.tree):find("Spellhance", 1, true) ~= nil, T.BuildName(spell, plan.tree))
W.level = 31
Spend(spell.pre, 22)
plan = T.Plan()
check("Ab Stufe 31: Neuverteilung empfohlen", not plan.early and plan.respec)
MakeTree("MAGE")
local frost, frostIndex = Find("MAGE", "frost")
W.level, W.free = 33, 24
plan = T.Plan()
check("Frost ohne Punkte ab Stufe 33: volle Liste, keine Neuverteilung", plan.build == frost and not plan.early and not plan.respec)
check("Frost ist Vorschlag der Klasse", select(2, T.Choose()) == frostIndex)

-------------------------------------------------------------------------------
-- 7. Ohne C_Traits oder ohne Builds
-------------------------------------------------------------------------------
local saved = C_Traits
C_Traits = nil
T.Invalidate()
local none, err = T.Plan()
check("Ohne C_Traits: kein Plan, Grund genannt", none == nil and err == "C_Traits missing")
C_Traits = saved
W.class = "DEATHKNIGHT"
T.Invalidate()
none, err = T.Plan()
check("Klasse ohne Builds: kein Plan, Grund genannt", none == nil and err == "no build for this class")

-- Audit 2026-11-17: automatische Wahl bei Builds mit Vorphase. Auf der Stufe der Neuverteilung bleibt der
-- Build, und der Hinweis "neu verteilen" erscheint (vorher sprang die Wahl zu einem anderen Build, ohne Hinweis).
do
    local _, preIndex
    for i, b in ipairs(ns.TalentBuilds.SHAMAN) do if b.pre then _, preIndex = b, i break end end
    local b = ns.TalentBuilds.SHAMAN[preIndex]
    MakeTree("SHAMAN")
    W.level = b.preUntil - 1
    local preCount = 0
    for _ in b.pre:gmatch("%d+:%d+") do preCount = preCount + 1 end
    Spend(b.pre, math.min(preCount, W.level - 9))
    W.free = 0
    local before = select(2, T.Choose())
    W.level = b.preUntil
    W.free = 1
    T.Invalidate()
    local plan = T.Plan()
    check("Vorphase: automatische Wahl bleibt beim Build und meldet Neuverteilung",
        before == preIndex and plan and plan.index == preIndex and plan.respec == true,
        ("vorher %s, nachher %s, respec %s"):format(tostring(before), tostring(plan and plan.index), tostring(plan and plan.respec)))
    W.free = 0
end

-- Audit 2026-11-17: Build ab Punkt 6 ohne Vorphase (Paladin Heilig): die ersten 5 Punkte sind frei und gelten
-- nicht als falsch (vorher rote Labels und keine Erinnerung auf Stufe 10-14)
do
    local holy, holyIndex = Find("PALADIN", "holy")
    MakeTree("PALADIN")
    T.Select(holyIndex)
    W.level, W.free = 14, 0
    local spent = 0
    for _, id in ipairs(W.order) do
        local want = false
        for sid in holy.order:gmatch("(%d+):%d+") do if tonumber(sid) == id then want = true end end
        if not want and spent < 5 then W.nodes[id].ranks = 1; spent = spent + 1 end
    end
    T.Invalidate()
    local plan = T.Plan()
    check("Heilig ab Punkt 6: 5 freie Punkte davor gelten nicht als falsch", spent == 5 and plan and #plan.wrong == 0,
        ("verteilt %d, falsch %s"):format(spent, tostring(plan and #plan.wrong)))
    T.Select(nil)
end

-- Audit 2026-11-17: ohne Punkte kein Bonus (vorher Stufe 1 -> 5 Punkte "früher", Karte zeigte "Stufe 5")
check("Bonus: Stufe 1 ohne Punkte 0, Stufe 5 mit 1 Punkt (Perk) 5, Stufe 20 mit 11 Punkten 0",
    T.Bonus(0, 1) == 0 and T.Bonus(1, 5) == 5 and T.Bonus(11, 20) == 0,
    T.Bonus(0, 1) .. "/" .. T.Bonus(1, 5) .. "/" .. T.Bonus(11, 20))

io.write(fails == 0 and "Alle Pruefungen OK\n" or (fails .. " Pruefungen fehlgeschlagen\n"))
os.exit(fails == 0 and 0 or 1)
