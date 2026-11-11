-- Panel im Keynote-Stil (DESIGN.md): runde Glasflaechen, eine Hauptaussage, weiche Bewegung.
--   Kopf      Logo-Kachel, Route, Schritt, Level-Pille
--   XP        Pillen-Balken mit Verlauf und Erholt-Abschnitt
--   REISE     Zeitleiste bei Kontinentwechsel (Faehre)
--   JETZT     Hero-Karte: Handlungen mit Icon-Kachel, Meta-Pillen, Ziel-Balken
--   DANACH    Vorschau
--   Chips     Forever-Boni als Pillen, darunter runde Glyph-Knoepfe
local _, ns = ...
local R, P, T, S = ns.Runner, ns.Progress, ns.Text, ns.State
local C, A1, A2 = ns.COLORS, ns.ACCENT, ns.ACCENT2

local WIDTH, PAD, INNER = 384, 16, 14
local FIXED_H = 190 -- feste Höhe des Fensters (Kopf bis Kacheln); die sichtbare Hülle wächst getrennt
local HEAD_W = WIDTH - 2 * PAD - 52 - 50 -- Kopftext: rechts vom Logo, links von der Level-Pille
local ICON_TILE, ICON = 30, 20
local MAX_ROWS = 8
local CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"

local panel, picker
local rows, legs = {}, {}
local lastMain
local xpShown, routeShown = 0, 0

-------------------------------------------------------------------------------
-- Hilfen
-------------------------------------------------------------------------------
local ICONS = {
    complete = "Ability_DualWield", mob = "Ability_DualWield", unitscan = "Ability_DualWield",
    target = "INV_Misc_GroupNeedMore", collect = "INV_Misc_Bag_10", ["goto"] = "Ability_Hunter_Pathfinding",
    zone = "Ability_Hunter_Pathfinding", subzone = "Ability_Hunter_Pathfinding", fly = "Ability_Hunter_Pathfinding",
    fp = "Ability_Hunter_Pathfinding", hs = "INV_Misc_Rune_01", home = "INV_Misc_Rune_01",
    train = "INV_Misc_Book_09", trainer = "INV_Misc_Book_09", vendor = "INV_Misc_Coin_01",
    xp = "Spell_Holy_SurgeOfLight", use = "INV_Misc_Gear_01", equip = "INV_Misc_Gear_01",
}
-- Eigene Glyphen in einem Strichstil, eingefärbt nach Art der Handlung: Quest gold, Kampf rot,
-- Sammeln blau, Weg und Reise im Akzentton, alles andere neutral.
local GLYPH = {
    accept = { "accept", "quest" }, turnin = { "turnin", "quest" }, abandon = { "kill", "bad" },
    complete = { "kill", "bad" }, mob = { "kill", "bad" }, unitscan = { "kill", "bad" },
    collect = { "collect", "item" }, vendor = { "collect", "neutral" }, target = { "talk", "ok" },
    ["goto"] = { "goto", "accent" }, zone = { "ship", "accent" }, subzone = { "goto", "accent" },
    fly = { "fly", "accent" }, fp = { "fly", "accent" }, hs = { "home", "accent" }, home = { "home", "accent" },
    train = { "train", "neutral" }, trainer = { "train", "neutral" }, xp = { "xp", "accent" },
    use = { "use", "item" }, equip = { "use", "item" }, boat = { "ship", "accent" },
    zeppelin = { "ship", "accent" }, tram = { "ship", "accent" },
}
local GLYPH_COLOR = {
    quest = { 0.98, 0.75, 0.14 }, bad = { 1, 0.37, 0.29 }, item = { 0.38, 0.65, 0.98 },
    ok = { 0.29, 0.87, 0.5 },
}
local function SetIcon(tex, tag, done)
    local g = GLYPH[tag]
    if g then
        local c = done and ns.COLORS.text3 or GLYPH_COLOR[g[2]] or (g[2] == "accent" and ns.ACCENT) or ns.COLORS.text2
        tex:SetTexture(ns.TEX .. "ulx-glyph-" .. g[1])
        tex:SetTexCoord(0, 1, 0, 1)
        tex:SetVertexColor(c[1], c[2], c[3], 1)
    else
        tex:SetTexture("Interface\\Icons\\" .. (ICONS[tag] or "INV_Misc_Note_01"))
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetVertexColor(1, 1, 1, 1)
    end
end

local Clock, Meters = ns.Clock, ns.Meters

local function Speed() return ns.RunSpeed() end -- im Kampf geschuetzt, siehe Kit

local function Overline(parent, text)
    local fs = ns.Label(parent, 10, A1, "OVERLAY", "Bold")
    fs:SetText(text)
    return fs
end

-- Kleine runde Info-Pille ("320 m", "0:50")
local function Pill(parent)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(18)
    f.bg = ns.Round(f, "circle", 9, { 1, 1, 1, 0.08 }, "BACKGROUND")
    f.text = ns.Label(f, 11, C.text2, "OVERLAY", "Medium")
    f.text:SetPoint("CENTER", 0, 0)
    function f:Set(text)
        self.text:SetText(text)
        self:SetWidth(self.text:GetStringWidth() + 16)
    end
    return f
end

