-- Navigationspfeil im Keynote-Stil: runde Glasscheibe mit Verlaufsring, darin der Pfeil, darunter eine Pille
-- mit Entfernung und Laufzeit. Bei Kontinentwechsel führt er zum Hafen (ns.Travel), auf der Überfahrt
-- zeigt er das Schiff. Verschiebbar mit der Maus.
local _, ns = ...
local S = ns.State
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

local arrow

local Clock, Meters = ns.Clock, ns.Meters

local function SetLabel(self, text)
    self.dist:SetText(text or "")
    self.pill:SetWidth(self.dist:GetStringWidth() + 20)
    self.pill:SetShown(text ~= nil and text ~= "")
end

local function Update(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.03 then return end
    self.t = 0
    -- Ziel kommt aus der Navigation: Zwischenpunkte des Wegnetzes, Hafen oder Routen-Wegpunkt
    local target = ns.Nav.Target()
    if ns.Nav.onRide then
        self.tex:Hide()
        self.check:Hide()
        local icon = ns.Nav.rideIcon
        local glyph = (icon == "fly" or icon == "home") and icon or "ship"
        if self.rideGlyph ~= glyph then
            self.rideGlyph = glyph
            self.ship:SetTexture(ns.TEX .. "ulx-glyph-" .. glyph)
        end
        self.ship:Show()
        SetLabel(self, icon == "fly" and ns.L["Take the flight"] or icon == "home" and ns.L["Use your Hearthstone"] or ns.L["Crossing"])
        return
    end
    self.ship:Hide()
    if not target and ns.view and ns.Nav.atGoal then
        -- Alle Wegpunkte erreicht, jetzt die Handlungen vor Ort (Quest abgeben, annehmen, ...)
        self.tex:Hide()
        -- Ziel über oder unter dir: Doppelpfeil nach oben oder unten statt Häkchen, mit Ansage
        local view = ns.view
        local step = view.catchup and view.catchup.route.s[view.catchup.si] or view.route.s[view.main]
        local floor = step and step.fl
        local glyph = floor and "xp" or "check"
        if self.goalGlyph ~= glyph then
            self.goalGlyph = glyph
            self.check:SetTexture(ns.TEX .. "ulx-glyph-" .. glyph)
        end
        self.check:SetRotation(floor == "down" and math.pi or 0)
        if floor then self.check:SetVertexColor(1, 0.82, 0.2) else self.check:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3]) end
        self.check:Show()
        SetLabel(self, floor == "up" and ns.L["Upstairs"] or floor == "down" and ns.L["Downstairs"] or ns.L["At your destination"])
        return
    end
    self.check:Hide()
    if not target or not HBD then
        self.tex:Hide()
        SetLabel(self, nil)
        return
    end
    local tx, ty, tci = S.WorldPoint(target)
    local px, py, pci = HBD:GetPlayerWorldPosition()
    local facing = GetPlayerFacing()
    if ns.IsSecret(facing) or ns.IsSecret(px) then facing, px = nil, nil end -- geschuetzt: Pfeil kurz ausblenden
    if not (tx and px and facing) or pci ~= tci then
        self.tex:Hide()
        SetLabel(self, nil)
        return
    end
    local angle, dist = HBD:GetWorldVector(pci, px, py, tx, ty)
    if not angle then return end
    self.tex:Show()
    self.tex:SetRotation(angle - facing)
    local radius = target.r and target.r > 0 and target.r or 10
    local near = dist <= radius
    if near then self.tex:SetVertexColor(0.45, 1, 0.6) else self.tex:SetVertexColor(1, 1, 1) end
    SetLabel(self, ("%s  ·  %s"):format(Meters(dist), Clock(dist / ns.RunSpeed())))
end

local function Build()
    arrow = CreateFrame("Frame", "UltimaArrow", UIParent)
    arrow:SetSize(76, 76)
    local p = ns.db.arrow.point
    if p then arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else arrow:SetPoint("TOP", UIParent, "TOP", 0, -140) end
    arrow:SetMovable(true)
    arrow:EnableMouse(true)
    arrow:RegisterForDrag("LeftButton")
    arrow:SetClampedToScreen(true)
    arrow:SetScript("OnDragStart", arrow.StartMoving)
    arrow:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        ns.db.arrow.point = { point, relPoint, x, y }
    end)
    local disc = arrow:CreateTexture(nil, "BACKGROUND")
    disc:SetTexture(ns.TEX .. "ulx-disc")
    disc:SetAllPoints()
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetTexture(ns.TEX .. "ulx_navigation_arrow-1")
    arrow.tex:SetSize(44, 44)
    arrow.tex:SetPoint("CENTER")
    arrow.ship = arrow:CreateTexture(nil, "ARTWORK")
    arrow.ship:SetTexture(ns.TEX .. "ulx-glyph-ship")
    arrow.ship:SetSize(34, 34)
    arrow.ship:SetPoint("CENTER")
    arrow.ship:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])
    arrow.ship:Hide()
    arrow.check = arrow:CreateTexture(nil, "ARTWORK")
    arrow.check:SetTexture(ns.TEX .. "ulx-glyph-check")
    arrow.check:SetSize(30, 30)
    arrow.check:SetPoint("CENTER")
    arrow.check:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3])
    arrow.check:Hide()
    arrow.pill = CreateFrame("Frame", nil, arrow)
    arrow.pill:SetHeight(22)
    arrow.pill:SetPoint("TOP", arrow, "BOTTOM", 0, -6)
    ns.Round(arrow.pill, "circle", 11, { 0.055, 0.059, 0.071, 0.88 }, "BACKGROUND")
    arrow.dist = ns.Label(arrow.pill, 13, ns.COLORS.text, "OVERLAY", "Medium")
    arrow.dist:SetPoint("CENTER", 0, 0)
    arrow.dist:SetJustifyH("CENTER")
    arrow:SetScript("OnUpdate", function(self, elapsed) ns.Guard("Arrow", Update, self, elapsed) end)
    arrow:SetShown(ns.db.arrow.shown)
end

ns.On("READY", Build)

-- Größe (eigene Stufe mal automatischer Maßstab), Sichtbarkeit und bei Bedarf die Ausgangslage
function ns.ApplyArrow(resetPosition)
    if not arrow then return end
    local db = ns.db
    arrow:SetScale(db.arrow.scale * (db.window.autoScale and db.window.scale or 1))
    arrow:SetShown(db.arrow.shown)
    if resetPosition then
        arrow:ClearAllPoints()
        arrow:SetPoint("TOP", UIParent, "TOP", 0, -140)
    end
end

function ns.ToggleArrow()
    ns.db.arrow.shown = not ns.db.arrow.shown
    ns.ApplyArrow()
end
