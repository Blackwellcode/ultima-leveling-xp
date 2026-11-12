-- Navigation: bestimmt das aktuelle Ziel (Fähre oder Routen-Wegpunkt), sucht einen Weg über das
-- Wegnetz (ns.Paths) und führt den Pfeil von Zwischenpunkt zu Zwischenpunkt. Ziel und Zwischenpunkte
-- erscheinen als Marker auf Minimap und Weltkarte (HereBeDragons-Pins).
local _, ns = ...
local Nav = {}
ns.Nav = Nav
local R, S = ns.Runner, ns.State
local Pins = LibStub and LibStub("HereBeDragons-Pins-2.0", true)

local REACHED = 18      -- Yards: Zwischenpunkt erreicht
local OFF_PATH = 45     -- Yards: so weit neben dem Weg -> Weg ab deiner Position neu suchen
local REPLAN_MOVED = 60 -- Yards: so weit seit der letzten Suche bewegt -> neu suchen (bei weiten Zielen 15 % der Strecke)
local REPLAN_GAP = 1.5  -- Sekunden: frühestens so oft neu suchen

local goalKey, goal, points, idx = nil, nil, nil, 1
local planned = { x = 0, y = 0, t = -100, net = false } -- Stand der letzten Suche
Nav.onRide = false

local function Dist(ax, ay, bx, by) return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2) end

-------------------------------------------------------------------------------
-- Marker
-------------------------------------------------------------------------------
local pool, used = {}, 0
local function Pin(kind)
    used = used + 1
    local f = pool[used]
    if not f then
        f = CreateFrame("Frame")
        f.tex = f:CreateTexture(nil, "OVERLAY")
        f.tex:SetAllPoints()
        pool[used] = f
    end
    if kind == "target" then
        f:SetSize(22, 22)
        f.tex:SetTexture(ns.TEX .. "ulx_logo-64")
        local n = ns.Theme.color.neutral
        f.tex:SetVertexColor(n[1], n[2], n[3], 1)
    else
        f:SetSize(9, 9)
        f.tex:SetTexture(ns.TEX .. "ulx-circle")
        f.tex:SetVertexColor(ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.9)
    end
    return f
end

local function ClearPins()
    if Pins then
        Pins:RemoveAllMinimapIcons(Nav)
        Pins:RemoveAllWorldMapIcons(Nav)
    end
    used = 0
end

local function DrawPins()
    ClearPins()
    if not (Pins and points) then return end
    for i = idx, #points do
        local p = points[i]
        local final = i == #points
        -- Einstellungen pins.*: Marker auf Minimap und Weltkarte, Zahl der Wegpunkte auf der Minimap
        if ns.db.pins.minimap and (final or i < idx + ns.db.pins.dots) then
            Pins:AddMinimapIconWorld(Nav, Pin(final and "target" or "dot"), p.ci, p.x, p.y, final)
        end
        if ns.db.pins.world then
            Pins:AddWorldMapIconWorld(Nav, Pin(final and "target" or "dot"), p.ci, p.x, p.y, 3)
        end
    end
end

-------------------------------------------------------------------------------
-- Ziel und Weg
-------------------------------------------------------------------------------
-- Ziel-Punkt aus Ansicht: Fähre (Hafen), sonst nächster Routen-Wegpunkt. nil auf der Überfahrt.
-- Als Geist: zurück zur Leiche. Position über C_DeathInfo (Kartenanteile der aktuellen Karte).
local function CorpseGoal()
    if not (UnitIsGhost and UnitIsGhost("player")) then return nil end
    if not (C_DeathInfo and C_DeathInfo.GetCorpseMapPosition and C_Map and C_Map.GetBestMapForUnit) then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    local pos = map and C_DeathInfo.GetCorpseMapPosition(map)
    if not pos then return nil end
    local x, y = pos:GetXY()
    if ns.IsSecret(x) or ns.IsSecret(y) or not x then return nil end
    return { "goto", m = map, x = x * 100, y = y * 100, r = 25 }
