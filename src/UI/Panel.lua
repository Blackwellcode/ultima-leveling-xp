-- Panel im Hausstil Blackwellcode ("Rail", Theme.lua): Graphit, Haarlinien statt Karten, ein Glutakzent für "jetzt".
--   Schiene   22-px-Spalte links: ein Strich je Routenschritt, die Glutmarke steht auf dem aktuellen
--   Kopf      Routenname in Anzeigegröße, Schritt, rechts das Level als Zahl
--   XP        4-px-Balken, darunter Anteil und Rest
--   Status    vier Spalten (Boni): Bezeichnung klein, Wert als Wort; geschützte Knöpfe
--   Reise     Etappen bei Kontinentwechsel
--   Jetzt     der Schrittsatz groß, weitere Handlungen als Zeilen mit Verb-Spalte
--   Danach    Vorschau
local _, ns = ...
local R, P, T, S = ns.Runner, ns.Progress, ns.Text, ns.State
local C, A1 = ns.COLORS, ns.ACCENT
local TH = ns.Theme
local SZ = TH.size

local WIDTH = 384
local RAIL = 22                      -- Schienen-Spalte
local LEFT, RIGHT = RAIL + 14, 16    -- Innenabstand nach der Schiene und rechts
local CW = WIDTH - LEFT - RIGHT      -- Inhaltsbreite
local LEVEL_W = 70                   -- rechter Kopfblock: "Stufe 16"
local HEAD_W = CW - LEVEL_W
local VERB_W = 82                    -- Verb-Spalte der Zeilen: Symbol, dann das Verb
local STEP_ICON = 20                 -- Symbol vor dem Schrittsatz
local FIG_W = 64                     -- rechte Zahlen-Spalte (Entfernung, Zeit)
local FIXED_H = 160 -- feste Höhe des Fensters (Kopf bis Statusleiste); die sichtbare Hülle wächst getrennt
local MAX_ROWS = 8
-- Werkzeugleiste: Schale unten, Kacheln in Gruppen (Hausstil 1.2.0)
local TRAY_H, TRAY_INSET, TRAY_PAD = 42, 6, 6
local BUTTON, BUTTON_GAP, GROUP_GAP = 30, 4, 12
local MAX_TICKS = 160

local panel, picker
local rows, legs, rules, ticks = {}, {}, {}, {}
local lastMain
local xpShown, routeShown = 0, 0

-- Farbe aus einem Token: Texte über SetTextColor, Texturen über SetVertexColor
local function Paint(region, c, a)
    if region.SetTextColor then
        region:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
    else
        region:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    end
end

-- Haarlinie: eine Textur ohne Einrasten ins Pixelraster, damit 1 px bei jeder Skalierung 1 px bleibt
local function Hairline(parent, layer)
    local t = parent:CreateTexture(nil, layer or "BORDER")
    t:SetTexture(ns.WHITE)
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    Paint(t, C.cardBorder)
    return t
end

local function Label(parent, size, color, weight)
    return ns.Label(parent, size, color, "OVERLAY", weight)
end

-------------------------------------------------------------------------------
-- Glyphen für Zeilen ohne Verb (Ziele wie "Murlocs getötet 3/8"), einfarbig gedämpft
-------------------------------------------------------------------------------
local GLYPH = {
    accept = "accept", turnin = "turnin", abandon = "kill", complete = "kill", mob = "kill", unitscan = "kill",
    collect = "collect", vendor = "collect", target = "talk", ["goto"] = "goto", zone = "ship", subzone = "goto",
    fly = "fly", fp = "fly", hs = "home", home = "home", train = "train", trainer = "train", xp = "xp",
    use = "use", equip = "use", boat = "ship", zeppelin = "ship", tram = "ship",
}

-- Verb und Objekt aus dem übersetzten Text trennen: "Annehmen: X" -> "Annehmen", "X".
-- Gilt für Vorlagen mit dem Verb vorn ("Go to %s") und hinten (koreanisch "%s 수락").
local VERB_KEYS = { "Accept: %s", "Turn in: %s", "Collect: %s", "Train: %s", "Abandon: %s", "Use: %s",
    "Enemies: %s", "Talk to: %s", "Get the flight path: %s", "Go to %s", "Fly to %s", "Travel to %s" }
local function Trim(s)
    s = s:gsub("^%s+", ""):gsub("[%s:：]+$", "")
    return s
