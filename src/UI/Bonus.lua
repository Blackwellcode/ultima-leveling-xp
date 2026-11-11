-- Bonus: Forever-Vorteile als Kacheln im Panel (früher eigene Wächter-Leiste).
-- Grün = genutzt, gelb = läuft bald aus, rot = du verschenkst etwas, grau = gerade nicht relevant.
--
-- Erkennung in jeder Client-Sprache, Zauber-IDs geprüft 2026-11-09:
--   Essen      Referenzzauber 19705 "Well Fed" (Ausdauer/Willenskraft +2, 15 min); alle Well-Fed-Buffs tragen
--              diesen Namen, gesucht wird über den Namen in Client-Sprache.
--   Schlafsack Item 211527 "Cozy Sleeping Bag" (Benutzen: 429961 "Unroll Bag"), Buff 429959 "Well-Rested":
--              +1 % Erfahrung je Stapel (Quests und Kills), bis 3 Stapel, 2 Stunden, bleibt nach dem Tod.
--              Nicht verwechseln mit 1225478 "Well Rested" (Legacy-Vorteil, schnellerer Erholt-Vorrat).
--   Camp       Buff 1229741 "Camp Benefits" (1 Stunde). Lagerfeuer-Items über den Namen, IDs werden gemerkt.
local _, ns = ...
local B = {}
ns.Bonus = B
local L = ns.L
local S = ns.State
local MAX_RESTED = 1.5       -- Erholt-Vorrat höchstens 150 % eines Levels
local SOON = 120             -- Sekunden, ab denen ein Buff als "läuft aus" gilt
local GROUP_GAP = 5          -- Level-Abstand, ab dem ein Mitspieler deine Kill-XP spürbar senkt
local BAG_ITEM_ID = 211527   -- Cozy Sleeping Bag
local REF_SPELL = { food = 19705, bag = 429959, camp = 1229741 }                     -- siehe Kopf
local AURA_ID = { bag = 429959, camp = 1229741 } -- direkt per ID abfragbar (Essen: viele IDs, nur über den Namen)
local ENGLISH = { food = "Well Fed", bag = "Well-Rested", camp = "Camp Benefits" }   -- Rückfall: englischer Client
local LEARN = { bag = true, camp = true } -- abweichende IDs im Spiel merken (z. B. nach einem Patch)

local COLORS = {
    ok = { 0.35, 0.85, 0.40 },
    warn = { 1.00, 0.82, 0.20 },
    bad = { 1.00, 0.25, 0.20 },
    off = { 0.50, 0.50, 0.50 },
    rest = { 0.40, 0.65, 1.00 },
}
B.COLORS = COLORS

local function PlayerAura(name)
    if not (name and C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName) then return nil end
    return C_UnitAuras.GetAuraDataBySpellName("player", name, "HELPFUL")
end

