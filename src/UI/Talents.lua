-- Leveling-Talente im Talentfenster:
--   unter jedem Talent des Builds der Zielrang bei deiner Punktzahl (grün = passt, gelb = noch offen,
--   rot = mehr Punkte als vorgesehen oder nicht im Build), ein Leuchten auf dem nächsten Punkt und rechts
--   neben dem Fenster eine Karte mit Build-Wahl, freien Punkten und den nächsten Punkten.
-- Ultima legt nur eigene Rahmen über das Fenster, verändert keine Blizzard-Frames und lernt keine Talente.
-- Das Talentfenster (Addon Blizzard_PlayerSpells) lädt erst beim ersten Öffnen; Ultima hängt sich dann an.
-- Dazu eine Chat-Erinnerung, sobald ein Punkt frei ist (Option).
local _, ns = ...
local L = ns.L
local T = ns.Talents
local C, A1 = ns.COLORS, ns.ACCENT

local CARD_W, PAD, ROW_H, ICON = 236, 12, 30, 22
local card, glow, hooked
local labels, rows = {}, {}
local refreshQueued = false
local lastReminder

local function TalentsFrame()
    local spells = _G.PlayerSpellsFrame
    return spells and spells.TalentsFrame, spells
end

-------------------------------------------------------------------------------
-- Talent-Knöpfe des Fensters je Knoten
-------------------------------------------------------------------------------
local function ButtonMap(tf)
    local map = {}
    if tf.EnumerateAllTalentButtons then
        for button in tf:EnumerateAllTalentButtons() do
            local id = (button.GetNodeID and button:GetNodeID()) or button.nodeID or (button.nodeInfo and button.nodeInfo.ID)
            if id then map[id] = button end
        end
    end
    return map
end

local function ButtonFor(tf, map, nodeID)
    local button = map[nodeID]
    if not button and tf.GetTalentButtonByNodeID then button = tf:GetTalentButtonByNodeID(nodeID) end
    return button
end

-------------------------------------------------------------------------------
-- Zielrang unter den Talenten
-------------------------------------------------------------------------------
local function Label(i, parent)
    local l = labels[i]
    if not l then
        l = CreateFrame("Frame", nil, parent)
        l:SetSize(30, 13)
        l.bg = l:CreateTexture(nil, "BACKGROUND")
        l.bg:SetAllPoints()
        l.bg:SetColorTexture(C.panel[1], C.panel[2], C.panel[3], 0.9)
        l.text = ns.Label(l, 10, C.text, "OVERLAY", "Bold")
        l.text:SetPoint("CENTER")
        labels[i] = l
    end
    l:SetParent(parent)
    return l
end

local function HideMarks()
    for _, l in ipairs(labels) do l:Hide() end
    if glow then
        glow.pulse:Stop()
        glow:Hide()
    end
end

local function DrawTargets(tf, plan)
    local map = ButtonMap(tf)
    local n = 0
    for _, node in ipairs(plan.tree.nodes) do
        local target = plan.want[node.id] or 0
        local final = plan.final[node.id] or 0
        if target > 0 or final > 0 or node.ranks > 0 then
            local button = ButtonFor(tf, map, node.id)
            if button and button:IsVisible() then
                n = n + 1
                local l = Label(n, tf)
                l:ClearAllPoints()
                l:SetPoint("TOP", button, "BOTTOM", 0, -1)
                l:SetFrameLevel((button:GetFrameLevel() or 1) + 12)
                -- Zielrang jetzt; ist das Talent erst später dran, dessen Endrang gedimmt
                local shown = target > 0 and target or final
                l.text:SetText(("%d/%d"):format(shown, node.max))
                local color
                if node.ranks > target then color = C.bad
                elseif target == 0 then color = C.text3
                elseif node.ranks < target then color = C.warn
                else color = C.ok end
                l.text:SetTextColor(color[1], color[2], color[3])
                l:SetWidth((l.text:GetStringWidth() or 20) + 6)
                l:Show()
            end
        end
    end
    -- Leuchten auf dem nächsten Punkt, wenn einer frei ist
    local nextStep = plan.next[1]
    local button = nextStep and nextStep.ready and nextStep.node and ButtonFor(tf, map, nextStep.node.id)
    if not (button and button:IsVisible()) then
        if glow then glow.pulse:Stop(); glow:Hide() end
        return
    end
    if not glow then
        glow = CreateFrame("Frame", nil, tf)
        glow.tex = glow:CreateTexture(nil, "OVERLAY")
        glow.tex:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        glow.tex:SetBlendMode("ADD")
        glow.tex:SetVertexColor(A1[1], A1[2], A1[3], 1)
        glow.tex:SetPoint("CENTER")
        glow.pulse = glow:CreateAnimationGroup()
        glow.pulse:SetLooping("BOUNCE")
        local fade = glow.pulse:CreateAnimation("Alpha")
        fade:SetFromAlpha(1)
        fade:SetToAlpha(0.35)
        fade:SetDuration(0.6)
    end
    glow:SetParent(tf)
    glow:ClearAllPoints()
    glow:SetAllPoints(button)
    glow:SetFrameLevel((button:GetFrameLevel() or 1) + 10)
    local size = (button:GetWidth() or 40) * 1.9
    glow.tex:SetSize(size, size)
    glow:Show()
    if not glow.pulse:IsPlaying() then glow.pulse:Play() end