end
local function SplitVerb(text)
    if not text then return nil, text end
    for _, key in ipairs(VERB_KEYS) do
        local prefix, suffix = ns.L[key]:match("^(.-)%%s(.*)$")
        if prefix and prefix ~= "" and text:sub(1, #prefix) == prefix then
            return Trim(prefix), text:sub(#prefix + 1)
        elseif prefix == "" and suffix and suffix ~= "" and #text > #suffix and text:sub(-#suffix) == suffix then
            return Trim(suffix), text:sub(1, #text - #suffix)
        end
    end
    return nil, text
end

local Clock, Meters = ns.Clock, ns.Meters

local function Speed() return ns.RunSpeed() end -- im Kampf geschuetzt, siehe Kit

-- Farbcodes aus den Tokens: Ziel (Person, Ort) im Akzent, Gegner in "bad", Stockwerk in "warn"
local HEX_ACCENT, HEX_BAD, HEX_WARN, HEX_MUTED = ns.Hex(A1), ns.Hex(C.bad), ns.Hex(C.warn), ns.Hex(C.text3)
local function Colored(hex, text) return "|cff" .. hex .. text .. "|r" end

-- Weich gleitender Wert (für Balken und die Glutmarke)
local function Approach(current, target, dt)
    local k = math.min(1, dt * 10)
    return current + (target - current) * k
end

-------------------------------------------------------------------------------
-- Schiene: ein Strich je Schritt (bei langen Routen je Block), erledigte gedämpft hell, die Glutmarke
-- auf dem aktuellen Schritt. Über die Höhe der Hülle verteilt.
-------------------------------------------------------------------------------
local RAIL_TOP, RAIL_BOTTOM = 14, 14

local function MarkY(fraction)
    local h = (panel.bodyH or FIXED_H) - RAIL_TOP - RAIL_BOTTOM
    return -RAIL_TOP - fraction * h
end

local function RenderRail(total, at)
    local body = panel.body
    local h = (panel.bodyH or FIXED_H) - RAIL_TOP - RAIL_BOTTOM
    local count = 0
    local block = 1
    if total and total > 1 then
        block = math.max(1, math.ceil(total / MAX_TICKS), math.ceil(total / math.max(2, math.floor(h / 2))))
        count = math.ceil(total / block)
    end
    for i = 1, count do
        local t = ticks[i]
        if not t then
            t = Hairline(body, "BORDER")
            t:SetSize(7, 1)
            ticks[i] = t
        end
        local first = (i - 1) * block + 1
        local y = count > 1 and (-RAIL_TOP - (i - 1) / (count - 1) * h) or -RAIL_TOP
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", body, "TOPLEFT", 8, y)
        Paint(t, (at and first < at) and C.text3 or C.cardBorder)
        t:Show()
    end
    for i = count + 1, #ticks do ticks[i]:Hide() end
    panel.mark:SetShown(count > 0)
end

local function PlaceMark()
    panel.mark:ClearAllPoints()
    panel.mark:SetPoint("LEFT", panel.body, "TOPLEFT", 4, MarkY(routeShown))
end

-- Balken und Glutmarke gleiten weich zum Ziel. Sind beide angekommen, hängt sich der Handler ab;
-- RenderHeader hängt ihn bei jedem neuen Ziel wieder an (sonst liefe er jedes Bild weiter).
local SETTLED = 0.001
local function Slide(_, dt)
    local w = panel.xp:GetWidth()
    if not (w and w > 0 and panel.xpTarget) then return end
    local xpTarget, routeTarget = panel.xpTarget, panel.routeTarget or 0
    xpShown = Approach(xpShown, xpTarget, dt)
    routeShown = Approach(routeShown, routeTarget, dt)
    local settled = math.abs(xpTarget - xpShown) < SETTLED and math.abs(routeTarget - routeShown) < SETTLED
    if settled then xpShown, routeShown = xpTarget, routeTarget end
    panel.xpFill:SetWidth(math.max(1, w * xpShown))
    panel.rest:SetWidth(math.max(1, w * (panel.restTarget or 0)))
    panel.rest:SetShown((panel.restTarget or 0) > xpTarget + 0.005)
    PlaceMark()
    if settled then
        panel:SetScript("OnUpdate", nil)
        panel.sliding = false
    end
end

local function StartSlide()
    if panel and not panel.sliding then
        panel.sliding = true
        panel:SetScript("OnUpdate", Slide)
    end
end

-- Haarlinien zwischen den Abschnitten, aus einem Vorrat
local ruleCount = 0
local function Rule(y)
    ruleCount = ruleCount + 1
    local r = rules[ruleCount]
    if not r then
        r = Hairline(panel, "BORDER")
        r:SetHeight(1)
        rules[ruleCount] = r
    end
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT, y)
    r:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -RIGHT, y)
    r:Show()
end

-- Die Knöpfe der Werkzeugleiste, in dieser Reihenfolge und Gruppe. Eine Liste für Panel und
-- Willkommensfenster (dort mit Symbol, Name und Zweck erklärt): key, Gruppe, Glyphe, Name, Zweck.
ns.PANEL_BUTTONS = {
    { key = "back", group = "step", glyph = "left", name = "One step back", desc = "Go back to the previous step." },
    { key = "skip", group = "step", glyph = "right", name = "Skip step", desc = "Mark the current step as done and move on." },
    { key = "route", group = "route", glyph = "list", name = "Choose route", desc = "Pick another route, or let Ultima choose one for your level." },
    { key = "dungeon", group = "route", glyph = "dungeon", name = "Prepare a dungeon", desc = "Collect every quest for one dungeon, then back to your route." },
    { key = "arrow", group = "tools", glyph = "compass", name = "Arrow on or off", desc = "Show or hide the navigation arrow." },
    { key = "options", group = "tools", glyph = "settings", name = "Options", desc = "All settings, sorted by topic." },
    { key = "help", group = "tools", glyph = "help", name = "Help", desc = "Opens the welcome guide with all buttons again." },
    { key = "fold", group = "view", glyph = "minus", name = "Expand or collapse steps", desc = "Show only the header, or all steps." },
}

-------------------------------------------------------------------------------
-- Zeilen: der Schrittsatz (erste offene Handlung) groß; weitere Handlungen als Verb-Spalte plus Objekt
-------------------------------------------------------------------------------
local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, panel.hero)
    row:RegisterForClicks("RightButtonUp")
    row.hl = row:CreateTexture(nil, "BACKGROUND")
    row.hl:SetTexture(ns.WHITE)
    row.hl:SetPoint("TOPLEFT", -6, 4)
    row.hl:SetPoint("BOTTOMRIGHT", 6, -4)
    Paint(row.hl, C.card)
    row.hl:Hide()
    row.sep = Hairline(row, "BORDER")
    row.sep:SetHeight(1)
    row.sep:SetPoint("BOTTOMLEFT", row, "TOPLEFT", 0, 4)
    row.sep:SetPoint("BOTTOMRIGHT", row, "TOPRIGHT", 0, 4)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(14, 14)
    row.icon:SetPoint("TOPLEFT", 0, -1)
    row.verb = Label(row, SZ.small, C.text3, "Medium")
    row.verb:SetPoint("TOPLEFT", 18, -2)
    row.text = Label(row, SZ.body, C.text, "Medium")
    row.text:SetWordWrap(true)
    row.dist = Label(row, SZ.display, C.text, "Bold")
    row.dist:SetJustifyH("RIGHT")
    row.dist:SetPoint("TOPRIGHT", 0, 0)
    row.time = Label(row, SZ.small, C.text3, "Medium")
    row.time:SetJustifyH("RIGHT")
    row.time:SetPoint("TOPRIGHT", row.dist, "BOTTOMRIGHT", 0, -2)
    row.track = Hairline(row, "BORDER")
    row.track:SetHeight(4)
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetTexture(ns.WHITE)
    row.fill:SetHeight(4)
    row.fill:SetPoint("TOPLEFT", row.track, "TOPLEFT")
    Paint(row.fill, C.text)
    row.count = Label(row, SZ.small, C.text3, "Bold")
    row.hint = Label(row, SZ.small, C.text2, "Medium")
    row.hint:SetWordWrap(true)
    row:SetScript("OnClick", function(self)
        if self.si then R.Skip(self.si) ns.RequestUpdate() end
    end)
    row:SetScript("OnEnter", function(self)
        self.hl:Show()
        if not self.full then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.full, 1, 1, 1, 1, true)
        GameTooltip:AddLine(ns.L["Right-click: skip step"], C.text3[1], C.text3[2], C.text3[3])
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function(self)
        self.hl:Hide()
        GameTooltip_Hide()
    end)
    rows[i] = row
    return row
end

