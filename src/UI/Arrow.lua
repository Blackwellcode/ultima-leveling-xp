-- Navigationspfeil im Hausstil: runde Graphitscheibe mit der Pfeilspitze im Akzent, darunter die Entfernung
-- als Zahl und die Laufzeit klein. Bei Kontinentwechsel führt er zum Hafen (ns.Travel), auf der Überfahrt
-- zeigt er das Schiff. Verschiebbar mit der Maus.
local _, ns = ...
local S = ns.State
local HBD = LibStub and LibStub("HereBeDragons-2.0", true)

local arrow

local Clock, Meters = ns.Clock, ns.Meters

local function SetLabel(self, text, sub)
    self.dist:SetText(text or "")
    self.time:SetText(sub or "")
    self.pill:SetWidth(math.max(self.dist:GetStringWidth(), self.time:GetStringWidth()) + 16)
    self.pill:SetHeight((sub and sub ~= "") and 48 or 34)
    self.pill:SetShown(text ~= nil and text ~= "")
end

-- Scheibe nur zeigen, wenn sie etwas zeigt: ohne Ziel keine leere Scheibe mitten im Bild
local function SetDial(self, shown)
    if self.dialShown == shown then return end
    self.dialShown = shown
    self.dial:SetShown(shown)
    self.ring:SetShown(shown)
end

local function Update(self, elapsed)
    self.t = (self.t or 0) + elapsed
    if self.t < 0.03 then return end
    self.t = 0
    SetDial(self, true)
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
        -- schon in der Luft: das Flugziel nennen ("Flug nach Westfall"), sonst die Aufforderung
        local text
        if ns.Nav.flyTo then
            text = ns.F("Fly to %s", ns.Nav.flyTo)
        elseif icon == "fly" then
            text = ns.L["Take the flight"]
        else
            text = icon == "home" and ns.L["Use your Hearthstone"] or ns.L["Crossing"]
        end
        SetLabel(self, text)
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
        local c = floor and ns.COLORS.warn or ns.COLORS.ok
        self.check:SetVertexColor(c[1], c[2], c[3])
        self.check:Show()
        SetLabel(self, floor == "up" and ns.L["Upstairs"] or floor == "down" and ns.L["Downstairs"] or ns.L["At your destination"])
        return
    end
    self.check:Hide()
    if not target or not HBD then
        self.tex:Hide()
        SetLabel(self, nil)
        SetDial(self, false)
        return
    end
    local tx, ty, tci = S.WorldPoint(target)
    local px, py, pci = HBD:GetPlayerWorldPosition()
    local facing = GetPlayerFacing()
    if ns.IsSecret(facing) or ns.IsSecret(px) then facing, px = nil, nil end -- geschuetzt: Pfeil kurz ausblenden
    if not (tx and px and facing) or pci ~= tci then
        self.tex:Hide()
        SetLabel(self, nil)
        SetDial(self, false)
        return
    end
    local angle, dist = HBD:GetWorldVector(pci, px, py, tx, ty)
    if not angle then return end
    self.tex:Show()
    self.tex:SetRotation(angle - facing)
    local radius = target.r and target.r > 0 and target.r or 10
    local near = dist <= radius
    local c = near and ns.COLORS.ok or ns.ACCENT
    self.tex:SetVertexColor(c[1], c[2], c[3])
    SetLabel(self, Meters(dist), Clock(dist / ns.RunSpeed()))
end

local function Build()
    arrow = CreateFrame("Frame", "UltimaArrow", UIParent)
    arrow:SetSize(74, 74)
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
    -- Scheibe 74 px in der Fläche des Hauses, Rand in der Linienfarbe
    arrow.dial = ns.Round(arrow, "circle", 37, ns.COLORS.panel, "BACKGROUND")
    arrow.ring = ns.Round(arrow, "ring", 37, ns.COLORS.cardBorder, "BORDER")
    arrow.tex = arrow:CreateTexture(nil, "ARTWORK")
    arrow.tex:SetTexture(ns.TEX .. "ulx_navigation_arrow-1")
    arrow.tex:SetSize(44, 44)
    arrow.tex:SetPoint("CENTER")
    arrow.ship = arrow:CreateTexture(nil, "ARTWORK")
    arrow.ship:SetTexture(ns.TEX .. "ulx-glyph-ship")
    arrow.ship:SetSize(34, 34)
    arrow.ship:SetPoint("CENTER")
    arrow.ship:SetVertexColor(ns.COLORS.text[1], ns.COLORS.text[2], ns.COLORS.text[3])
    arrow.ship:Hide()
    arrow.check = arrow:CreateTexture(nil, "ARTWORK")
    arrow.check:SetTexture(ns.TEX .. "ulx-glyph-check")
    arrow.check:SetSize(30, 30)
    arrow.check:SetPoint("CENTER")
    arrow.check:SetVertexColor(ns.COLORS.ok[1], ns.COLORS.ok[2], ns.COLORS.ok[3])
    arrow.check:Hide()
    arrow.pill = CreateFrame("Frame", nil, arrow)
    arrow.pill:SetHeight(48)
    arrow.pill:SetPoint("TOP", arrow, "BOTTOM", 0, -6)
    ns.Round(arrow.pill, "round", ns.Theme.radius.control, ns.COLORS.panel, "BACKGROUND")
    arrow.dist = ns.Label(arrow.pill, ns.Theme.size.figure, ns.COLORS.text, "OVERLAY", "Bold")
    arrow.dist:SetPoint("TOP", 0, -4)
    arrow.dist:SetJustifyH("CENTER")
    arrow.time = ns.Label(arrow.pill, ns.Theme.size.small, ns.COLORS.text3, "OVERLAY", "Medium")
    arrow.time:SetPoint("TOP", arrow.dist, "BOTTOM", 0, -1)
    arrow.time:SetJustifyH("CENTER")
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