end

-------------------------------------------------------------------------------
-- Karte neben dem Fenster
-------------------------------------------------------------------------------
-- Ruhiger Symbol-Knopf (Pfeil links oder rechts): ohne Fläche, beim Darüberfahren die erhöhte Fläche
-- Symbol-Knopf aus dem gemeinsamen Baukasten (Kit.lua, Hausstil 1.2.0)
local function GlyphButton(parent, glyph, onClick)
    local b = ns.IconButton(parent, glyph, 24)
    b:SetScript("OnClick", onClick)
    return b
end

-- Build wechseln: automatisch -> 1 -> 2 -> ... -> automatisch
local function Cycle(delta)
    local builds = T.Builds()
    local count = #builds
    if count == 0 then return end
    local current = ns.cdb.talentBuild or 0
    local nextIndex = (current + delta) % (count + 1)
    T.Select(nextIndex > 0 and nextIndex or nil)
    ns.RefreshTalents()
end

local function Row(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, card)
    row:SetSize(CARD_W - 2 * PAD, ROW_H)
    row.icon = ns.Icon(row, ICON)
    row.icon:SetPoint("LEFT", 0, 0)
    row.name = ns.Label(row, 12, C.text, "OVERLAY", "Medium")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, 1)
    row.name:SetJustifyH("LEFT")
    row.info = ns.Label(row, 10, C.text2, "OVERLAY")
    row.info:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, -1)
    row.info:SetJustifyH("LEFT")
    rows[i] = row
    return row
end

local function Build(parent)
    card = CreateFrame("Frame", "UltimaTalentCard", parent)
    card:SetWidth(CARD_W)
    card:SetFrameStrata("HIGH")
    ns.Round(card, "shadow", 24, { 0, 0, 0, 0.6 }, "BACKGROUND", -2, 14)
    ns.Round(card, "round", ns.Theme.radius.panel, C.panel, "BACKGROUND")
    ns.Round(card, "ring", ns.Theme.radius.panel, C.cardBorder, "BORDER")
    card.title = ns.Label(card, ns.Theme.size.heading, C.text, "OVERLAY", "Bold")
    card.title:SetPoint("TOPLEFT", PAD, -PAD)
    card.title:SetJustifyH("LEFT")
    card.prev = GlyphButton(card, "left", function() Cycle(-1) end)
    card.prev:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -8)
    card.nextButton = GlyphButton(card, "right", function() Cycle(1) end)
    card.nextButton:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, -PAD - 21)
    card.build = ns.Label(card, 12, C.text, "OVERLAY", "Medium")
    card.build:SetPoint("LEFT", card.prev, "RIGHT", 6, 0)
    card.build:SetJustifyH("CENTER")
    -- Variante und Art der Wahl in eigener Zeile über die volle Breite
    card.mode = ns.Label(card, 10, C.text3, "OVERLAY")
    card.mode:SetPoint("TOPLEFT", card.prev, "BOTTOMLEFT", 0, -4)
    card.mode:SetJustifyH("CENTER")
    card.points = ns.Label(card, 11, C.text2, "OVERLAY")
    card.points:SetPoint("TOPLEFT", card.mode, "BOTTOMLEFT", 0, -10)
    card.points:SetJustifyH("LEFT")
    card.spent = ns.Label(card, 10, C.text3, "OVERLAY")
    card.spent:SetPoint("TOPLEFT", card.points, "BOTTOMLEFT", 0, -3)
    card.spent:SetJustifyH("LEFT")
    card.note = ns.Label(card, 11, C.text2, "OVERLAY")
    card.note:SetJustifyH("LEFT")
    card.note:SetWordWrap(true)
    card.rows = rows -- für den Oberflächen-Test (Breiten aller Zeilen)