local function FillRow(row, index, ref, entry, y, waypoint, width)
    local a, si = entry.a, ref.si
    local text, have, need, hint = T.Action(a)
    if entry.text then text = entry.text end
    -- "Accept X" unter "Annehmen: X" wiederholt nur den Titel: weglassen
    if a[1] == "accept" or a[1] == "turnin" then hint = nil end
    local done
    if a[1] == "goto" then
        done = P.Done(a)
    else
        done = P.BLOCKING[a[1]] and P.Done(a, { routeId = ref.route.id, si = si, ai = entry.i })
    end
    if ref.kind == "catchup" and P.BLOCKING[a[1]] then
        hint = ns.F("Catch up from %s", ref.route.n or "") .. (hint and (". " .. hint) or "")
    elseif ref.kind == "open" and P.BLOCKING[a[1]] then
        hint = ns.L["Postponed, ready to turn in"] .. (hint and (". " .. hint) or "")
    end
    -- Überspringen per Klick nur für Schritte der aktiven Route
    row.si = ref.route == (ns.view and ns.view.route) and si or nil
    row.full = text
    row.sep:SetShown(index > 1)

    -- Entfernung und Laufzeit rechts als Zahlen, nur für den Wegpunkt, zu dem der Pfeil führt
    local figure = false
    row.dist:Hide()
    row.time:Hide()
    row.waypoint = nil
    if waypoint == a and not done then
        local d = S.Distance(a)
        if d then
            row.dist:SetText(Meters(d))
            row.time:SetText(Clock(d / Speed()))
            row.dist:Show()
            row.time:Show()
            row.waypoint = true
            figure = true
        end
    end
    local textRight = figure and FIG_W or 0

    -- Der Schrittsatz: groß in der Anzeigeschrift, ohne Verb-Spalte. Erledigtes tritt zurück.
    local step = entry.first and not done
    local x
    -- Symbol der Handlung (Annehmen, Abgeben, Töten, Sammeln, Reisen ...) vor jeder Zeile
    row.icon:SetTexture(ns.TEX .. "ulx-glyph-" .. (GLYPH[a[1]] or "goto"))
    row.icon:ClearAllPoints()
    if step then
        row.verb:Hide()
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("TOPLEFT", 0, -3)
        Paint(row.icon, C.text)
        row.icon:Show()
        x = STEP_ICON + 4
        if row.styleKey ~= "step" then
            row.styleKey = "step"
            row.text:SetFont(ns.FontPath("Bold"), SZ.display, "")
            row.text.baseSize = SZ.display
        end
        row.text:SetText(text or "")
    else
        if row.styleKey ~= "row" then
            row.styleKey = "row"
            row.text:SetFont(ns.FontPath("Medium"), SZ.body, "")
            row.text.baseSize = SZ.body
        end
        local verb, object = SplitVerb(text)
        x = VERB_W
        row.icon:SetSize(12, 12)
        row.icon:SetPoint("TOPLEFT", 0, -3)
        Paint(row.icon, done and C.text3 or C.text2)
        row.icon:Show()
        if verb then
            row.verb:SetText(verb)
            ns.Fit(row.verb, VERB_W - 24, 9)
            row.verb:Show()
            row.text:SetText(object or "")
        else
            row.verb:Hide()
            row.text:SetText(text or "")
        end
    end
    local textW = width - x - textRight
    row.text:ClearAllPoints()
    row.text:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
    row.text:SetWidth(textW)
    Paint(row.text, done and C.text3 or C.text)
    local below = -(row.text:GetStringHeight() + 6)

    -- Zielbalken: 4 px Spur in der Linienfarbe, Füllung hell, Zähler als Zahl rechts
    if need and need > 0 and not done then
        local trackW = textW - 40
        row.track:ClearAllPoints()
        row.track:SetPoint("TOPLEFT", row.text, "TOPLEFT", 0, below - 2)
        row.track:SetWidth(trackW)
        row.fill:SetWidth(math.max(1, trackW * math.min(1, (have or 0) / need)))
        row.count:ClearAllPoints()
        row.count:SetPoint("LEFT", row.track, "RIGHT", 8, 0)
        row.count:SetText(("%d/%d"):format(have or 0, need))
        row.track:Show()
        row.fill:Show()
        row.count:Show()
        below = below - 14
    else
        row.track:Hide()
        row.fill:Hide()
        row.count:Hide()
    end

    local always = ref.kind == "catchup" or ref.kind == "open"
    if hint and (ns.db.hints or always) and not done then
        row.hint:ClearAllPoints()
        row.hint:SetPoint("TOPLEFT", row.text, "TOPLEFT", 0, below)
        row.hint:SetWidth(textW)
        row.hint:SetText(hint)
        row.hint:Show()
        below = below - row.hint:GetStringHeight() - 4
    else
        row.hint:Hide()
    end

    local height = math.max(figure and 40 or 16, -below)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.hero, "TOPLEFT", 0, y)
    row:SetSize(width, height)
    row:Show()
    return height
end

-------------------------------------------------------------------------------
-- Reise: Etappen mit Marken (erledigt grün, aktuell hell, später gedämpft) an einer Haarlinie
-------------------------------------------------------------------------------
local function GetLeg(i)
    if legs[i] then return legs[i] end
    local leg = CreateFrame("Frame", nil, panel.travel)
    leg:SetHeight(28)
    leg.mark = leg:CreateTexture(nil, "ARTWORK")
    leg.mark:SetTexture(ns.TEX .. "ulx-glyph-goto")
    leg.mark:SetSize(12, 12)
    leg.mark:SetPoint("TOPLEFT", 0, -2)
    leg.line = Hairline(leg, "BORDER")
    leg.line:SetWidth(1)
    leg.line:SetPoint("TOP", leg.mark, "BOTTOM", 0, -3)
    leg.line:SetPoint("BOTTOM", leg, "BOTTOM", 0, -6)
    leg.text = Label(leg, SZ.body, C.text, "Medium")
    leg.text:SetPoint("TOPLEFT", leg, "TOPLEFT", 18, 0)
    leg.sub = Label(leg, SZ.small, C.text2, "Medium")
    leg.sub:SetPoint("TOPLEFT", leg.text, "BOTTOMLEFT", 0, -2)
    legs[i] = leg
    return leg
end