-- Buff suchen: bekannte und gelernte ID, dann Name der IDs (Client-Sprache), dann Englisch.
local function FindAura(key)
    local learned = ns.db.auraIds and ns.db.auraIds[key]
    if C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
        for _, id in ipairs({ AURA_ID[key], learned }) do
            local aura = C_UnitAuras.GetPlayerAuraBySpellID(id)
            if aura and not ns.IsSecret(aura) and not ns.IsSecret(aura.expirationTime)
                and not ns.IsSecret(aura.applications) then
                return aura
            end
        end
    end
    local names = {}
    if learned then names[#names + 1] = S.SpellName(learned) end
    if REF_SPELL[key] then names[#names + 1] = S.SpellName(REF_SPELL[key]) end
    names[#names + 1] = ENGLISH[key]
    for _, name in ipairs(names) do
        local aura = PlayerAura(name)
        if aura and (ns.IsSecret(aura) or ns.IsSecret(aura.expirationTime) or ns.IsSecret(aura.applications)) then
            return nil -- geschützt: keine Aussage
        end
        if aura then
            if LEARN[key] and aura.spellId and ns.db.auraIds[key] ~= aura.spellId then
                ns.db.auraIds[key] = aura.spellId
            end
            return aura
        end
    end
    return nil
end

-- Name des Well-Fed-Buffs in Client-Sprache, klein geschrieben (für die Tooltip-Suche)
local function FoodWord()
    local name = S.SpellName(REF_SPELL.food)
    return name and name:lower() or nil
end

local function Remaining(aura)
    if aura.expirationTime and aura.expirationTime > 0 then
        return aura.expirationTime - GetTime()
    end
    return nil
end

local function Clock(seconds)
    if seconds >= 60 then return math.floor(seconds / 60) .. "m" end
    return math.floor(seconds) .. "s"
end

-------------------------------------------------------------------------------
-- Prüfungen: Zustand, Kachel-Status (kurz) und Erklärung, oder nil (ausblenden)
-------------------------------------------------------------------------------
local function CheckRested()
    local max = UnitXPMax("player")
    local rested = GetXPExhaustion() or 0
    local pct = max > 0 and rested / max or 0
    local status = ("%d %%%s"):format(math.floor(pct * 100 + 0.5), IsResting() and " Zz" or "")
    if pct >= MAX_RESTED - 0.01 then
        return "bad", status, L["Rested pool full (150 %). Further rest is wasted, go kill monsters."]
    end
    if rested == 0 then
        return "off", status, L["No rested pool. Log out in an inn or a capital to build it up."]
    end
    return "rest", status, L["Rested doubles your kill XP. Logging out in an inn fills it further."]
end

local function CheckFood()
    local aura = FindAura("food")
    if aura then
        local left = Remaining(aura)
        if left and left < SOON then
            return "warn", Clock(left), L["Well Fed runs out soon (+5 % kill XP)."]
        end
        return "ok", left and Clock(left) or L["active"], L["Well Fed active: +5 % kill XP."]
    end
    -- In Stadt oder Gasthaus kämpfst du nicht, dort ist fehlendes Essen kein Verlust.
    if IsResting() then
        return "off", "-", L["Not Well Fed. Eat buff food before leveling: 15 minutes of +5 % kill XP."]
    end
    return "bad", L["missing"], L["Not Well Fed. Buff food gives 15 minutes of +5 % kill XP."]
end

local function BagCount()
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(BAG_ITEM_ID) or 0 end
    return GetItemCount and GetItemCount(BAG_ITEM_ID) or 0
end

local function CheckBag()
    local aura = FindAura("bag")
    if aura then
        local stacks = aura.applications or 1
        if stacks < 3 then
            return "warn", stacks .. "/3",
                ns.F("Sleeping bag buff at %d of 3 stacks. Rest on the bag longer: up to +3 %% XP.", stacks)
        end
        return "ok", "3/3", L["Sleeping bag buff full: +3 % XP, persists through death."]
    end
    if BagCount() > 0 then
        return "bad", "0/3", L["Cozy Sleeping Bag is in your bags, but its buff is missing. Place it and lie down: up to +3 % XP."]
    end
    return "off", "-", L["No Cozy Sleeping Bag in your bags. It is the reward of a quest chain across both continents."]
end

local function CheckGroup()
    if not ns.db.groupWarn or not IsInGroup() then return nil end
    local mine = UnitLevel("player")
    local prefix = IsInRaid() and "raid" or "party"
    local count = IsInRaid() and GetNumGroupMembers() or GetNumGroupMembers() - 1
    local highest, who = mine, nil
    for i = 1, count do
        local unit = prefix .. i
        local level = UnitExists(unit) and UnitLevel(unit)
        if ns.IsSecret(level) then level = nil end -- im Kampf geschuetzt: diesen Mitspieler auslassen
        if level and level > highest then highest, who = level, UnitName(unit) end
    end
    local gap = highest - mine
    if gap >= GROUP_GAP then
        return "bad", ns.F("Group +%d", gap),
            ns.F("%s is %d levels higher. Higher group members lower your kill XP noticeably.", who or "?", gap)
    end
    return "ok", L["Group"], ns.F("No group member %d or more levels above you.", GROUP_GAP)
end

-- Zählt Quests im Log unter der Überschrift mit dem Namen der aktuellen Instanz (beides Client-Sprache).
local function CheckDungeon()
    local _, kind = IsInInstance()
    if kind ~= "party" then return nil end
    local name = GetInstanceInfo()
    local header, quests = nil, 0
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info then
            if info.isHeader then
                header = info.title
            elseif header == name then
                quests = quests + 1
            end
        end
    end
    if quests == 0 then
        return "bad", ns.F("Dungeon %d Q", 0),
            ns.F("No quests for %s in your log. Accept dungeon quests first, then one run gives quest and kill XP.", name)
    end
    return "ok", ns.F("Dungeon %d Q", quests), ns.F("%d quests for %s in your log.", quests, name)
end

-- Gefahr: sichtbare Gegner, die deutlich über deinem Level liegen (über die Namensplaketten).
-- Routen sind für zügiges Leveln geschrieben und führen auch an Gegnern vorbei, die 3 und mehr Level
-- über dir sind; dann warnt Ultima, statt dich ahnungslos hineinlaufen zu lassen.
local function CheckDanger()
    if not ns.db.dangerWarn or not (C_NamePlate and C_NamePlate.GetNamePlates) then return nil end
    local DANGER_GAP = ns.db.dangerGap
    local mine = UnitLevel("player")
    local highest, count = 0, 0
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken
        if unit and UnitExists(unit) then
            local attackable, level, dead = UnitCanAttack("player", unit), UnitLevel(unit), UnitIsDead(unit)
            if not (ns.IsSecret(attackable) or ns.IsSecret(level) or ns.IsSecret(dead)) and attackable and not dead
                and level and (level == -1 or level >= mine + DANGER_GAP) then
                count = count + 1
                local shown = level == -1 and mine + 10 or level
                if shown > highest then highest = shown end
            end
        end
    end
    if count == 0 then return nil end
    return "bad", ns.F("Danger: enemies up to level %d", highest),
        ns.F("%d enemies here are %d or more levels above you. Level up first or skip this step with >.", count, DANGER_GAP)
end

-- Camping: Sammelbuff "Camp Benefits" nach 1 Minute /sit am Lagerfeuer (Warcraft Tavern, Camping Guide).
local function CheckCamp()
    local aura = FindAura("camp")
    if aura then
        local left = Remaining(aura)
        if left and left < SOON then return "warn", Clock(left), L["Camp Benefits runs out soon."] end
        return "ok", left and Clock(left) or L["active"], L["Camp Benefits active."]
    end
    return "off", "-", L["No camp buff. Sitting at a campfire for 1 minute (/sit) grants the buffs of the camp objects."]
end

-------------------------------------------------------------------------------
-- Gegenstände in den Taschen: Buff-Essen, Schlafsack, Lagerfeuer.
-- Buff-Essen erkennt Ultima am Tooltip (Well-Fed-Name in Client-Sprache oder "well fed").
-- Ergebnisse je Item-ID werden gemerkt, die Taschen nur nach BAG_UPDATE_DELAYED neu durchsucht.
-------------------------------------------------------------------------------
local isFood, bagCache = {}, nil

local function ItemName(id)
    if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
    return (GetItemInfo(id))
end

local function ItemIcon(id)
    if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
    return GetItemIcon and GetItemIcon(id) or nil
end

-- Zeilen des Tooltips eines Taschenplatzes. Erst über C_TooltipInfo, sonst über einen unsichtbaren
-- eigenen Tooltip (geht in jedem Client). Liefert eine Liste von Texten oder nil (noch nicht geladen).
local scanTip
local function TooltipLines(bag, slot)
    local lines = {}
    if C_TooltipInfo and C_TooltipInfo.GetBagItem then
        local data = C_TooltipInfo.GetBagItem(bag, slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                if TooltipUtil and TooltipUtil.SurfaceArgs and not line.leftText then TooltipUtil.SurfaceArgs(line) end
                if type(line.leftText) == "string" then lines[#lines + 1] = line.leftText end
            end
        end
    end
    if #lines < 2 and CreateFrame and GameTooltip then
        scanTip = scanTip or CreateFrame("GameTooltip", "UltimaScanTip", nil, "GameTooltipTemplate")
        scanTip:SetOwner(WorldFrame, "ANCHOR_NONE")
        scanTip:ClearLines()
        scanTip:SetBagItem(bag, slot)
        lines = {}
        for i = 1, scanTip:NumLines() or 0 do
            local left = _G["UltimaScanTipTextLeft" .. i]
            local text = left and left:GetText()
            if type(text) == "string" then lines[#lines + 1] = text end
        end
        scanTip:Hide()
    end
    -- Gegenstand noch nicht im Cache: der Tooltip zeigt dann nur einen Platzhalter
    if #lines < 2 then return nil end
    if RETRIEVING_ITEM_INFO and lines[1] == RETRIEVING_ITEM_INFO then return nil end
    return lines
end

local function GivesWellFed(bag, slot, id)
    if isFood[id] ~= nil then return isFood[id] end
    local lines = TooltipLines(bag, slot)
    if not lines then return false end -- noch nicht geladen: nicht merken, beim nächsten Durchlauf erneut prüfen
    local word = FoodWord()
    local found = false
    for _, text in ipairs(lines) do
        text = text:lower()
        if (word and text:find(word, 1, true)) or text:find("well fed", 1, true) then
            found = true
            break
        end
    end
    isFood[id] = found
    return found
end

local function IsCampfire(id, name)
    if ns.db.campItems[id] then return true end
    if name:find("Campfire", 1, true) then
        ns.db.campItems[id] = true -- gemerkt: klappt danach auch in anderen Client-Sprachen
        return true
    end
    return false
end

local LAST_BAG = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 -- Rucksack plus Taschen (und Reagenzientasche)

local function ScanBags()
    local found = {}
    for bag = 0, LAST_BAG do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id then
                local name = ItemName(id) or ""
                if not found.food and GivesWellFed(bag, slot, id) then found.food = id end
                if not found.bag and id == BAG_ITEM_ID then found.bag = id end
                if not found.camp and IsCampfire(id, name) then found.camp = id end
            end
        end
    end
    return found
end

function B.BagsChanged() bagCache = nil end

local function Bags()
    if not bagCache then bagCache = ScanBags() end
    return bagCache
end

-- Für /ultima debug: was die Taschensuche gefunden hat
function B.DebugBags()
    local bags = Bags()
    local food = bags.food and (ItemName(bags.food) or tostring(bags.food)) or "-"
    local known = 0
    for _, v in pairs(isFood) do if v then known = known + 1 end end
    return ("food %s, bag %s, campfire %s, food items known %d"):format(food, tostring(bags.bag or "-"),
        tostring(bags.camp or "-"), known)
end

-------------------------------------------------------------------------------
-- Kacheln für das Panel: immer vier (Erholt, Essen, Schlafsack, Camp), dazu Warnungen.
-- action = { type = "item", item = id } (geschützter Klick) oder { type = "route" }
-------------------------------------------------------------------------------
local ICON = {
    rested = "Interface/Icons/Spell_Nature_Sleep",
    food = "Interface/Icons/INV_Misc_Food_15",
    bag = "Interface/Icons/INV_Misc_Bag_10",
    camp = "Interface/Icons/Spell_Fire_Fire",
}

local lastState, primed = {}, false

-- Wechselt eine Kachel oder Warnung auf Rot, erscheint einmal ein Hinweis in der Bildschirmmitte.
local ANNOUNCE_GAP = 60 -- Sekunden: dieselbe Warnung höchstens einmal je Minute
local lastAnnounce = {}
local function Announce(key, state, tip)
    if primed and state == "bad" and lastState[key] ~= "bad" and ns.db.announce
        and GetTime() - (lastAnnounce[key] or -ANNOUNCE_GAP) >= ANNOUNCE_GAP then
        lastAnnounce[key] = GetTime()
        local c = COLORS.bad
        UIErrorsFrame:AddMessage("Ultima: " .. tip, c[1], c[2], c[3])
    end
    lastState[key] = state
end

local lastTiles, lastAlerts

function B.Tiles()
    -- Im Kampf sind Buff-Daten geschützt: letzten Stand zeigen statt geschützte Werte anzufassen
    if ns.AurasSecret() or InCombatLockdown() then
        if lastTiles then return lastTiles, lastAlerts end
        -- erster Aufruf mitten im Kampf (nach /reload): neutrale Kacheln statt geschützte Buff-Daten zu lesen
        local idle = {}
        for i, key in ipairs({ "rested", "food", "bag", "camp" }) do
            idle[i] = { key = key, title = L[({ rested = "Rested", food = "Food", bag = "Sleeping bag", camp = "Camp" })[key]],
                icon = ICON[key], state = "off", status = "-", tip = "" }
        end
        return idle, {}
    end
    local bags = Bags()
    local tiles = {}
    local maxLevel = UnitLevel("player") >= GetMaxPlayerLevel()

    local rState, rStatus, rTip = CheckRested()
    tiles[1] = { key = "rested", title = L["Rested"], icon = ICON.rested, state = rState, status = rStatus, tip = rTip }

    local fState, fStatus, fTip = CheckFood()
    local food = { key = "food", title = L["Food"], icon = bags.food and ItemIcon(bags.food) or ICON.food,
        state = fState, status = fStatus, tip = fTip }
    if fState ~= "ok" then
        if bags.food then
            food.action = { type = "item", item = bags.food }
            food.actionText = L["Eat"]
            food.tip = fTip .. "\n" .. ns.F("Click: eat %s.", ItemName(bags.food) or L["buff food"])
        else
            food.tip = fTip .. "\n" .. L["No buff food in your bags."]
        end
    end
    tiles[2] = food

    local bState, bStatus, bTip = CheckBag()
    local bagTile = { key = "bag", title = L["Sleeping bag"], icon = bags.bag and ItemIcon(bags.bag) or ICON.bag,
        state = bState, status = bStatus, tip = bTip }
    if bState ~= "ok" and bState ~= "warn" then
        if bags.bag then
            bagTile.action = { type = "item", item = bags.bag }
            bagTile.actionText = L["Place"]
            bagTile.tip = L["Click: place the Cozy Sleeping Bag, then lie down. Up to +3 % XP."]
        elseif UnitLevel("player") >= 14 then
            bagTile.action = { type = "route" }
            bagTile.actionText = L["Quest chain"]
            bagTile.status = L["not owned"]
            bagTile.state = "warn"
            bagTile.tip = L["Click: Ultima guides you through the quest chain for the Cozy Sleeping Bag (6 quests, both continents). Your route continues afterwards."]
        else
            bagTile.status = L["from level 14"]
            bagTile.tip = L["The quest chain for the Cozy Sleeping Bag starts at level 14."]
        end
    end
    if bagTile.status == "-" then bagTile.status = L["not owned"] end
    tiles[3] = bagTile

    local cState, cStatus, cTip = CheckCamp()
    local camp = { key = "camp", title = L["Camp"], icon = ICON.camp, state = cState, status = cStatus, tip = cTip }
    if cState ~= "ok" and bags.camp then
        camp.action = { type = "item", item = bags.camp }
        camp.actionText = L["Light"]
        camp.tip = cTip .. "\n" .. ns.F("Click: set up %s.", ItemName(bags.camp) or L["campfire"])
    end
    tiles[4] = camp

    if not maxLevel then
        for _, t in ipairs(tiles) do Announce(t.key, t.state, t.tip) end
    end

    -- Warnungen nur, wenn sie zutreffen (Gruppe, Dungeon)
    local alerts = {}
    for _, check in ipairs({ { "danger", CheckDanger }, { "group", CheckGroup }, { "dungeon", CheckDungeon } }) do
        local key, state, text, tip = check[1], check[2]()
        if state then
            alerts[#alerts + 1] = { state = state, text = text, tip = tip }
            if not maxLevel then Announce(key, state, tip) end
        end
    end
    primed = true
    lastTiles, lastAlerts = tiles, alerts
    return tiles, alerts
end