end

-- Zeilen unter der Liste: Warnungen und Hinweise
local function Notes(plan)
    local list = {}
    if plan.respec then
        list[#list + 1] = { ns.F("Level %d reached: respec to the full build.", plan.build.preUntil), C.warn }
    elseif #plan.wrong > 0 then
        list[#list + 1] = { ns.F("%d talents differ from the build.", #plan.wrong), C.bad }
    end
    if plan.missing > 0 then
        list[#list + 1] = { ns.F("%d build talents not found in your talent tree.", plan.missing), C.text3 }
    end
    if #plan.next == 0 then list[#list + 1] = { L["Build complete."], C.ok } end
    return list
end

local function FillCard(plan, err)
    local inner = CARD_W - 2 * PAD
    card.title:SetText(L["Leveling talents"])
    ns.Fit(card.title, inner, 10)
    for _, row in ipairs(rows) do row:Hide() end
    if not plan then
        card.prev:Hide(); card.nextButton:Hide(); card.build:SetText(""); card.mode:SetText("")
        card.points:SetText(err == "no build for this class" and L["No leveling build for your class."]
            or ns.F("Talent tree not readable: %s", tostring(err)))
        card.points:SetWidth(inner)
        card.points:SetWordWrap(true)
        card.note:Hide()
        card.spent:Hide()
        card:SetHeight(PAD * 2 + 20 + 30 + (card.points:GetStringHeight() or 14))
        return
    end
    card.prev:Show(); card.nextButton:Show(); card.note:Show()
    card.points:SetWordWrap(false)
    card.build:SetText(T.SpecName(plan.build, plan.tree))
    ns.Fit(card.build, inner - 2 * 22 - 12, 9)
    local mode = ns.cdb.talentBuild and ns.F("Build %d of %d", plan.index, #T.Builds()) or L["Automatic choice"]
    local variant = T.VariantName(plan.build)
    card.mode:SetText(variant and (variant .. ", " .. mode) or mode)
    ns.Fit(card.mode, inner, 8)
    card.points:SetText(ns.F("Free talent points: %d", plan.free))
    local free = plan.free > 0 and A1 or C.text2
    card.points:SetTextColor(free[1], free[2], free[3])
    ns.Fit(card.points, inner, 9)
    card.spent:SetText(ns.F("Spent: %d of %d", plan.spent, plan.total))
    ns.Fit(card.spent, inner, 8)
    card.spent:Show()

    local anchor, y = card.spent, 0
    for i, step in ipairs(plan.next) do
        local row = Row(i)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, i == 1 and -10 or -4)
        local name = (step.node and step.node.name) or T.SpellName(step.spell) or ("#" .. step.spell)
        local max = step.node and step.node.max or step.rank
        row.icon:SetTexture(T.SpellIcon(step.spell) or "Interface\\Icons\\INV_Misc_QuestionMark")
        row.icon:SetDesaturated(not step.ready)
        row.name:SetText(("%s  %d/%d"):format(name, step.rank, max))
        local color = step.ready and C.text or C.text2
        row.name:SetTextColor(color[1], color[2], color[3])
        ns.Fit(row.name, inner - ICON - 8, 9)
        if step.ready then
            row.info:SetText(L["Ready"])
            row.info:SetTextColor(A1[1], A1[2], A1[3])
        else
            row.info:SetText(ns.F("Point %d, level %d", step.point, step.level))
            row.info:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
        end
        ns.Fit(row.info, inner - ICON - 8, 8)
        row:Show()
        anchor = row
        y = y + ROW_H + (i == 1 and 10 or 4)
    end

    local notes = Notes(plan)
    local text = {}
    for _, n in ipairs(notes) do
        text[#text + 1] = ("|cff%02x%02x%02x%s|r"):format(n[2][1] * 255, n[2][2] * 255, n[2][3] * 255, n[1])
    end
    card.note:ClearAllPoints()
    card.note:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -10)
    card.note:SetWidth(inner)
    card.note:SetText(table.concat(text, "\n"))
    local noteH = #text > 0 and ((card.note:GetStringHeight() or 0) + 10) or 0
    -- Titel, Build-Zeile, Variante/Modus, Punkte, Verteilt, Liste, Hinweise
    card:SetHeight(PAD + 16 + 8 + 22 + 4 + 12 + 10 + 14 + 3 + 12 + y + noteH + PAD)
end

-------------------------------------------------------------------------------
-- Aktualisieren
-------------------------------------------------------------------------------
local function Refresh()
    refreshQueued = false
    local tf, spells = TalentsFrame()
    if not (tf and spells) then return end
    if not (ns.db and ns.db.talents.overlay) or not tf:IsVisible() then
        HideMarks()
        if card then card:Hide() end
        return
    end
    T.Invalidate()
    local plan, err = T.Plan()
    if not card then Build(spells) end
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", spells, "TOPRIGHT", 6, 0)
    FillCard(plan, err)
    card:Show()
    HideMarks()
    if plan then DrawTargets(tf, plan) end
end

-- Mehrere Ereignisse kurz hintereinander (Punkt gesetzt, Baum neu gezeichnet) ergeben eine Aktualisierung
function ns.RefreshTalents()
    if refreshQueued then return end
    refreshQueued = true
    C_Timer.After(0.2, function() ns.Guard("Talents", Refresh) end)
end

local function Hook()
    if hooked then return end
    local tf = TalentsFrame()
    if not tf then return end
    hooked = true
    tf:HookScript("OnShow", ns.RefreshTalents)
    tf:HookScript("OnHide", function()
        HideMarks()
        if card then card:Hide() end
    end)
    -- Baum neu gezeichnet (Punkt gesetzt, Spezialisierung umgeschaltet)
    if tf.UpdateTreeCurrencyInfo then hooksecurefunc(tf, "UpdateTreeCurrencyInfo", ns.RefreshTalents) end
    ns.RefreshTalents()
end

-- Erinnerung im Chat, sobald ein Punkt frei ist (einmal je Punktzahl)
local function Remind()
    if not (ns.db and ns.db.talents.remind) then return end
    T.Invalidate()
    local plan = T.Plan()
    local step = plan and plan.next[1]
    if not (step and step.ready) or lastReminder == plan.total then return end
    lastReminder = plan.total
    local name = (step.node and step.node.name) or T.SpellName(step.spell) or ("#" .. step.spell)
    print(ns.PREFIX .. ns.F("Talent point free: %s (%d/%d)", name, step.rank, step.node.max))
end

local EVENTS = {
    "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP",
    "TRAIT_CONFIG_UPDATED", "TRAIT_NODE_CHANGED", "TRAIT_TREE_CURRENCY_INFO_UPDATED",
}

ns.On("READY", function()
    local frame = CreateFrame("Frame")
    for _, event in ipairs(EVENTS) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns.missingEvents = ns.missingEvents or {}
            ns.missingEvents[#ns.missingEvents + 1] = event
        end
    end
    frame:SetScript("OnEvent", function(_, event, arg1)
        if event == "ADDON_LOADED" then
            if arg1 == "Blizzard_PlayerSpells" then ns.Guard("Talents", Hook) end
            return
        end
        T.Invalidate()
        if event == "PLAYER_ENTERING_WORLD" then
            ns.Guard("Talents", Hook) -- Fenster schon geladen (z. B. nach /reload)
            -- beim Einloggen nicht sofort erinnern, erst nach dem Laden des Spielers
            C_Timer.After(5, function() ns.Guard("Talents", Remind) end)
            return
        end
        if event == "PLAYER_LEVEL_UP" or event == "TRAIT_TREE_CURRENCY_INFO_UPDATED" then
            -- die neue Stufe steht erst kurz nach dem Ereignis in UnitLevel
            C_Timer.After(1, function() ns.Guard("Talents", Remind) end)
        end
        ns.RefreshTalents()
    end)
end)

-- Für /ultima talents: Stand als Textzeilen
function ns.TalentReport()
    T.Invalidate()
    local plan, err = T.Plan()
    if not plan then
        return { err == "no build for this class" and L["No leveling build for your class."]
            or ns.F("Talent tree not readable: %s", tostring(err)) }
    end
    local lines = {
        ns.F("Build: %s", T.BuildName(plan.build, plan.tree)) .. "  (" .. (ns.cdb.talentBuild and ns.F("Build %d of %d", plan.index, #T.Builds()) or L["Automatic choice"]) .. ")",
        ns.F("Free talent points: %d", plan.free) .. "   " .. ns.F("Spent: %d of %d", plan.spent, plan.total),
    }
    for _, n in ipairs(Notes(plan)) do lines[#lines + 1] = n[1] end
    local step = plan.next[1]
    if step then
        local name = (step.node and step.node.name) or T.SpellName(step.spell) or ("#" .. step.spell)
        lines[#lines + 1] = ns.F("Next point: %s", ("%s %d/%d"):format(name, step.rank, step.node and step.node.max or step.rank))
    end
    return lines
end