local function RenderTravel(plan, y, width)
    if not plan then
        panel.travel:Hide()
        return y
    end
    Rule(y)
    y = y - 10
    panel.travel:ClearAllPoints()
    panel.travel:SetPoint("TOPLEFT", LEFT, y)
    panel.travel:SetWidth(width)
    panel.travelLabel:ClearAllPoints()
    panel.travelLabel:SetPoint("TOPLEFT", 0, 0)
    local inner = -20
    local current = true
    for i, leg in ipairs(plan) do
        local row = GetLeg(i)
        local legGlyph = leg.done and "check" or (leg.kind == "ride" and (leg.icon == "fly" and "fly" or leg.icon == "home" and "home" or "ship")) or "goto"
        row.mark:SetTexture(ns.TEX .. "ulx-glyph-" .. legGlyph)
        Paint(row.mark, leg.done and C.ok or (current and C.text or C.text3))
        row.text:SetText(leg.text)
        ns.Fit(row.text, width - 18, 10)
        Paint(row.text, leg.done and C.text3 or C.text)
        local sub = leg.sub
        if leg.kind == "goto" and not leg.done and leg.point then
            local d = S.Distance(leg.point)
            if d then sub = (sub and (sub .. ", ") or "") .. Meters(d) .. ", " .. Clock(d / Speed()) end
        end
        row.sub:SetText(sub or "")
        ns.Fit(row.sub, width - 18, 9)
        row.line:SetShown(i < #plan)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.travel, "TOPLEFT", 0, inner)
        row:SetWidth(width)
        row:Show()
        inner = inner - ((sub and sub ~= "") and 38 or 26)
        if not leg.done then current = false end
    end
    for i = #plan + 1, #legs do legs[i]:Hide() end
    panel.travel:SetHeight(-inner)
    panel.travel:Show()
    return y - (-inner) - 6
end

-------------------------------------------------------------------------------
-- Statusleiste: vier feste Spalten unter der XP-Leiste. Sie sind geschuetzte Knoepfe
-- (SecureActionButton), damit ein Klick Essen essen, den Schlafsack auslegen oder ein Lagerfeuer
-- aufstellen darf. Position und Attribute aendern sich nie im Kampf.
-------------------------------------------------------------------------------
local TILE_Y, TILE_H, TILE_GAP = -108, 44, 8
local tiles = {}

local function StartSleepingBag()
    local id = ns.SLEEPING_BAG_ROUTE[UnitFactionGroup("player")]
    if not (id and R.Get(id)) then
        print(ns.WARN .. ns.L["Sleeping bag route not found for this faction."])
        return
    end
    -- Neu einsteigen: alter Zeiger weg, der Questlog bestimmt den Schritt (sonst sofort "fertig")
    R.StartBonus(id)
    print(ns.PREFIX .. ns.L["Sleeping bag quest chain started. Your route continues afterwards."])
    ns.RequestUpdate()
end

local function BuildTiles()
    local width = (CW - 3 * TILE_GAP) / 4
    for i = 1, 4 do
        local t = CreateFrame("Button", "UltimaBonusTile" .. i, panel, "SecureActionButtonTemplate")
        t:SetSize(width, TILE_H)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT + (i - 1) * (width + TILE_GAP), TILE_Y)
        t:RegisterForClicks("AnyUp", "AnyDown")
        t.bg = ns.Round(t, "round", TH.radius.control, C.card, "BACKGROUND")
        t.bg:SetShown(false)
        t.title = Label(t, SZ.small, C.text3, "Medium")
        t.title:SetPoint("TOPLEFT", 0, -4)
        t.status = Label(t, SZ.heading, C.text, "Bold")
        t.icon = ns.Icon(t, 16)
        t.icon:SetPoint("TOPLEFT", t.title, "BOTTOMLEFT", 0, -4)
        t.status:SetPoint("LEFT", t.icon, "RIGHT", 5, 0)
        t.innerW = width - 4
        t.valueW = width - 4 - 21
        -- Der Knopf meldet Drücken und Loslassen; gestartet wird nur beim Loslassen (sonst doppelt)
        t:SetScript("PostClick", function(self, _, down)
            if self.routeAction and not down then StartSleepingBag() end
        end)
        t:SetScript("OnEnter", function(self)
            self.bg:SetShown(true)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tipText or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.bg:SetShown(false)
            GameTooltip_Hide()
        end)
        tiles[i] = t
    end
end

-- Deckkraft des Fensters: Einstellung, im Kampf der Kampf-Wert (SetAlpha ist auch im Kampf erlaubt)
function ns.ApplyPanelAlpha()
    if not panel then return end
    local w = ns.db.window
    panel:SetAlpha(panel.inCombat and math.min(w.alpha, w.combatAlpha) or w.alpha)
end

