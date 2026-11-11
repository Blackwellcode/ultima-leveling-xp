-- Plates: Quest-Fortschritt (Daten aus Questie) und Level-Warnung
-- an den EllesmereUI-Nameplates und am EllesmereUI-Zielrahmen. Frueher Teil von !NoashUI.
local _, ns = ...

local WHITE = "Interface\\Buttons\\WHITE8x8"
local SKULL = "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
local FONT = STANDARD_TEXT_FONT
local QUEST_ICON, QUEST_FONT = 20, 15
local DARK = 0.067 -- Rahmenfarbe von EllesmereUI für Einheiten ohne Levelfarbe

local db
local questTooltips
local plateWidgets = {}
local targetWidget

-------------------------------------------------------------------------------
-- Level und Gefahr
-------------------------------------------------------------------------------
local function IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v)
end

-- Farbe nach Levelabstand; nutzt die EllesmereUI-Regel, damit Text und Rahmen gleich sind.
local function LevelColor(unit, level)
    if EllesmereUI and EllesmereUI.GetLevelColor then
        local r, g, b = EllesmereUI.GetLevelColor(unit, level, true)
        if r then return r, g, b end
    end
    if level <= 0 then return 1, 0.1, 0.1 end
    local c = GetQuestDifficultyColor(level)
    return c.r, c.g, c.b
end

local ELITE = { elite = true, rareelite = true, worldboss = true }

-- 0 = keine Warnung, 1 = viel zu hoch
local function DangerTier(unit, level)
    if level <= 0 then return 1 end
    local class = UnitClassification(unit)
    if class == "worldboss" then return 1 end
    local diff = level - UnitLevel("player")
    if diff >= db.dangerDiff then return 1 end
    if ELITE[class] and diff >= db.eliteDangerDiff then return 1 end
    return 0
end

-------------------------------------------------------------------------------
-- Questdaten aus Questie
-------------------------------------------------------------------------------
local function QuestieIcon(iconType)
    if not (Questie and Questie.icons) then return nil end
    if iconType == Questie.ICON_TYPE_SLAY then return Questie.icons.slay end
    if iconType == Questie.ICON_TYPE_TALK then return Questie.icons.talk end
    if iconType == Questie.ICON_TYPE_EVENT then return Questie.icons.event end
    if iconType == Questie.ICON_TYPE_INTERACT then return Questie.icons.interact end
    return Questie.icons.loot
end

-- Liefert Icon, Fortschrittstext und Zahl weiterer offener Ziele für eine NPC-Einheit.
local function QuestInfo(unit)
    if not questTooltips then return nil end
    local guid = UnitGUID(unit)
    if not guid or IsSecret(guid) then return nil end
    local unitType, _, _, _, _, npcId = strsplit("-", guid)
    if (unitType ~= "Creature" and unitType ~= "Vehicle") or not npcId then return nil end
    local entries = questTooltips.lookupByKey["m_" .. npcId]
    if not entries then return nil end

    local first, extra = nil, 0
    for _, entry in pairs(entries) do
        local obj = entry.objective
        if obj and obj.Update then
            obj:Update()
            if not obj.Completed then
                if first then extra = extra + 1 else first = obj end
            end
        end
    end
    if not first then return nil end

    local text = ""
    if first.Needed and first.Needed > 0 then
        text = (first.Collected or 0) .. "/" .. first.Needed
    end
    if extra > 0 then text = text .. " +" .. extra end
    return QuestieIcon(first.Icon), text
end

-------------------------------------------------------------------------------
-- Widgets: Rahmen, Puls, Totenkopf, Questmarker
-------------------------------------------------------------------------------
local function MakeEdges(parent, layer, blend)
    local e = {}
    for i = 1, 4 do
        local t = parent:CreateTexture(nil, layer)
        t:SetTexture(WHITE)
        if blend then t:SetBlendMode(blend) end
        e[i] = t
    end
    return e
end

local function LayoutEdges(e, anchor, gap, size)
    local top, bottom, left, right = e[1], e[2], e[3], e[4]
    for i = 1, 4 do e[i]:ClearAllPoints() end
    top:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", -gap - size, gap)
    top:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", gap + size, gap)
    top:SetHeight(size)
    bottom:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -gap - size, -gap)
    bottom:SetPoint("TOPRIGHT", anchor, "BOTTOMRIGHT", gap + size, -gap)
    bottom:SetHeight(size)
    left:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, gap)
    left:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMLEFT", -gap, -gap)
    left:SetWidth(size)
    right:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, gap)
    right:SetPoint("BOTTOMLEFT", anchor, "BOTTOMRIGHT", gap, -gap)
    right:SetWidth(size)