-- Weich gleitender Wert (für Balken)
local function Approach(current, target, dt)
    local k = math.min(1, dt * 10)
    return current + (target - current) * k
end

-------------------------------------------------------------------------------
-- Runde Knoepfe mit Glyphe
-------------------------------------------------------------------------------
local function GlyphButton(glyph, tooltip, onClick)
    local b = CreateFrame("Button", nil, panel)
    b:SetSize(26, 26)
    b.bg = ns.Round(b, "circle", 13, { 1, 1, 1, 0.06 }, "BACKGROUND")
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetTexture(ns.TEX .. "ulx-glyph-" .. glyph)
    b.glyph:SetSize(16, 16)
    b.glyph:SetPoint("CENTER")
    b.glyph:SetVertexColor(C.text2[1], C.text2[2], C.text2[3])
    b:SetScript("OnClick", onClick)
    b:SetScript("OnEnter", function(self)
        self.bg:SetColor(A1[1], A1[2], A1[3], 0.22)
        self.glyph:SetVertexColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:SetColor(1, 1, 1, 0.06)
        self.glyph:SetVertexColor(C.text2[1], C.text2[2], C.text2[3])
        GameTooltip_Hide()
    end)
    return b
end

-------------------------------------------------------------------------------
-- Zeilen der Hero-Karte
-------------------------------------------------------------------------------
local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, panel.hero)
    row:RegisterForClicks("RightButtonUp")
    row.tile = CreateFrame("Frame", nil, row)
    row.tile:SetSize(ICON_TILE, ICON_TILE)
    row.tile:SetPoint("TOPLEFT", 0, 0)
    row.tileBg = ns.Round(row.tile, "round", 8, { 1, 1, 1, 0.07 }, "BACKGROUND")
    row.icon = row.tile:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(ICON, ICON)
    row.icon:SetPoint("CENTER")
    row.check = row.tile:CreateTexture(nil, "OVERLAY")
    row.check:SetTexture(CHECK)
    row.check:SetSize(14, 14)
    row.check:SetPoint("BOTTOMRIGHT", 4, -4)
    row.text = ns.Label(row, 14, C.text, "OVERLAY", "Medium")
    row.text:SetPoint("TOPLEFT", row.tile, "TOPRIGHT", 10, -1)
    row.text:SetWordWrap(true)
    row.track = CreateFrame("Frame", nil, row)
    row.track:SetHeight(4)
    row.trackBg = ns.Round(row.track, "circle", 2, { 1, 1, 1, 0.08 }, "BACKGROUND")
    row.fill = CreateFrame("Frame", nil, row.track)
    row.fill:SetPoint("TOPLEFT")
    row.fill:SetPoint("BOTTOMLEFT")
    row.fillBg = ns.Round(row.fill, "circle", 2, { A1[1], A1[2], A1[3], 1 }, "ARTWORK")
    row.count = ns.Label(row, 11, C.text2, "OVERLAY", "Medium")
    row.pill1 = Pill(row)
    row.pill2 = Pill(row)
    row.hint = ns.Label(row, 11, C.text3, "OVERLAY", "Light")
    row.hint:SetWordWrap(true)
    row:SetScript("OnClick", function(self)
        if self.si then R.Skip(self.si) ns.RequestUpdate() end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.full then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(self.full, 1, 1, 1, 1, true)
        GameTooltip:AddLine(ns.L["Click: skip step"], 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

local function FillRow(row, ref, entry, y, waypoint, width)
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
        hint = ns.F("Catch up from %s", ref.route.n or "") .. (hint and ("  ·  " .. hint) or "")
    elseif ref.kind == "open" and P.BLOCKING[a[1]] then
        hint = ns.L["Postponed, ready to turn in"] .. (hint and ("  ·  " .. hint) or "")
    end
    -- Überspringen per Klick nur für Schritte der aktiven Route
    row.si = ref.route == (ns.view and ns.view.route) and si or nil
    row.full = text
    SetIcon(row.icon, a[1], done)
    -- die erste offene Handlung trägt die Karte: fett und größer; Erledigtes tritt zurück
    local emphasis = entry.first and not done
    local styleKey = emphasis and "Bold15" or "Medium14"
    if row.styleKey ~= styleKey then
        row.styleKey = styleKey
        row.text:SetFont(ns.FontPath(emphasis and "Bold" or "Medium"), emphasis and 15 or 14, "")
    end
    row.check:SetShown(done and true or false)
    row.text:SetWidth(width - ICON_TILE - 10)
    row.text:SetText(text or "")
    row.text:SetTextColor(done and C.text3[1] or C.text[1], done and C.text3[2] or C.text[2], done and C.text3[3] or C.text[3])
    local below = -(row.text:GetStringHeight() + 7)
    local textW = width - ICON_TILE - 10

    -- Zielbalken als Pille mit Zaehler
    if need and need > 0 and not done then
        row.track:ClearAllPoints()
        row.track:SetPoint("TOPLEFT", row.text, "TOPLEFT", 0, below - 2)
        row.track:SetWidth(textW - 44)
        row.fill:SetWidth(math.max(4, (textW - 44) * math.min(1, (have or 0) / need)))
        row.count:ClearAllPoints()
        row.count:SetPoint("LEFT", row.track, "RIGHT", 8, 0)
        row.count:SetText(("%d/%d"):format(have or 0, need))
        row.track:Show()
        row.count:Show()
        below = below - 14
    else
        row.track:Hide()
        row.count:Hide()
    end

    -- Entfernung und Laufzeit als Pillen
    row.pill1:Hide()
    row.pill2:Hide()
    if waypoint == a and not done then
        local d = S.Distance(a)
        if d then
            row.pill1:Set(Meters(d))
            row.pill2:Set(Clock(d / Speed()))
            row.pill1:ClearAllPoints()
            row.pill1:SetPoint("TOPLEFT", row.text, "TOPLEFT", 0, below)
            row.pill2:ClearAllPoints()
            row.pill2:SetPoint("LEFT", row.pill1, "RIGHT", 6, 0)
            row.pill1:Show()
            row.pill2:Show()
            row.waypoint = true
            below = below - 24
        end
    else
        row.waypoint = nil
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

    local height = math.max(ICON_TILE, -below)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", panel.hero, "TOPLEFT", INNER, y)
    row:SetSize(width, height)
    row:Show()
    return height
end

-------------------------------------------------------------------------------
-- Reise-Zeitleiste
-------------------------------------------------------------------------------
local function GetLeg(i)
    if legs[i] then return legs[i] end
    local leg = CreateFrame("Frame", nil, panel.travel)
    leg:SetHeight(28)
    leg.dot = leg:CreateTexture(nil, "ARTWORK")
    leg.dot:SetTexture(ns.TEX .. "ulx-circle")
    leg.dot:SetSize(10, 10)
    leg.dot:SetPoint("TOPLEFT", 0, -3)
    leg.line = leg:CreateTexture(nil, "BACKGROUND")
    leg.line:SetTexture(ns.WHITE)
    leg.line:SetWidth(2)
    leg.line:SetPoint("TOP", leg.dot, "BOTTOM", 0, -2)
    leg.line:SetPoint("BOTTOM", leg, "BOTTOM", 0, -6)
    leg.line:SetVertexColor(1, 1, 1, 0.12)
    leg.text = ns.Label(leg, 13, C.text, "OVERLAY", "Medium")
    leg.text:SetPoint("TOPLEFT", leg.dot, "TOPRIGHT", 10, 2)
    leg.sub = ns.Label(leg, 11, C.text2, "OVERLAY", "Light")
    leg.sub:SetPoint("TOPLEFT", leg.text, "BOTTOMLEFT", 0, -2)
    legs[i] = leg
    return leg
end

local function RenderTravel(plan, y, width)
    if not plan then
        panel.travel:Hide()
        return y
    end
    panel.travel:ClearAllPoints()
    panel.travel:SetPoint("TOPLEFT", PAD, y)
    panel.travel:SetWidth(width)
    local inner = -14
    panel.travelLabel:SetPoint("TOPLEFT", INNER, inner)
    inner = inner - 18
    local current = true
    for i, leg in ipairs(plan) do
        local row = GetLeg(i)
        local color = leg.done and C.ok or (current and A1 or C.text3)
        row.dot:SetVertexColor(color[1], color[2], color[3], 1)
        row.text:SetText(leg.text)
        ns.Fit(row.text, width - 2 * INNER - 20, 10)
        row.text:SetTextColor(leg.done and C.text3[1] or C.text[1], leg.done and C.text3[2] or C.text[2],
            leg.done and C.text3[3] or C.text[3])
        local sub = leg.sub
        if leg.kind == "goto" and not leg.done and leg.point then
            local d = S.Distance(leg.point)
            if d then sub = (sub and (sub .. "  ·  ") or "") .. Meters(d) .. "  ·  " .. Clock(d / Speed()) end
        end
        row.sub:SetText(sub or "")
        ns.Fit(row.sub, width - 2 * INNER - 20, 9)
        row.line:SetShown(i < #plan)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", panel.travel, "TOPLEFT", INNER, inner)
        row:SetWidth(width - 2 * INNER)
        row:Show()
        inner = inner - ((sub and sub ~= "") and 38 or 26)
        if not leg.done then current = false end
    end
    for i = #plan + 1, #legs do legs[i]:Hide() end
    panel.travel:SetHeight(-inner + 6)
    panel.travel:Show()
    return y - (-inner + 6) - 10
end

-------------------------------------------------------------------------------
-- Boni-Kacheln: vier feste Kacheln unter der XP-Leiste. Sie sind geschuetzte Knoepfe
-- (SecureActionButton), damit ein Klick Essen essen, den Schlafsack auslegen oder ein Lagerfeuer
-- aufstellen darf. Position und Attribute aendern sich nie im Kampf.
-------------------------------------------------------------------------------
local TILE_Y, TILE_H, TILE_GAP = -108, 76, 6
local tiles = {}

local function StartSleepingBag()
    local id = ns.SLEEPING_BAG_ROUTE[UnitFactionGroup("player")]
    if not (id and R.Get(id)) then
        print(ns.WARN .. ns.L["Sleeping bag route not found for this faction."])
        return
    end
    if ns.cdb.route ~= id then ns.cdb.returnRoute = ns.cdb.route end
    R.Load(id)
    print(ns.PREFIX .. ns.L["Sleeping bag quest chain started. Your route continues afterwards."])
    ns.RequestUpdate()
end

local function BuildTiles()
    local width = (WIDTH - 2 * PAD - 3 * TILE_GAP) / 4
    for i = 1, 4 do
        local t = CreateFrame("Button", "UltimaBonusTile" .. i, panel, "SecureActionButtonTemplate")
        t:SetSize(width, TILE_H)
        t:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD + (i - 1) * (width + TILE_GAP), TILE_Y)
        t:RegisterForClicks("AnyUp", "AnyDown")
        t.bg = ns.Round(t, "round", 12, { 1, 1, 1, 0.05 }, "BACKGROUND")
        t.ring = ns.Round(t, "ring", 12, C.cardBorder, "BORDER")
        t.icon = ns.Icon(t, 24)
        t.icon:SetPoint("TOPLEFT", 10, -10)
        t.dot = t:CreateTexture(nil, "ARTWORK")
        t.dot:SetTexture(ns.TEX .. "ulx-circle")
        t.dot:SetSize(8, 8)
        t.dot:SetPoint("TOPRIGHT", -10, -12)
        t.title = ns.Label(t, 12, C.text, "OVERLAY", "Bold")
        t.title:SetPoint("TOPLEFT", 10, -40)
        t.status = ns.Label(t, 10, C.text2, "OVERLAY", "Light")
        t.status:SetPoint("TOPLEFT", 10, -56)
        t.innerW = width - 18 -- 10 links, 8 rechts bis zum Ring
        -- Der Knopf meldet Drücken und Loslassen; gestartet wird nur beim Loslassen (sonst doppelt)
        t:SetScript("PostClick", function(self, _, down)
            if self.routeAction and not down then StartSleepingBag() end
        end)
        t:SetScript("OnEnter", function(self)
            self.bg:SetColor(1, 1, 1, 0.09)
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
            GameTooltip:SetText(self.tipText or "", 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        t:SetScript("OnLeave", function(self)
            self.bg:SetColor(1, 1, 1, 0.05)
            GameTooltip_Hide()
        end)
        tiles[i] = t
    end
end

-- Nur Inhalte aendern; Attribute nur ausserhalb des Kampfes.
-- Deckkraft des Fensters: Einstellung, im Kampf der Kampf-Wert (SetAlpha ist auch im Kampf erlaubt)
function ns.ApplyPanelAlpha()
    if not panel then return end
    local w = ns.db.window
    panel:SetAlpha(panel.inCombat and math.min(w.alpha, w.combatAlpha) or w.alpha)
end

local function RenderTiles()
    local list, alerts = ns.Bonus.Tiles()
    local combat = InCombatLockdown()
    -- Kacheln ein- oder ausblenden (Einstellung tiles.shown); geschützte Knöpfe nur außerhalb des Kampfes
    if not combat then
        for _, t in ipairs(tiles) do
            if t:IsShown() ~= ns.db.tiles.shown then t:SetShown(ns.db.tiles.shown) end
        end
    end
    local titles, statuses = {}, {}
    for i, data in ipairs(list) do
        local t = tiles[i]
        local color = ns.Bonus.COLORS[data.state] or C.text3
        t.icon:SetTexture(data.icon)
        -- leerer Zustand tritt zurück, aktive Zustände zeigen ihre Farbe auch im Statustext
        local idle = data.state == "off" and not data.action
        t.icon:SetDesaturated(idle)
        t.icon:SetAlpha(idle and 0.45 or 1)
        t.title:SetTextColor(idle and C.text3[1] or C.text[1], idle and C.text3[2] or C.text[2], idle and C.text3[3] or C.text[3])
        t.dot:SetVertexColor(color[1], color[2], color[3], 1)
        t.title:SetText(data.title)
        ns.Fit(t.title, t.innerW, 9)
        local action = data.action
        if action then
            t.status:SetText(data.actionText or data.status)
            ns.Fit(t.status, t.innerW, 8)
            t.status:SetTextColor(A1[1], A1[2], A1[3])
            t.ring:SetColor(A1[1], A1[2], A1[3], 0.45)
        else
            t.status:SetText(data.status)
            ns.Fit(t.status, t.innerW, 8)
            if idle then t.status:SetTextColor(C.text3[1], C.text3[2], C.text3[3])
            else t.status:SetTextColor(color[1], color[2], color[3]) end
            if data.state == "bad" then t.ring:SetColor(color[1], color[2], color[3], 0.5)
            else t.ring:SetColor(C.cardBorder[1], C.cardBorder[2], C.cardBorder[3], C.cardBorder[4]) end
        end
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
    -- alle vier Kacheln in derselben Schriftgröße (die kleinste nötige), sonst wirkt die Reihe unruhig
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
    panel.title:SetText(route and route.n or ns.L["No route"])
    ns.Fit(panel.title, HEAD_W, 13)
    local level = S.Level()
    panel.levelText:SetText(tostring(level))
    panel.levelPill:SetWidth(math.max(26, panel.levelText:GetStringWidth() + 18))
    if route then
        local total = #route.s
        local at = view.main or total
        local sub = ns.F("Step %d of %d  ·  %d %%", at, total, math.floor(at / total * 100))
        local parked = (view.waiting or 0) + #(view.open or {})
        if parked > 0 then sub = sub .. "  ·  " .. ns.F("%d postponed", parked) end
        panel.sub:SetText(sub)
        ns.Fit(panel.sub, HEAD_W, 9)
        panel.routeTarget = at / total
    else
        panel.sub:SetText(ns.L["Route button: picks one for your level"])
        ns.Fit(panel.sub, HEAD_W, 9)
        panel.routeTarget = 0
    end
    local xp, max = S.XP()
    local rested = GetXPExhaustion() or 0
    if max > 0 then
        panel.xpTarget = xp / max
        panel.restTarget = math.min(xp + rested, max) / max
        local missing = max - xp
        panel.xpLeft:SetText(ns.F("%d %%  ·  %s XP to go", math.floor(xp / max * 100),
            BreakUpLargeNumbers and BreakUpLargeNumbers(missing) or tostring(missing)))
        panel.xpRight:SetText(rested > 0 and ns.F("Rested %d %%", math.floor(rested / max * 100 + 0.5)) or "")
    else
        panel.xpTarget, panel.restTarget = 1, 1
        panel.xpLeft:SetText(ns.L["Max level"])
        panel.xpRight:SetText("")
    end
    -- Eine Zeile, zwei Texte: rechts "Erholt" höchstens die halbe Breite, links der Rest mit 10 px Abstand
    local full = WIDTH - 2 * PAD
    ns.Fit(panel.xpRight, full / 2, 9) -- rechtsbündig, Anker rechts: die Feldbreite stört nicht
    local rightW = (panel.xpRight:GetText() or "") ~= "" and math.min(full / 2, ns.TextWidth(panel.xpRight)) + 10 or 0
    ns.Fit(panel.xpLeft, full - rightW, 9)
end

local function Render(view)
    if not panel then return end
    view = view or ns.view or {}
    RenderHeader(view)
    local route = view.route
    local width = WIDTH - 2 * PAD
    local alerts = RenderTiles()
    local y = ns.db.tiles.shown and (TILE_Y - TILE_H - 12) or (TILE_Y - 4)
    -- Warnungen (Gruppe, Dungeon) als Zeile unter den Kacheln
    -- nur echte Warnungen zeigen; "alles in Ordnung" braucht keine Zeile
    local warn = {}
    for _, a in ipairs(alerts) do if a.state ~= "ok" then warn[#warn + 1] = a end end
    alerts = warn
    if #alerts > 0 then
        local parts = {}
        for _, a in ipairs(alerts) do
            local c = ns.Bonus.COLORS[a.state] or C.text2
            parts[#parts + 1] = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, a.text)
        end
        panel.alert:ClearAllPoints()
        panel.alert:SetPoint("TOPLEFT", PAD + 2, y)
        panel.alert:SetText(table.concat(parts, "    "))
        ns.Fit(panel.alert, WIDTH - 2 * PAD - 4, 9)
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

        -- Hero-Karte
        local inner = -14
        panel.heroLabel:SetPoint("TOPLEFT", INNER, inner)
        inner = inner - 20
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
                firstMob.text = ns.F("Enemies: %s", "|cffff5f4a" .. table.concat(mobs, ", ") .. "|r")
            end
            for _, entry in ipairs(actions) do
                local text = T.Action(entry.a)
                if entry.a[1] == "goto" and entry ~= shownGoto then text = nil end
                if (entry.a[1] == "mob" or entry.a[1] == "unitscan") and entry ~= firstMob then text = nil end
                if not npc and not object and mobs[1] and entry == shownGoto and not entry.a.t then
                    -- Jagdgebiet: sagen, wen du dort suchst, statt nur die Zone zu nennen
                    entry.text = ns.F("Go to %s", "|cffff5f4a" .. mobs[1] .. "|r")
                end
                if npc and hasGoto then
                    if entry.a[1] == "target" then
                        text = nil
                    elseif entry.a[1] == "goto" and not entry.a.t then
                        entry.text = ns.F("Go to %s", "|cff4ade80" .. ns.NPC(npc) .. "|r")
                    end
                elseif object and entry.a[1] == "goto" and not entry.a.t then
                    entry.text = ns.F("Go to %s", "|cffd946ef" .. object .. "|r")
                end
                -- Stockwerk ansagen: die Koordinate stimmt, aber das Ziel liegt über oder unter dir
                local floor = ref.route.s[ref.si].fl
                if floor and entry.a[1] == "goto" and text then
                    entry.text = (entry.text or text) .. "  |cffffd133" .. (floor == "up" and ns.L["Upstairs"] or ns.L["Downstairs"]) .. "|r"
                end
                if text and count < MAX_ROWS then
                    count = count + 1
                    if not firstOpen and (P.BLOCKING[entry.a[1]] or entry.a[1] == "goto")
                        and not P.Done(entry.a, { routeId = ref.route.id, si = ref.si, ai = entry.i }) then
                        firstOpen = true
                        entry.first = true
                    end
                    inner = inner - FillRow(GetRow(count), ref, entry, inner, waypoint, width - 2 * INNER) - 12
                end
            end
        end
        panel.hero:ClearAllPoints()
        panel.hero:SetPoint("TOPLEFT", PAD, y)
        panel.hero:SetSize(width, -inner + 2)
        panel.hero:Show()
        if view.main ~= lastMain then
            lastMain = view.main
            panel.heroFade()
        end
        y = y - (-inner + 2) - 12

        -- Tipp des Schritts, an dem du gerade arbeitest (beim Nachholen der Nachhol-Schritt)
        local main = view.catchup and view.catchup.route.s[view.catchup.si] or (view.main and route.s[view.main])
        -- Am Ziel, aber Annahme oder Abgabe noch offen: der NPC ist vielleicht gerade nicht da
        -- (Eskorte unterwegs, getötet). Das sagt Ultima dazu, statt dich ratlos stehen zu lassen.
        local absent
        local mainFloor = main and main.fl
        if mainFloor and R.AtGoal(view) then
            absent = "|cffffd133" .. (mainFloor == "up" and ns.L["The target is on a floor above you."] or ns.L["The target is on a floor below you."]) .. "|r"
        elseif view.main and not view.catchup and R.AtGoal(view) then
            for _, entry in ipairs(P.Pending(route.s[view.main], player, route.id, view.main)) do
                if entry.a[1] == "accept" or entry.a[1] == "turnin" then
                    absent = "|cffffd133" .. ns.L["Nobody here? The NPC may be away or dead. Wait for the respawn or skip with >."] .. "|r"
                end
            end
        end
        -- Alle Hinweise des Schritts (höchstens 3), nicht nur der erste: "Klicke das Objekt an" steht oft
        -- erst an zweiter Stelle. Hinweise mit einem anklickbaren Objekt zuerst.
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
            panel.tip:SetPoint("TOPLEFT", PAD + 2, y)
            panel.tip:SetText(tipText)
            panel.tip:Show()
            y = y - panel.tip:GetStringHeight() - 12
        end

        local nextSi = ns.db.showNext and NextMain(view, player) or nil
        if nextSi then
            local lines = {}
            for _, e in ipairs(P.Actions(route.s[nextSi], player)) do
                local text = T.Action(e.a)
                if text and P.BLOCKING[e.a[1]] and #lines < 2 then lines[#lines + 1] = "|cff5b6170›|r  " .. text end
            end
            if #lines > 0 then
                panel.nextLabel:ClearAllPoints()
                panel.nextLabel:SetPoint("TOPLEFT", PAD + 2, y)
                panel.nextLabel:Show()
                panel.nextText:ClearAllPoints()
                panel.nextText:SetPoint("TOPLEFT", PAD + 2, y - 15)
                panel.nextText:SetText(table.concat(lines, "\n"))
                panel.nextText:Show()
                y = y - 22 - panel.nextText:GetStringHeight()
            end
        end
    else
        panel.travel:Hide()
    end
    for i = count + 1, #rows do rows[i]:Hide() end

    y = y - 4
    panel.buttons:ClearAllPoints()
    panel.buttons:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, y)
    panel.body:SetHeight(-y + 26 + PAD) -- nur die Hülle wächst, siehe Build
end

ns.On("VIEW", function(view) ns.Guard("Panel", Render, view) end)

-------------------------------------------------------------------------------
-- Routenwahl (rundes Popup)
-------------------------------------------------------------------------------
local function TogglePicker(anchor)
    if picker and picker:IsShown() then picker:Hide() return end
    if not picker then
        picker = CreateFrame("Frame", "UltimaRoutePicker", panel)
        picker:SetFrameStrata("DIALOG")
        ns.Round(picker, "shadow", 24, { 0, 0, 0, 0.9 }, "BACKGROUND", -1, 14)
        ns.Round(picker, "round", 14, { 0.07, 0.075, 0.09, 0.97 }, "BACKGROUND")
        ns.Round(picker, "ring", 14, C.cardBorder, "BORDER")
        picker.buttons = {}
    end
    for _, b in ipairs(picker.buttons) do b:Hide() end
    local player = S.Player()
    local entries = {
        { text = ns.L["Automatic for your level"], fn = function() R.AutoSelect(true) end },
        { text = (ns.db.routeKind == "dungeonroute" and ns.L["Dungeon routes: on"] or ns.L["Dungeon routes: off"]),
          fn = function()
              ns.db.routeKind = ns.db.routeKind == "dungeonroute" and "route" or "dungeonroute"
              R.AutoSelect(true)
          end },
    }
    local current = ns.cdb.route
    for _, kind in ipairs({ "route", "dungeonroute" }) do
        for _, r in ipairs(R.Candidates(player, kind)) do
            if r.hi >= player.level - 1 and r.lo <= player.level + 3 then
                local tags = (kind == "dungeonroute" and "  |cff8a8f99" .. ns.L["Dungeon"] .. "|r" or "")
                    .. (r.era and "  |cff8a8f99" .. ns.L["Classic"] .. "|r" or "")
                entries[#entries + 1] = { text = r.n .. tags, current = current == r.id,
                    fn = function() R.Load(r.id) end }
            end
        end
    end
    local y = -10
    for i, entry in ipairs(entries) do
        local b = picker.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, picker)
            b:SetSize(WIDTH - 20, 26)
            b.hl = ns.Round(b, "round", 8, { A1[1], A1[2], A1[3], 0.16 }, "BACKGROUND")
            b.hl:SetShown(false)
            b.label = ns.Label(b, 13, C.text, "OVERLAY", "Medium")
            b.label:SetPoint("LEFT", 12, 0)
            b:SetScript("OnEnter", function(self) self.hl:SetShown(true) end)
            b:SetScript("OnLeave", function(self) self.hl:SetShown(self.isCurrent and true or false) end)
            picker.buttons[i] = b
        end
        b.isCurrent = entry.current
        b.hl:SetShown(entry.current and true or false)
        b.label:SetText(entry.text)
        ns.Fit(b.label, WIDTH - 44, 10)
        b:SetScript("OnClick", function()
            picker:Hide()
            entry.fn()
            ns.RequestUpdate()
        end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 10, y)
        b:Show()
        y = y - 26
        if i == 2 then y = y - 8 end
    end
    picker:SetSize(WIDTH, -y + 10)
    picker:ClearAllPoints()
    picker:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 8)
    picker:Show()
end
ns.ToggleRoutePicker = function() if panel then TogglePicker(panel.listButton) end end

-------------------------------------------------------------------------------
-- Aufbau
-------------------------------------------------------------------------------
local function Build()
    panel = CreateFrame("Frame", "UltimaPanel", UIParent)
    panel:SetWidth(WIDTH)
    panel:SetScale(ns.db.window.scale or 1)
    panel:SetFrameStrata("MEDIUM")
    panel:SetClampedToScreen(true)
    -- Das Fenster selbst hat eine feste Größe: an ihm hängen die geschützten Kacheln, und ein Rahmen,
    -- an dem geschützte Knöpfe verankert sind, darf im Kampf weder Größe noch Lage ändern
    -- (ADDON_ACTION_BLOCKED bei SetHeight). Hintergrund und Rand liegen deshalb auf einer eigenen Hülle,
    -- die frei mit dem Inhalt wächst.
    panel:SetHeight(FIXED_H)
    panel:SetFrameLevel(5)
    local body = CreateFrame("Frame", nil, panel)
    body:SetPoint("TOPLEFT")
    body:SetPoint("TOPRIGHT")
    body:SetHeight(FIXED_H)
    body:SetFrameLevel(4) -- unter dem Fenster, damit die Hülle keine Texte verdeckt
    panel.body = body
    ns.Round(body, "shadow", 30, { 0, 0, 0, 0.85 }, "BACKGROUND", -2, 18)
    ns.Round(body, "round", 18, C.panel, "BACKGROUND", 0)
    ns.Round(body, "ring", 18, C.cardBorder, "BORDER")
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

    -- Kopf: Logo-Kachel, Titel, Unterzeile, Level-Pille
    local tile = CreateFrame("Frame", nil, panel)
    tile:SetSize(40, 40)
    tile:SetPoint("TOPLEFT", PAD, -PAD)
    local logo = tile:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.TEX .. "ulx_logo-128")
    logo:SetAllPoints()
    panel.title = ns.Label(panel, 18, C.text, "OVERLAY", "Bold")
    panel.title:SetPoint("TOPLEFT", tile, "TOPRIGHT", 12, -2)
    panel.title:SetWordWrap(false)
    panel.sub = ns.Label(panel, 11, C.text2, "OVERLAY", "Light")
    panel.sub:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -4)
    panel.levelPill = CreateFrame("Frame", nil, panel)
    panel.levelPill:SetSize(30, 24)
    panel.levelPill:SetPoint("TOPRIGHT", -PAD, -PAD - 6)
    ns.Round(panel.levelPill, "circle", 12, { A1[1], A1[2], A1[3], 0.16 }, "BACKGROUND")
    panel.levelText = ns.Label(panel.levelPill, 13, A1, "OVERLAY", "Bold")
    panel.levelText:SetPoint("CENTER", 0, 0)

    -- Routenfortschritt: feine Pille unter dem Kopf
    panel.route = CreateFrame("Frame", nil, panel)
    -- Routenfortschritt als feine Linie direkt unter der Unterzeile, nur so breit wie der Kopftext:
    -- sie gehört zum Routennamen und konkurriert nicht mehr mit dem XP-Balken darunter.
    panel.route:SetHeight(2)
    panel.route:SetPoint("TOPLEFT", PAD + 52, -57)
    panel.route:SetWidth(HEAD_W)
    ns.Round(panel.route, "circle", 1.5, { 1, 1, 1, 0.06 }, "BACKGROUND")
    panel.routeFill = CreateFrame("Frame", nil, panel.route)
    panel.routeFill:SetPoint("TOPLEFT")
    panel.routeFill:SetPoint("BOTTOMLEFT")
    ns.Round(panel.routeFill, "circle", 1.5, { A2[1], A2[2], A2[3], 0.8 }, "ARTWORK")

    -- XP: dicke Pille mit Erholt-Abschnitt
    panel.xp = CreateFrame("Frame", nil, panel)
    panel.xp:SetHeight(8)
    panel.xp:SetPoint("TOPLEFT", PAD, -76)
    panel.xp:SetPoint("TOPRIGHT", -PAD, -76)
    ns.Round(panel.xp, "circle", 4, { 1, 1, 1, 0.07 }, "BACKGROUND")
    panel.rest = CreateFrame("Frame", nil, panel.xp)
    panel.rest:SetPoint("TOPLEFT")
    panel.rest:SetPoint("BOTTOMLEFT")
    ns.Round(panel.rest, "circle", 4, { C.rest[1], C.rest[2], C.rest[3], 0.45 }, "BORDER")
    panel.xpFill = CreateFrame("Frame", nil, panel.xp)
    panel.xpFill:SetPoint("TOPLEFT")
    panel.xpFill:SetPoint("BOTTOMLEFT")
    ns.Round(panel.xpFill, "circle", 4, { A1[1], A1[2], A1[3], 1 }, "ARTWORK")
    panel.xpLeft = ns.Label(panel, 11, C.text2, "OVERLAY", "Medium")
    panel.xpLeft:SetPoint("TOPLEFT", panel.xp, "BOTTOMLEFT", 0, -6)
    panel.xpRight = ns.Label(panel, 11, C.rest, "OVERLAY", "Medium")
    panel.xpRight:SetPoint("TOPRIGHT", panel.xp, "BOTTOMRIGHT", 0, -6)
    panel.xpRight:SetJustifyH("RIGHT")

    -- Reise-Karte
    panel.travel = CreateFrame("Frame", nil, panel)
    ns.Round(panel.travel, "round", 12, C.card, "BACKGROUND", 1)
    ns.Round(panel.travel, "ring", 12, { A2[1], A2[2], A2[3], 0.35 }, "BORDER")
    panel.travelLabel = Overline(panel.travel, ns.L["TRAVEL"])
    panel.travel:Hide()

    -- Hero-Karte
    panel.hero = CreateFrame("Frame", nil, panel)
    ns.Round(panel.hero, "round", 12, { A1[1], A1[2], A1[3], 0.07 }, "BACKGROUND", 1)
    ns.Round(panel.hero, "ring", 12, { A1[1], A1[2], A1[3], 0.32 }, "BORDER")
    panel.heroLabel = Overline(panel.hero, ns.L["NOW"])
    panel.heroFade = ns.FadeIn(panel.hero, 0.3)

    panel.tip = ns.Label(panel, 12, C.text2, "OVERLAY", "Light")
    panel.tip:SetWidth(WIDTH - 2 * PAD - 4)
    panel.tip:SetWordWrap(true)
    panel.alert = ns.Label(panel, 11, C.text2, "OVERLAY", "Medium")
    panel.alert:Hide()
    BuildTiles()
    panel.nextLabel = Overline(panel, ns.L["NEXT"])
    panel.nextText = ns.Label(panel, 12, C.text2, "OVERLAY", "Medium")
    panel.nextText:SetWidth(WIDTH - 2 * PAD - 4)
    panel.nextText:SetWordWrap(true)

    -- Runde Glyph-Knoepfe unten rechts
    panel.buttons = CreateFrame("Frame", nil, panel)
    panel.buttons:SetSize(5 * 26 + 4 * 6, 26)
    local fold = GlyphButton(ns.db.window.collapsed and "plus" or "minus", ns.L["Expand or collapse steps"], function(self)
        ns.db.window.collapsed = not ns.db.window.collapsed
        self.glyph:SetTexture(ns.TEX .. "ulx-glyph-" .. (ns.db.window.collapsed and "plus" or "minus"))
        Render()
    end)
    panel.listButton = GlyphButton("list", ns.L["Choose route"], function(self) TogglePicker(self) end)
    local nextB = GlyphButton("right", ns.L["Skip step"], function()
        if ns.view and ns.view.main then R.Skip(ns.view.main) ns.RequestUpdate() end
    end)
    local backB = GlyphButton("left", ns.L["One step back"], function()
        if ns.view then R.Back(ns.view) ns.RequestUpdate() end
    end)
    local optionsB = GlyphButton("settings", ns.L["Options"], function() ns.ToggleOptions() end)
    for i, b in ipairs({ backB, nextB, panel.listButton, optionsB, fold }) do
        b:SetParent(panel.buttons)
        b:ClearAllPoints()
        b:SetPoint("LEFT", (i - 1) * 32, 0)
    end

    -- Kampf: abdunkeln
    panel:RegisterEvent("PLAYER_REGEN_DISABLED")
    panel:RegisterEvent("PLAYER_REGEN_ENABLED")
    panel:SetScript("OnEvent", function(self, event)
        panel.inCombat = event == "PLAYER_REGEN_DISABLED"
        -- Kampfbeginn mitten im Ziehen: jetzt noch beenden, einen Moment später ist das Fenster gesperrt
        if panel.inCombat then panel.StopDrag() end
        ns.ApplyPanelAlpha()
    end)

    -- Balken gleiten weich; der Inhalt wird bei jeder Auswertung (VIEW) neu gezeichnet
    panel:SetScript("OnUpdate", function(_, dt)
        local w = panel.xp:GetWidth()
        if w and w > 0 and panel.xpTarget then
            xpShown = Approach(xpShown, panel.xpTarget, dt)
            panel.xpFill:SetWidth(math.max(8, w * xpShown))
            panel.rest:SetWidth(math.max(8, w * (panel.restTarget or 0)))
            panel.rest:SetShown((panel.restTarget or 0) > (panel.xpTarget or 0) + 0.005)
            routeShown = Approach(routeShown, panel.routeTarget or 0, dt)
            panel.routeFill:SetWidth(math.max(3, panel.route:GetWidth() * routeShown))
        end
    end)
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