-- Nur Inhalte aendern; Attribute nur ausserhalb des Kampfes.
local function RenderTiles()
    local list, alerts = ns.Bonus.Tiles()
    local combat = InCombatLockdown()
    -- Spalten ein- oder ausblenden (Einstellung tiles.shown); geschützte Knöpfe nur außerhalb des Kampfes
    if not combat then
        for _, t in ipairs(tiles) do
            if t:IsShown() ~= ns.db.tiles.shown then t:SetShown(ns.db.tiles.shown) end
        end
    end
    local titles, statuses = {}, {}
    for i, data in ipairs(list) do
        local t = tiles[i]
        local idle = data.state == "off" and not data.action
        t.title:SetText(data.title)
        ns.Fit(t.title, t.innerW, 9)
        local action = data.action
        -- Ein Wert, der Handeln verlangt, steht im Akzent und ist ein Wort ("Jetzt essen"), nie ein Punkt
        if action then
            t.status:SetText(data.actionText or data.status)
            Paint(t.status, A1)
        else
            t.status:SetText(data.status)
            if idle then Paint(t.status, C.text3)
            elseif data.state == "ok" then Paint(t.status, C.text)
            else Paint(t.status, ns.Bonus.COLORS[data.state] or C.text) end
        end
        ns.Fit(t.status, t.valueW, 9)
        -- Symbol des Bonus (Spiel-Icon); ohne Wirkung gedämpft
        t.icon:SetTexture(data.icon)
        t.icon:SetDesaturated(idle and true or false)
        t.icon:SetAlpha(idle and 0.5 or 1)
        t.tipText = data.tip
        titles[#titles + 1], statuses[#statuses + 1] = t.title, t.status
        t.routeAction = action and action.type == "route" or nil
        if not combat then
            local item = action and action.type == "item" and ("item:" .. action.item) or nil
            if t:GetAttribute("item") ~= item then
                t:SetAttribute("type", item and "item" or nil)
                t:SetAttribute("item", item)
            end
        end
    end
    -- alle vier Spalten in derselben Schriftgröße (die kleinste nötige), sonst wirkt die Reihe unruhig
    ns.FitSame(titles)
    ns.FitSame(statuses)
    return alerts
end

-------------------------------------------------------------------------------
-- Inhalt
-------------------------------------------------------------------------------
local function NextMain(view, player)
    if not view.main then return nil end
    for si = view.main + 1, math.min(#view.route.s, view.main + 40) do
        local s = view.route.s[si]
        if P.Applies(s, player) then
            for _, e in ipairs(P.Actions(s, player)) do
                if P.BLOCKING[e.a[1]] then return si end
            end
        end
    end
end

local function RenderHeader(view)
    local route = view.route
    panel.title:SetText(route and R.DisplayName(route) or ns.L["No route"])
    ns.Fit(panel.title, HEAD_W, 15)
    local level = S.Level()
    panel.levelText:SetText(tostring(level))
    if route then
        local total = #route.s
        local at = view.main or total
        local sub = route.k == "dungeonquests" and ns.F("Dungeon quests, step %d of %d", at, total)
            or ns.F("Step %d of %d", at, total)
        local parked = (view.waiting or 0) + #(view.open or {})
        if parked > 0 then sub = sub .. ", " .. ns.F("%d postponed", parked) end
        panel.sub:SetText(sub)
        ns.Fit(panel.sub, HEAD_W, 9)
        panel.routeTarget = total > 1 and (at - 1) / (total - 1) or 0
        panel.railTotal, panel.railAt = total, at
    else
        panel.sub:SetText(ns.L["Route button: picks one for your level"])
        ns.Fit(panel.sub, HEAD_W, 9)
        panel.routeTarget = 0
        panel.railTotal, panel.railAt = nil, nil
    end
    local xp, max = S.XP()
    local rested = GetXPExhaustion() or 0
    if max > 0 then
        panel.xpTarget = xp / max
        panel.restTarget = math.min(xp + rested, max) / max
        local missing = max - xp
        panel.xpLeft:SetText(ns.F("%d %%, %s XP to go", math.floor(xp / max * 100),
            BreakUpLargeNumbers and BreakUpLargeNumbers(missing) or tostring(missing)))
        panel.xpRight:SetText(rested > 0 and ns.F("Rested %d %%", math.floor(rested / max * 100 + 0.5)) or "")
    else
        panel.xpTarget, panel.restTarget = 1, 1
        panel.xpLeft:SetText(ns.L["Max level"])
        panel.xpRight:SetText("")
    end
    StartSlide()
    -- Eine Zeile, zwei Texte: rechts "Erholt" höchstens die halbe Breite, links der Rest mit 10 px Abstand
    ns.Fit(panel.xpRight, CW / 2, 9) -- rechtsbündig, Anker rechts: die Feldbreite stört nicht
    local rightW = (panel.xpRight:GetText() or "") ~= "" and math.min(CW / 2, ns.TextWidth(panel.xpRight)) + 10 or 0
    ns.Fit(panel.xpLeft, CW - rightW, 9)
end

local function Render(view)
    if not panel then return end
    view = view or ns.view or {}
    ruleCount = 0
    RenderHeader(view)
    local route = view.route
    local width = CW
    local alerts = RenderTiles()
    local y = ns.db.tiles.shown and (TILE_Y - TILE_H - 8) or (TILE_Y + 2)
    -- Warnungen (Gruppe, Dungeon) als Zeile unter der Statusleiste; "alles in Ordnung" braucht keine Zeile
    local warn = {}
    for _, a in ipairs(alerts) do if a.state ~= "ok" then warn[#warn + 1] = a end end
    alerts = warn
    if #alerts > 0 then
        local parts = {}
        for _, a in ipairs(alerts) do
            parts[#parts + 1] = Colored(ns.Hex(ns.Bonus.COLORS[a.state] or C.text2), a.text)
        end
        panel.alert:ClearAllPoints()
        panel.alert:SetPoint("TOPLEFT", LEFT, y)
        panel.alert:SetText(table.concat(parts, "    "))
        ns.Fit(panel.alert, CW, 9)
        panel.alert:Show()
        y = y - 20
    else
        panel.alert:Hide()
    end
    local collapsed = ns.db.window.collapsed
    local count = 0
    panel.hero:Hide()
    panel.nextLabel:Hide()
    panel.nextText:Hide()
    panel.tip:Hide()

    if route and not collapsed then
        local player = S.Player()
        local waypoint = R.Waypoint(view)
        local plan = ns.Travel.Plan(waypoint)
        panel.travelPlan = plan
        y = RenderTravel(plan, y, width)

        -- Jetzt: Schrittsatz und Handlungen
        Rule(y)
        y = y - 10
        panel.heroLabel:ClearAllPoints()
        panel.heroLabel:SetPoint("TOPLEFT", 0, 0)
        local inner = -22
        local firstOpen = false
        for _, ref in ipairs(R.Shown(view)) do
            -- Wegpunkt und Ansprechpartner gehören zusammen: "Gehe zu <NPC>" statt "Gehe zu <Zone>" plus
            -- einer eigenen Zeile "Ansprechen". Das spart eine Zeile und sagt, wen du suchst.
            local actions = P.Actions(ref.route.s[ref.si], player)
            local npc, hasGoto
            -- kein NPC: anklickbares Objekt aus den Hinweisen ("{pick:Beached Sea Turtle}") als Ziel nennen
            local object
            for _, h in ipairs(ref.route.s[ref.si].h or {}) do
                object = object or h:match("{pick:(.-)}")
            end
            -- Ein Schritt, eine Wegzeile: Rundgänge haben mehrere Wegpunkte, gezeigt wird nur der aktuelle
            -- (der, zu dem der Pfeil führt), sonst der erste offene. Ebenso eine Gegner-Zeile für alle Namen.
            local shownGoto, firstMob
            local mobs = {}
            for _, entry in ipairs(actions) do
                local a = entry.a
                if a[1] == "target" and a.names and not npc then npc = a.names[1] end
                if a[1] == "goto" then
                    hasGoto = true
                    if a == waypoint then
                        shownGoto = entry
                    elseif not shownGoto and not P.Done(a) then
                        shownGoto = entry
                    end
                end
                if (a[1] == "mob" or a[1] == "unitscan") and a.names then
                    firstMob = firstMob or entry
                    for _, n in ipairs(a.names) do mobs[#mobs + 1] = ns.NPC(n) end
                end
            end
            if hasGoto and not shownGoto then
                for _, entry in ipairs(actions) do if entry.a[1] == "goto" then shownGoto = entry end end
            end
            if firstMob and #mobs > 1 then
                firstMob.text = ns.F("Enemies: %s", Colored(HEX_BAD, table.concat(mobs, ", ")))
            end
            for _, entry in ipairs(actions) do
                local text = T.Action(entry.a)
                if entry.a[1] == "goto" and entry ~= shownGoto then text = nil end
                if (entry.a[1] == "mob" or entry.a[1] == "unitscan") and entry ~= firstMob then text = nil end
                if not npc and not object and mobs[1] and entry == shownGoto and not entry.a.t then
                    -- Jagdgebiet: sagen, wen du dort suchst, statt nur die Zone zu nennen
                    entry.text = ns.F("Go to %s", Colored(HEX_BAD, mobs[1]))
                end
                if npc and hasGoto then
                    if entry.a[1] == "target" then
                        text = nil
                    elseif entry.a[1] == "goto" and not entry.a.t then
                        -- der NPC dieses Wegpunkts, nicht der erste des Schritts (zwei NPCs, zwei Orte)
                        entry.text = ns.F("Go to %s", Colored(HEX_ACCENT, ns.NPC(R.GotoNpc(actions, entry) or npc)))
                    end
                elseif object and entry.a[1] == "goto" and not entry.a.t then
                    entry.text = ns.F("Go to %s", Colored(HEX_ACCENT, object))
                end
                -- Stockwerk ansagen: die Koordinate stimmt, aber das Ziel liegt über oder unter dir
                local floor = ref.route.s[ref.si].fl
                if floor and entry.a[1] == "goto" and text then
                    entry.text = (entry.text or text) .. "  " .. Colored(HEX_WARN, floor == "up" and ns.L["Upstairs"] or ns.L["Downstairs"])
                end
                if text and count < MAX_ROWS then
                    count = count + 1
                    if not firstOpen and (P.BLOCKING[entry.a[1]] or entry.a[1] == "goto")
                        and not P.Done(entry.a, { routeId = ref.route.id, si = ref.si, ai = entry.i }) then
                        firstOpen = true
                        entry.first = true
                    end
                    inner = inner - FillRow(GetRow(count), count, ref, entry, inner, waypoint, width) - 10
                end
            end
        end
        panel.hero:ClearAllPoints()
        panel.hero:SetPoint("TOPLEFT", LEFT, y)
        panel.hero:SetSize(width, -inner)
        panel.hero:Show()
        if view.main ~= lastMain then
            lastMain = view.main
            panel.heroFade()
        end
        y = y - (-inner) - 4

        -- Tipp des Schritts, an dem du gerade arbeitest (beim Nachholen der Nachhol-Schritt)
        local main = view.catchup and view.catchup.route.s[view.catchup.si] or (view.main and route.s[view.main])
        -- Am Ziel, aber Annahme oder Abgabe noch offen: der NPC ist vielleicht gerade nicht da
        -- (Eskorte unterwegs, getötet). Das sagt Ultima dazu, statt dich ratlos stehen zu lassen.
        local absent
        local mainFloor = main and main.fl
        if mainFloor and R.AtGoal(view) then
            absent = Colored(HEX_WARN, mainFloor == "up" and ns.L["The target is on a floor above you."] or ns.L["The target is on a floor below you."])
        elseif view.main and not view.catchup and R.AtGoal(view) then
            for _, entry in ipairs(P.Pending(route.s[view.main], player, route.id, view.main)) do
                if entry.a[1] == "accept" or entry.a[1] == "turnin" then
                    absent = Colored(HEX_WARN, ns.L["Nobody here? The NPC may be away or dead. Wait for the respawn or skip with >."])
                end
            end
        end
        -- Alle Hinweise des Schritts (höchstens hintCount), nicht nur der erste: "Klicke das Objekt an" steht
        -- oft erst an zweiter Stelle. Hinweise mit einem anklickbaren Objekt zuerst.
        local tipText
        if main and main.h and ns.db.hints then
            local first, rest = {}, {}
            for _, h in ipairs(main.h) do
                if h:find("{pick:", 1, true) then first[#first + 1] = h else rest[#rest + 1] = h end
            end
            for _, h in ipairs(rest) do first[#first + 1] = h end
            local lines = {}
            for i = 1, math.min(ns.db.hintCount, #first) do lines[i] = T.Render(first[i]) end
            if #lines > 0 then tipText = table.concat(lines, "\n") end
        end
        if absent then tipText = (tipText and (tipText .. "\n") or "") .. absent end
        if tipText then
            panel.tip:ClearAllPoints()
            panel.tip:SetPoint("TOPLEFT", LEFT, y)
            panel.tip:SetText(tipText)
            panel.tip:Show()
            y = y - panel.tip:GetStringHeight() - 12
        end

        local nextSi = ns.db.showNext and NextMain(view, player) or nil
        if nextSi then
            local lines = {}
            for _, e in ipairs(P.Actions(route.s[nextSi], player)) do
                local text = T.Action(e.a)
                if text and P.BLOCKING[e.a[1]] and #lines < 2 then lines[#lines + 1] = text end
            end
            if #lines > 0 then
                Rule(y)
                y = y - 10
                panel.nextLabel:ClearAllPoints()
                panel.nextLabel:SetPoint("TOPLEFT", LEFT, y)
                panel.nextLabel:Show()
                panel.nextText:ClearAllPoints()
                panel.nextText:SetPoint("TOPLEFT", LEFT, y - 18)
                panel.nextText:SetText(table.concat(lines, "\n"))
                panel.nextText:Show()
                y = y - 24 - panel.nextText:GetStringHeight()
            end
        end
    else
        panel.travel:Hide()
    end
    for i = count + 1, #rows do rows[i]:Hide() end
    for i = ruleCount + 1, #rules do rules[i]:Hide() end

    y = y - 6
    panel.buttons:ClearAllPoints()
    panel.buttons:SetPoint("TOPLEFT", panel, "TOPLEFT", LEFT - TRAY_INSET, y)
    -- nur die Hülle wächst, siehe Build; die Schiene verteilt sich über die neue Höhe
    panel.bodyH = -y + TRAY_H + TRAY_INSET
    panel.body:SetHeight(panel.bodyH)
    RenderRail(panel.railTotal, panel.railAt)
    PlaceMark()
end

ns.On("VIEW", function(view) ns.Guard("Panel", Render, view) end)

-------------------------------------------------------------------------------
-- Routenwahl und Dungeon-Vorbereitung: eine Liste im selben Aufklapp-Fenster
--   Eintrag: text, right (Zahl rechts), current (gewählt), muted (erledigt), fn (Klick), keep (Liste bleibt
--   offen), tip (Tooltip füllen), gap (Abstand danach)
-------------------------------------------------------------------------------
local function ShowList(anchor, entries)
    if not picker then
        picker = CreateFrame("Frame", "UltimaRoutePicker", panel)
        picker:SetFrameStrata("DIALOG")
        picker:SetClampedToScreen(true) -- die Dungeon-Liste ist lang: nie über den Bildschirmrand
        ns.Round(picker, "shadow", 24, { 0, 0, 0, 0.6 }, "BACKGROUND", -1, 14)
        ns.Round(picker, "round", TH.radius.panel, C.panel, "BACKGROUND")
        ns.Round(picker, "ring", TH.radius.panel, C.cardBorder, "BORDER")
        picker.buttons = {}
    end
    for _, b in ipairs(picker.buttons) do b:Hide() end
    local y = -8
    for i, entry in ipairs(entries) do
        local b = picker.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, picker)
            b:SetSize(WIDTH - 16, 26)
            b.hl = ns.Round(b, "round", TH.radius.control, C.card, "BACKGROUND")
            b.hl:SetShown(false)
            b.label = Label(b, SZ.body, C.text2, "Medium")
            b.label:SetPoint("LEFT", 10, 0)
            b.right = Label(b, SZ.small, C.text3, "Bold")
            b.right:SetPoint("RIGHT", -10, 0)
            b.right:SetJustifyH("RIGHT")
            b:SetScript("OnEnter", function(self)
                self.hl:SetShown(true)
                if self.tip then
                    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                    self.tip(GameTooltip)
                    GameTooltip:Show()
                end
            end)
            b:SetScript("OnLeave", function(self)
                self.hl:SetShown(self.isCurrent and true or false)
                GameTooltip_Hide()
            end)
            picker.buttons[i] = b
        end
        b.isCurrent = entry.current
        b.tip = entry.tip
        b.hl:SetShown(entry.current and true or false)
        Paint(b.label, entry.current and C.text or (entry.muted and C.text3 or C.text2))
        b.label:SetText(entry.text)
        b.right:SetText(entry.right or "")
        local rightW = entry.right and (ns.TextWidth(b.right) + 16) or 0
        ns.Fit(b.label, WIDTH - 40 - rightW, 10)
        b:SetScript("OnClick", function()
            if not entry.keep then picker:Hide() end
            entry.fn()
            ns.RequestUpdate()
        end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 8, y)
        b:Show()
        y = y - 26
        if entry.gap then y = y - 8 end
    end
    picker:SetSize(WIDTH, -y + 8)
    picker:ClearAllPoints()
    picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    picker:Show()
end

-- Dungeon-Vorbereitung: je Dungeon die Quests, die es dafür gibt; rechts, wie viele erledigt sind
local function DungeonEntries()
    local entries = {}
    local current = ns.cdb.route
    -- in einer Vorbereitung: der Rückweg zur Leveling-Route steht oben
    local route = current and R.Get(current)
    local back = ns.cdb.returnRoute and R.Get(ns.cdb.returnRoute)
    if R.IsBonus(route) and back then
        entries[#entries + 1] = { text = ns.F("Back to %s", R.DisplayName(back)), gap = true, fn = function() R.EndBonus() end }
    end
    for _, d in ipairs(R.DungeonList()) do
        local finished = d.done >= d.total
        entries[#entries + 1] = {
            text = d.name .. (d.range and ("  " .. Colored(HEX_MUTED, d.range)) or ""),
            right = ns.F("%d of %d done", d.done, d.total),
            current = current == d.route.id,
            muted = finished,
            fn = function()
                R.StartBonus(d.route.id)
                print(ns.PREFIX .. ns.F("Dungeon quests for %s started. Your route continues afterwards.", d.name))
            end,
            tip = function(tooltip)
                tooltip:SetText(d.name, 1, 1, 1, 1, true)
                for _, q in ipairs(R.DungeonQuests(d.route)) do
                    local c = S.TurnedIn(q.q) and C.text3 or (S.OnQuest(q.q) and C.text or C.text2)
                    tooltip:AddLine(T.Action(q.a), c[1], c[2], c[3], true)
                end
                tooltip:AddLine(ns.L["Grey: done. White: in your quest log."], C.text3[1], C.text3[2], C.text3[3], true)
            end,
        }
    end
    if #entries == 0 then
        entries[1] = { text = ns.L["No dungeon quests for your faction."], muted = true, fn = function() end }
    end
    return entries
end

local function ToggleDungeons(anchor)
    if picker and picker:IsShown() and picker.mode == "dungeons" then picker:Hide() return end
    ShowList(anchor, DungeonEntries())
    picker.mode = "dungeons"
end

local function TogglePicker(anchor)
    if picker and picker:IsShown() then picker:Hide() return end
    local player = S.Player()
    local entries = {}
    local route = ns.cdb.route and R.Get(ns.cdb.route)
    local back = ns.cdb.returnRoute and R.Get(ns.cdb.returnRoute)
    if R.IsBonus(route) and back then
        entries[#entries + 1] = { text = ns.F("Back to %s", R.DisplayName(back)), fn = function() R.EndBonus() end }
    end
    entries[#entries + 1] = { text = ns.L["Prepare a dungeon"], keep = true,
        fn = function() ShowList(anchor, DungeonEntries()); picker.mode = "dungeons" end }
    entries[#entries + 1] = { text = ns.L["Automatic for your level"], fn = function() R.AutoSelect(true) end }
    entries[#entries + 1] = { text = (ns.db.routeKind == "dungeonroute" and ns.L["Dungeon routes: on"] or ns.L["Dungeon routes: off"]),
        gap = true,
        fn = function()
            ns.db.routeKind = ns.db.routeKind == "dungeonroute" and "route" or "dungeonroute"
            R.AutoSelect(true)
        end }
    local current = ns.cdb.route
    for _, kind in ipairs({ "route", "dungeonroute" }) do
        for _, r in ipairs(R.Candidates(player, kind)) do
            if r.hi >= player.level - 1 and r.lo <= player.level + 3 then
                local tags = (kind == "dungeonroute" and "  " .. Colored(HEX_MUTED, ns.L["Dungeon"]) or "")
                    .. (r.era and "  " .. Colored(HEX_MUTED, ns.L["Classic"]) or "")
                entries[#entries + 1] = { text = r.n .. tags, current = current == r.id,
                    fn = function() R.Load(r.id) end }
            end
        end
    end
    ShowList(anchor, entries)
    picker.mode = "routes"
end
ns.ToggleRoutePicker = function() if panel then TogglePicker(panel.listButton) end end
ns.ToggleDungeonPicker = function()
    if not panel then return end
    if not panel:IsShown() and not InCombatLockdown() then panel:Show() end
    ToggleDungeons(panel.listButton)
end

-------------------------------------------------------------------------------
-- Aufbau
-------------------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame", "UltimaPanel", UIParent)
    panel:SetWidth(WIDTH)
    panel:SetScale(ns.db.window.scale or 1)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    -- Das Fenster selbst hat eine feste Größe: an ihm hängen die geschützten Spalten der Statusleiste, und
    -- ein Rahmen, an dem geschützte Knöpfe verankert sind, darf im Kampf weder Größe noch Lage ändern
    -- (ADDON_ACTION_BLOCKED bei SetHeight). Fläche und Schiene liegen deshalb auf einer eigenen Hülle,
    -- die frei mit dem Inhalt wächst.
    panel:SetHeight(FIXED_H)
    panel:SetFrameLevel(5)
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT")
    body:SetPoint("TOPRIGHT")
    body:SetHeight(FIXED_H)
    body:SetFrameLevel(4) -- unter dem Fenster, damit die Hülle keine Texte verdeckt
    panel.body = body
    panel.bodyH = FIXED_H
    ns.Round(body, "shadow", 24, { 0, 0, 0, 0.6 }, "BACKGROUND", -2, 14)
    ns.Round(body, "round", TH.radius.panel, C.panel, "BACKGROUND", 0)
    -- Lichtkante oben (1 px, Weiß 6 %) statt Rahmen
    local edge = body:CreateTexture(nil, "BORDER")
    edge:SetTexture(ns.WHITE)
    edge:SetHeight(1)
    edge:SetPoint("TOPLEFT", TH.radius.panel, -1)
    edge:SetPoint("TOPRIGHT", -TH.radius.panel, -1)
    Paint(edge, TH.color.neutral, 0.06)
    -- Schiene: Haarlinie rechts der 22-px-Spalte, Striche und Glutmarke entstehen in RenderRail
    local railLine = Hairline(body, "BORDER")
    railLine:SetWidth(1)
    railLine:SetPoint("TOPLEFT", RAIL, 0)
    railLine:SetPoint("BOTTOMLEFT", RAIL, 0)
    panel.mark = body:CreateTexture(nil, "OVERLAY")
    panel.mark:SetTexture(ns.WHITE)
    panel.mark:SetSize(15, 3)
    Paint(panel.mark, A1)
    body:EnableMouse(true)
    body:RegisterForDrag("LeftButton")
    body:SetScript("OnDragStart", function()
        if not InCombatLockdown() and not ns.db.window.locked then
            panel.dragging = true
            panel:StartMoving()
        end
    end)
    -- Loslassen beendet nur ein Ziehen, das auch begonnen hat. Im Kampf ist das Fenster gesperrt:
    -- ein dort begonnener Ziehversuch darf nichts anfassen (ADDON_ACTION_BLOCKED StopMovingOrSizing).
    panel.StopDrag = function()
        if not panel.dragging then return end
        panel.dragging = nil
        panel:StopMovingOrSizing()
        local point, _, relPoint, x, y = panel:GetPoint()
        ns.db.window.point = { point, relPoint, x, y }
    end
    body:SetScript("OnDragStop", function()
        if not InCombatLockdown() then panel.StopDrag() end
    end)
    local p = ns.db.window.point
    if p then panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else panel:SetPoint("TOPRIGHT", UIParent, "RIGHT", -60, 280) end
    panel:SetMovable(true) -- gezogen wird an der Hülle (body), im Kampf und bei gesperrter Lage nicht

    -- Kopf: Routenname in Zahlengröße, darunter der Schritt; rechts "Stufe" klein und das Level als Zahl
    panel.title = Label(panel, SZ.figure, C.text, "Bold")
    panel.title:SetPoint("TOPLEFT", LEFT, -12)
    panel.title:SetWordWrap(false)
    panel.sub = Label(panel, SZ.small, C.text2, "Medium")
    panel.sub:SetPoint("TOPLEFT", LEFT, -46)
    panel.levelText = Label(panel, SZ.figure, C.text, "Bold")
    panel.levelText:SetJustifyH("RIGHT")
    panel.levelText:SetPoint("TOPRIGHT", -RIGHT, -12)
    panel.levelLabel = Label(panel, SZ.small, C.text3, "Medium")
    panel.levelLabel:SetJustifyH("RIGHT")
    panel.levelLabel:SetPoint("TOPRIGHT", -RIGHT, -46)
    panel.levelLabel:SetText(ns.L["Level"])

    -- XP: 4-px-Balken, Spur in der Linienfarbe, Füllung hell, Erholt in der Farbe des Spiels
    panel.xp = Hairline(panel, "BORDER")
    panel.xp:SetHeight(4)
    panel.xp:SetPoint("TOPLEFT", LEFT, -70)
    panel.xp:SetPoint("TOPRIGHT", -RIGHT, -70)
    panel.rest = panel:CreateTexture(nil, "ARTWORK", nil, 1)
    panel.rest:SetTexture(ns.WHITE)
    panel.rest:SetHeight(4)
    panel.rest:SetPoint("TOPLEFT", panel.xp, "TOPLEFT")
    Paint(panel.rest, C.rest, 0.5)
    panel.xpFill = panel:CreateTexture(nil, "ARTWORK", nil, 2)
    panel.xpFill:SetTexture(ns.WHITE)
    panel.xpFill:SetHeight(4)
    panel.xpFill:SetPoint("TOPLEFT", panel.xp, "TOPLEFT")
    Paint(panel.xpFill, C.text)
    panel.xpLeft = Label(panel, SZ.small, C.text2, "Medium")
    panel.xpLeft:SetPoint("TOPLEFT", panel.xp, "BOTTOMLEFT", 0, -6)
    panel.xpRight = Label(panel, SZ.small, C.text2, "Medium")
    panel.xpRight:SetPoint("TOPRIGHT", panel.xp, "BOTTOMRIGHT", 0, -6)
    panel.xpRight:SetJustifyH("RIGHT")
    -- Haarlinie über der Statusleiste
    local statusRule = Hairline(panel, "BORDER")
    statusRule:SetHeight(1)
    statusRule:SetPoint("TOPLEFT", LEFT, TILE_Y + 8)
    statusRule:SetPoint("TOPRIGHT", -RIGHT, TILE_Y + 8)

    -- Reise
    panel.travel = CreateFrame("Frame", nil, panel)
    panel.travelLabel = Label(panel.travel, SZ.small, C.text3, "Medium")
    panel.travelLabel:SetText(ns.L["TRAVEL"])
    panel.travel:Hide()

    -- Jetzt: ohne Karte, die Haarlinie darüber trennt
    panel.hero = CreateFrame("Frame", nil, panel)
    panel.heroLabel = Label(panel.hero, SZ.small, C.text3, "Medium")
    panel.heroLabel:SetText(ns.L["NOW"])
    panel.heroFade = ns.FadeIn(panel.hero, TH.motion.base)

    panel.tip = Label(panel, SZ.small, C.text2, "Medium")
    panel.tip:SetWidth(CW)
    panel.tip:SetWordWrap(true)
    panel.alert = Label(panel, SZ.small, C.text2, "Medium")
    panel.alert:Hide()
    BuildTiles()
    panel.nextLabel = Label(panel, SZ.small, C.text3, "Medium")
    panel.nextLabel:SetText(ns.L["NEXT"])
    panel.nextText = Label(panel, SZ.body, C.text2, "Medium")
    panel.nextText:SetWidth(CW)
    panel.nextText:SetWordWrap(true)

    -- Werkzeugleiste unten (Knöpfe als Kacheln, siehe ns.PANEL_BUTTONS)
    -- Werkzeugleiste: eine Schale unten im Fenster, die Knöpfe als Kacheln in Gruppen nach Zweck
    panel.buttons = CreateFrame("Frame", nil, panel)
    panel.buttons:SetSize(CW + 2 * TRAY_INSET, TRAY_H)
    ns.Round(panel.buttons, "round", TH.radius.panel, C.card, "BACKGROUND")
    local actions = {
        back = function() if ns.view then R.Back(ns.view) ns.RequestUpdate() end end,
        skip = function() if ns.view and ns.view.main then R.Skip(ns.view.main) ns.RequestUpdate() end end,
        route = function(self) TogglePicker(self) end,
        dungeon = function(self) ToggleDungeons(self) end,
        arrow = function(self)
            ns.ToggleArrow()
            self:SetActive(ns.db.arrow.shown)
        end,
        options = function() ns.ToggleOptions() end,
        help = function() ns.ShowWelcome() end,
        fold = function(self)
            ns.db.window.collapsed = not ns.db.window.collapsed
            self:SetGlyph(ns.db.window.collapsed and "plus" or "minus")
            Render()
        end,
    }
    panel.buttonByKey = {}
    local x, lastGroup = TRAY_PAD, nil
    for _, spec in ipairs(ns.PANEL_BUTTONS) do
        local b = ns.IconButton(panel.buttons, spec.glyph, BUTTON)
        b:SetTip(ns.L[spec.name], ns.L[spec.desc])
        b:SetScript("OnClick", actions[spec.key])
        b:ClearAllPoints()
        if spec.group == "view" then
            -- Einklappen gehört zur Ansicht: ganz rechts, abgesetzt
            b:SetPoint("RIGHT", panel.buttons, "RIGHT", -TRAY_PAD, 0)
        else
            if lastGroup and lastGroup ~= spec.group then x = x + GROUP_GAP - BUTTON_GAP end
            b:SetPoint("LEFT", panel.buttons, "LEFT", x, 0)
            x = x + BUTTON + BUTTON_GAP
            lastGroup = spec.group
        end
        panel.buttonByKey[spec.key] = b
    end
    panel.listButton = panel.buttonByKey.route
    panel.buttonByKey.fold:SetGlyph(ns.db.window.collapsed and "plus" or "minus")
    panel.buttonByKey.arrow:SetActive(ns.db.arrow.shown)

    -- Kampf: abdunkeln; Schiene und Zahlen bleiben ruhig stehen
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent", function(self, event)
        panel.inCombat = event == "PLAYER_REGEN_DISABLED"
        -- Kampfbeginn mitten im Ziehen: jetzt noch beenden, einen Moment später ist das Fenster gesperrt
        if panel.inCombat then panel.StopDrag() end
        ns.ApplyPanelAlpha()
    end)

    -- Balken und Glutmarke gleiten weich (Slide, hängt sich nach Ankunft ab); der Inhalt wird bei jeder
    -- Auswertung (VIEW) neu gezeichnet
    StartSlide()
    ns.panel = panel
    Render()
end

ns.On("READY", Build)

function ns.TogglePanel()
    if not panel then return end
    if InCombatLockdown() then
        print(ns.WARN .. ns.L["The window can't be shown or hidden in combat."])
        return
    end
    panel:SetShown(not panel:IsShown())
end