end

local function ColorEdges(e, r, g, b, a)
    for i = 1, 4 do e[i]:SetVertexColor(r, g, b, a) end
end

local function CreateWidget()
    local w = CreateFrame("Frame", nil, UIParent)
    w:SetFrameStrata("MEDIUM")
    -- Rahmen und Warnung liegen auf eigenem Frame, damit nur sie pulsieren.
    w.warn = CreateFrame("Frame", nil, w)
    w.warn:SetAllPoints(w)
    w.edges = MakeEdges(w.warn, "OVERLAY")
    w.glow = MakeEdges(w.warn, "OVERLAY", "ADD")

    w.pulse = w.warn:CreateAnimationGroup()
    w.pulse:SetLooping("BOUNCE")
    local fade = w.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.55)

    w.skull = w.warn:CreateTexture(nil, "OVERLAY")
    w.skull:SetTexture(SKULL)
    w.skull:SetSize(16, 16)

    w.quest = CreateFrame("Frame", nil, w)
    w.quest:SetSize(1, 1)
    w.quest.icon = w.quest:CreateTexture(nil, "OVERLAY")
    w.quest.text = w.quest:CreateFontString(nil, "OVERLAY")
    w.quest.text:SetFont(FONT, QUEST_FONT, "OUTLINE")
    w.quest.icon:SetSize(QUEST_ICON, QUEST_ICON)
    w.quest.icon:SetPoint("LEFT", w.quest, "LEFT", 0, 0)
    w.quest.text:SetPoint("LEFT", w.quest.icon, "RIGHT", 2, 0)
    return w
end

-- Zeichnet Level-Rahmen, Warnung und Questmarker für eine Einheit am Anker.
-- true, wenn EllesmereUI die Namensplaketten zeichnet: dann liefert Ultima deren dunklen Grundrahmen.
-- Blizzard-Plaketten bekommen nur farbige Rahmen (Level, Gefahr), keinen dauerhaften.
local ownsPlateBorder = false

local function Paint(w, unit, anchor)
    w:SetParent(anchor)
    w:SetFrameLevel(anchor:GetFrameLevel() + 5)
    w:ClearAllPoints()
    w:SetAllPoints(anchor)

    local level = UnitLevel(unit)
    local attackable = UnitCanAttack("player", unit)
    local npc = not UnitIsPlayer(unit)
    local showLevel = level and not IsSecret(level) and not IsSecret(attackable) and attackable and npc

    -- Nameplates haben keinen EllesmereUI-Rahmen mehr (showBorder aus): dieser Rahmen ist der
    -- einzige. Am Zielrahmen, der einen eigenen Rahmen hat, erscheint er nur bei Levelfarbe.
    local tier = 0
    ColorEdges(w.glow, 0, 0, 0, 0)
    if showLevel then
        local r, g, b = LevelColor(unit, level)
        tier = DangerTier(unit, level)
        if tier == 1 then
            LayoutEdges(w.edges, anchor, 0, 3)
            LayoutEdges(w.glow, anchor, 3, 3)
            ColorEdges(w.edges, 1, 0.1, 0.1, 1)
            ColorEdges(w.glow, 1, 0.1, 0.1, 0.45)
        elseif db.border then
            LayoutEdges(w.edges, anchor, 0, 2)
            ColorEdges(w.edges, r, g, b, 1)
        elseif w.isPlate and ownsPlateBorder then
            LayoutEdges(w.edges, anchor, 0, 2)
            ColorEdges(w.edges, DARK, DARK, DARK, 1)
        else
            ColorEdges(w.edges, 0, 0, 0, 0)
        end
    elseif w.isPlate and ownsPlateBorder then
        LayoutEdges(w.edges, anchor, 0, 2)
        ColorEdges(w.edges, DARK, DARK, DARK, 1)
    else
        ColorEdges(w.edges, 0, 0, 0, 0)
    end

    if tier == 1 then
        w.skull:ClearAllPoints()
        w.skull:SetPoint("RIGHT", anchor, "LEFT", -6, 0)
        w.skull:Show()
        if not w.pulse:IsPlaying() then w.pulse:Play() end
    else
        w.skull:Hide()
        w.pulse:Stop()
        w.warn:SetAlpha(1)
    end

    local icon, text = nil, nil
    if npc then icon, text = QuestInfo(unit) end
    if icon then
        w.quest.icon:SetTexture(icon)
        w.quest.text:SetText(text)
        w.quest:ClearAllPoints()
        w.quest:SetPoint(w.questPoint, anchor, w.questRelPoint, w.questX, w.questY)
        w.quest:Show()
    else
        w.quest:Hide()
    end
    w:Show()
