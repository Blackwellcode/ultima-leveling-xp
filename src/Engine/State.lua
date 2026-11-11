-- Spielzustand hinter einer schmalen Schnittstelle. Engine und Tests sprechen nur mit ns.State,
-- der Offline-Test ersetzt die Funktionen durch eine Simulation.
local _, ns = ...
local S = {}
ns.State = S

local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

function S.Player()
    local _, race = UnitRace("player")
    local _, class = UnitClass("player")
    return {
        race = race, class = class, faction = UnitFactionGroup("player"),
        level = UnitLevel("player"), game = ns.GAME, sex = UnitSex("player"), locale = GetLocale(),
    }
end

function S.Level() return UnitLevel("player") end
function S.XP() return UnitXP("player"), UnitXPMax("player") end

function S.OnQuest(q)
    if C_QuestLog.IsOnQuest then return C_QuestLog.IsOnQuest(q) end
    return GetQuestLogIndexByID and GetQuestLogIndexByID(q) ~= 0
end
function S.TurnedIn(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end
-- Quest abgabebereit? Zwei Abfragen, weil nicht jeder Client beide kennt oder gleich füllt.
function S.QuestComplete(q)
    if C_QuestLog.IsComplete and C_QuestLog.IsComplete(q) then return true end
    if C_QuestLog.ReadyForTurnIn and C_QuestLog.ReadyForTurnIn(q) then return true end
    return false
end

-- Hat die Quest noch unerledigte Ziele? Liefer- und Gesprächsquests ohne Ziele sind sofort abgebbar,
-- auch wenn das Spiel sie nicht als "fertig" markiert.
function S.HasOpenObjectives(q)
    if S.QuestComplete(q) then return false end
    local list = C_QuestLog.GetQuestObjectives(q)
    if not list or #list == 0 then return false end
    for _, obj in ipairs(list) do
        if not obj.finished then return true end
    end
    return false
end

-- Ziel o einer Quest: erledigt?, Text, vorhanden, benoetigt
function S.Objective(q, o)
    local list = C_QuestLog.GetQuestObjectives(q)
    local obj = list and list[o]
    if not obj then return nil end
    return obj.finished, obj.text, obj.numFulfilled, obj.numRequired
end

function S.QuestTitle(q)
    return C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(q) or nil
end

function S.ItemCount(i)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(i) end
    return GetItemCount(i)
end
function S.ItemName(i)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(i) end
    return (GetItemInfo(i))
end
function S.KnowsSpell(sp) return IsSpellKnown(sp) or (IsPlayerSpell and IsPlayerSpell(sp)) or false end
function S.SpellName(sp)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(sp) end
    return (GetSpellInfo(sp))
end

function S.ZoneText() return GetRealZoneText() or "" end
function S.SubzoneText() return GetSubZoneText() or "" end
function S.AreaName(area) return C_Map.GetAreaInfo and C_Map.GetAreaInfo(area) or nil end
function S.MapName(m)
    local info = m and C_Map.GetMapInfo(m)
    return info and info.name or nil
end

-- Berufsstufen. Die Namen der Berufe in Client-Sprache kommen über einen Zauber des Berufs, die Stufen aus
-- der Fertigkeitsliste.
local PROFESSION_SPELL = {
    alchemy = 2259, blacksmithing = 2018, enchanting = 7411, engineering = 4036, herbalism = 2383,
    leatherworking = 2108, mining = 2656, skinning = 8613, tailoring = 3908, cooking = 2550,
    firstaid = 3273, fishing = 7620, lockpicking = 1804, poisons = 2842,
}
local RIDING = { { 33388, 75 }, { 33391, 150 }, { 34090, 225 }, { 34091, 300 } }

-- Aktuelle Stufe eines Berufs; -1, wenn nicht erlernt; nil, wenn der Client keine Fertigkeitsliste kennt
function S.SkillLevel(name)
    if name == "riding" then
        local level = -1
        for _, r in ipairs(RIDING) do
            if IsPlayerSpell and IsPlayerSpell(r[1]) and r[2] > level then level = r[2] end
        end
        return level
    end
    local spell = PROFESSION_SPELL[name]
    local localized = spell and S.SpellName(spell)
    local getLine = C_SkillInfo and C_SkillInfo.GetSkillLineInfo or GetSkillLineInfo
    local getCount = C_SkillInfo and C_SkillInfo.GetNumSkillLines or GetNumSkillLines
    if not (localized and getLine and getCount) then return nil end
    for i = 1, getCount() do
        local skillName, _, _, rank = getLine(i)
        if type(skillName) == "table" then skillName, rank = skillName.name, skillName.rank end
        if skillName == localized then return rank end
    end
    return -1
end

-- Steht der Spieler in Karte m oder in einer ihrer Unterkarten? Sprachunabhaengig über uiMapIDs.
function S.InMap(m)
    if not m then return false end
    local cur = C_Map.GetBestMapForUnit("player")
    local guard = 0
    while cur and cur > 0 and guard < 10 do
        if cur == m then return true end
        local info = C_Map.GetMapInfo(cur)
        cur = info and info.parentMapID
        guard = guard + 1
    end
    return false
end

-- Ist der Ruhestein an Gebiet area gebunden? GetBindLocation und GetAreaInfo liefern beide Client-Sprache.
function S.BoundTo(area)
    local name = area and S.AreaName(area)
    return name ~= nil and GetBindLocation() == name
end

-- Zielpunkt einer goto-Handlung in Weltkoordinaten: x, y, Kontinent
function S.WorldPoint(a)
    if not HBD or not a.x or not a.y then return nil end
    if a.w then return a.x, a.y, a.ci end
    if not a.m then return nil end
    return HBD:GetWorldCoordinatesFromZone(a.x / 100, a.y / 100, a.m)
end

-- Entfernung in Yards; nil, wenn der Punkt auf einem anderen Kontinent liegt.
function S.Distance(a)
    if not HBD then return nil end
    local tx, ty, tci = S.WorldPoint(a)
    if not tx then return nil end
    local px, py, pci = S.PlayerWorld() -- prüft auf geschützte Werte
    if not px or pci ~= tci then return nil end
    return HBD:GetWorldDistance(pci, px, py, tx, ty)
end

-- Spielerposition in Weltkoordinaten: x, y, Kontinent
function S.PlayerWorld()
    if not HBD then return nil end
    local x, y, ci = HBD:GetPlayerWorldPosition()
    if ns.IsSecret and (ns.IsSecret(x) or ns.IsSecret(y) or ns.IsSecret(ci)) then return nil end -- geschützt: Position unbekannt
    return x, y, ci
end

-- Kontinent einer Zone (uiMapID) über ihren Mittelpunkt
function S.ZoneContinent(m)
    if not HBD or not m then return nil end
    local _, _, ci = HBD:GetWorldCoordinatesFromZone(0.5, 0.5, m)
    return ci
end

-- Abstand zweier Weltpunkte desselben Kontinents in Yards
function S.WorldDistance(ci, ax, ay, bx, by)
    if not HBD then return nil end
    return HBD:GetWorldDistance(ci, ax, ay, bx, by)
end