end

local function GoalFromView(view)
    local corpse = CorpseGoal()
    if corpse then return corpse, false end
    local waypoint = view and R.Waypoint(view) or nil
    local plan = ns.Travel.Plan(waypoint)
    if plan then
        local target = ns.Travel.ArrowTarget(plan)
        -- Art der Wartephase für den Pfeil: Schiff, Flug oder Ruhestein
        Nav.rideIcon = nil
        for _, leg in ipairs(plan) do
            if leg.kind == "ride" then Nav.rideIcon = leg.icon break end
        end
        return target, target == nil
    end
    return waypoint, false
end

local function Plan(a)
    local tx, ty, tci = S.WorldPoint(a)
    if not tx then
        points = nil
        return
    end
    local px, py, pci = S.PlayerWorld()
    local path
    if px and pci == tci then path = ns.Paths.Find(tci, px, py, tx, ty) end
    points = path or { { x = tx, y = ty, ci = tci, w = true, r = a.r, final = true } }
    idx = 1
    planned.x, planned.y = px or 0, py or 0
    planned.t = GetTime and GetTime() or 0
    planned.net = ns.Paths.IsReady()
    DrawPins()
end

function Nav.Update(view)
    Nav.atGoal = view and R.AtGoal(view) or false
    local a, ride = GoalFromView(view)
    Nav.onRide = ride
    if not a then
        goalKey, goal, points = nil, nil, nil
        ClearPins()
        return
    end
    local tx, ty, tci = S.WorldPoint(a)
    local key = tx and ("%d:%.0f:%.0f"):format(tci or -1, tx, ty) or nil
    if key ~= goalKey then
        goalKey, goal = key, a
        Plan(a)
    end
end

-- Weg neu suchen? Wenn du neben dem Weg läufst, dich seit der letzten Suche ein gutes Stück bewegt hast
-- (vielleicht gibt es jetzt einen besseren Einstieg) oder das Wegnetz inzwischen fertig ist.
local function NeedsReplan(px, py)
    if not goal then return false end
    local now = GetTime and GetTime() or 0
    if now - planned.t < REPLAN_GAP then return false end
    if not planned.net and ns.Paths.IsReady() then return true end
    local final = points[#points]
    local remaining = Dist(px, py, final.x, final.y)
    if Dist(px, py, planned.x, planned.y) >= math.max(REPLAN_MOVED, remaining * 0.15) then return true end
    -- Abstand zum aktuellen Wegstück (vom vorigen Punkt bzw. Startpunkt zum aktuellen Punkt)
    local cur = points[idx]
    local prev = points[idx - 1] or { x = planned.x, y = planned.y }
    if #points > 1 and ns.Paths.SegmentDist(px, py, prev.x, prev.y, cur.x, cur.y) > OFF_PATH then return true end
    return false
end

-- Aktueller Zielpunkt für den Pfeil. Rückt weiter, wenn ein Zwischenpunkt erreicht oder überholt ist.
function Nav.Target()
    if not points then return nil end
    local px, py, pci = S.PlayerWorld()
    if not px then return points[idx] end
    if points[idx].ci == pci and NeedsReplan(px, py) then
        Plan(goal)
        if not points then return nil end
    end
    local moved = false
    while idx < #points do
        local cur, nxt = points[idx], points[idx + 1]
        if cur.ci ~= pci then break end
        if Dist(px, py, cur.x, cur.y) <= REACHED or Dist(px, py, nxt.x, nxt.y) < Dist(cur.x, cur.y, nxt.x, nxt.y) then
            idx = idx + 1
            moved = true
        else
            break
        end
    end
    if moved then DrawPins() end
    return points[idx], idx, #points
end

Nav.Redraw = DrawPins

ns.On("VIEW", function(view) Nav.Update(view) end)
ns.On("ROUTES_LOADED", function()
    ns.Paths.Build()
    goalKey = nil
end)