end

-------------------------------------------------------------------------------
-- Nameplates
-------------------------------------------------------------------------------
local function PlateAnchor(unit)
    local ns = _G.EllesmereNameplates_NS
    local plate = ns and ns.plates and ns.plates[unit]
    if plate and plate.health then return plate.health end
    return C_NamePlate.GetNamePlateForUnit(unit)
end

local function UpdatePlate(unit)
    local anchor = PlateAnchor(unit)
    local w = plateWidgets[unit]
    if not anchor or not UnitExists(unit) or not db.enabled then
        if w then w:Hide() end
        return
    end
    if not w then
        w = CreateWidget()
        w.questPoint, w.questRelPoint, w.questX, w.questY = "LEFT", "RIGHT", 6, 0
        w.isPlate = true
        plateWidgets[unit] = w
    end
    Paint(w, unit, anchor)
end

local function UpdateAllPlates()
    for _, plate in pairs(C_NamePlate.GetNamePlates()) do
        local unit = plate.namePlateUnitToken
        if unit then UpdatePlate(unit) end
    end
end

-------------------------------------------------------------------------------
-- Zielrahmen
-------------------------------------------------------------------------------
local function UpdateTarget()
    local frame = _G.EllesmereUIUnitFrames_Target or TargetFrame
    if not frame then return end
    if not targetWidget then
        targetWidget = CreateWidget()
        -- Rechts neben dem Rahmen: Level oben, Questmarker darunter.
        targetWidget.questPoint, targetWidget.questRelPoint = "LEFT", "RIGHT"
        targetWidget.questX, targetWidget.questY = 8, -10
        targetWidget.level = targetWidget:CreateFontString(nil, "OVERLAY")
        targetWidget.level:SetFont(FONT, 16, "OUTLINE")
    end
    if not UnitExists("target") then
        targetWidget:Hide()
        return
    end
    Paint(targetWidget, "target", frame)

    local lv = targetWidget.level
    local level = UnitLevel("target")
    if level and not IsSecret(level) then
        lv:ClearAllPoints()
        lv:SetPoint("LEFT", frame, "RIGHT", 8, 9)
        lv:SetText(level > 0 and level or "??")
        lv:SetTextColor(LevelColor("target", level))
        lv:Show()
    else
        lv:Hide()
    end
end

-------------------------------------------------------------------------------
-- Ereignisse
-------------------------------------------------------------------------------
local refreshPending = false
local function RefreshAllSoon()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.2, function()
        refreshPending = false
        UpdateAllPlates()
        UpdateTarget()
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_LOGIN" then
        db = ns.db.questPlates
        ownsPlateBorder = C_AddOns.IsAddOnLoaded("EllesmereUINameplates") and true or false
        if C_AddOns.IsAddOnLoaded("Questie") and QuestieLoader then
            questTooltips = QuestieLoader:ImportModule("QuestieTooltips")
        else
            ns.questieMissing = true -- nur unter /ultima status melden, nicht bei jedem Login
        end
        events:RegisterEvent("NAME_PLATE_UNIT_ADDED")
        events:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("PLAYER_LEVEL_UP")
        events:RegisterEvent("QUEST_LOG_UPDATE")
        events:RegisterEvent("UNIT_LEVEL")
        events:RegisterEvent("UNIT_FACTION")
        events:RegisterEvent("UNIT_CLASSIFICATION_CHANGED")
        events:RegisterUnitEvent("UNIT_QUEST_LOG_CHANGED", "player")
        return
    end
    if event == "NAME_PLATE_UNIT_ADDED" then
        -- Eine Runde warten: EllesmereUI haengt seine Plate im selben Ereignis an.
        C_Timer.After(0, function() UpdatePlate(unit) end)
    elseif event == "NAME_PLATE_UNIT_REMOVED" then
        local w = plateWidgets[unit]
        if w then
            w.pulse:Stop()
            w:Hide()
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        UpdateTarget()
    elseif event == "UNIT_LEVEL" or event == "UNIT_FACTION" or event == "UNIT_CLASSIFICATION_CHANGED" then
        if unit == "target" then UpdateTarget()
        elseif plateWidgets[unit] then UpdatePlate(unit) end
    else
        RefreshAllSoon()
    end
end)

-- /ultima und das Optionsfenster zeichnen nach jeder Änderung neu.
ns.RefreshQuestPlates = RefreshAllSoon

