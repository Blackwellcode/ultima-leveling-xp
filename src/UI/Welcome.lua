-- Willkommensfenster beim ersten Start eines Charakters (Hausstil Blackwellcode, Theme.lua).
--   Seite 1  So funktioniert Ultima: Skizze des Fensters mit nummerierter Legende, vier Funktionen
--   Seite 2  Die Knöpfe: jeder Knopf mit Symbol, Name und Zweck (aus ns.PANEL_BUTTONS)
--   Seite 3  Deine Route: Berufe entlang der Route (je Charakter), Dungeons
--   Seite 4  Hilfen: Automatik, Reiseplaner, Anzeige
-- Links die Schiene des Hauses mit einem Strich je Seite; die Glutmarke steht auf der aktuellen Seite.
-- Gespeichert: ns.cdb.welcomed (gesehen), ns.cdb.professions (je Charakter), alles andere im Konto (ns.db).
-- Wieder öffnen: /ultima willkommen (welcome, setup) oder Optionen > Berufe.
local _, ns = ...
local L = ns.L
local C, A1 = ns.COLORS, ns.ACCENT
local TH = ns.Theme
local SZ = TH.size

local WIDTH, HEIGHT = 540, 560
local RAIL = 22
local LEFT, RIGHT = RAIL + 18, 20
local CW = WIDTH - LEFT - RIGHT
local LABEL_W = 92 -- Spalte für die Bezeichnung jeder Zeile
local FOOTER_H = 56
local TOP = 104    -- Seiten beginnen unter Kopf und Haarlinie
local SWITCH_ROW = 28

local frame, pages, ticks, current = nil, {}, {}, 1

local function Paint(region, c, a)
    if region.SetTextColor then
        region:SetTextColor(c[1], c[2], c[3], a or c[4] or 1)
    else
        region:SetVertexColor(c[1], c[2], c[3], a or c[4] or 1)
    end
end

local function Hairline(parent)
    local t = parent:CreateTexture(nil, "BORDER")
    t:SetTexture(ns.WHITE)
    if t.SetSnapToPixelGrid then
        t:SetSnapToPixelGrid(false)
        t:SetTexelSnappingBias(0)
    end
    Paint(t, C.cardBorder)
    return t
end

-- Knopf des Hauses: hell gefüllt (Hauptaktion) oder ruhig mit Haarlinien-Rand. Die Glutfarbe gehört in
-- diesem Fenster der Schienen-Marke, deshalb ist die Hauptaktion hell statt orange.
-- Textknopf aus dem gemeinsamen Baukasten (Kit.lua): Hauptaktion hell mit Pfeil, sonst als Kachel.
-- Die Glutfarbe gehört in diesem Fenster der Schienen-Marke, deshalb ist die Hauptaktion hell.
local function Button(parent, text, primary, onClick)
    local b = ns.TextButton(parent, text, primary and "primary" or "secondary", primary and "right" or nil, true)
    b:SetScript("OnClick", onClick)
    return b
end

-- Schalter wie im Optionsfenster: an = helle Spur mit Graphit-Knopf, aus = Linienfarbe
local function Switch(parent, get, set)
    local sw = CreateFrame("Button", nil, parent)
    sw:SetSize(40, 22)
    sw.bg = ns.Round(sw, "circle", 11, C.cardBorder, "BACKGROUND")
    sw.knob = sw:CreateTexture(nil, "ARTWORK")
    sw.knob:SetTexture(ns.TEX .. "ulx-circle")
    sw.knob:SetSize(16, 16)
    function sw:Refresh()
        local on = get() and true or false
        self.knob:ClearAllPoints()
        self.knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
        local track, knob = on and C.text or C.cardBorder, on and TH.color.accentInk or C.text3
        self.bg:SetColor(track[1], track[2], track[3], 1)
        Paint(self.knob, knob, 1)
    end
    sw:SetScript("OnClick", function(self)
        set(not get())
        self:Refresh()
    end)
    sw:Refresh()
    return sw
end

-- Überschrift einer Seite (Überschriftgröße, Satzschreibung)
local function Heading(parent, text, y)
    local fs = ns.Label(parent, SZ.heading, C.text, "OVERLAY", "Bold")
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(text)
    ns.Fit(fs, CW, 11)
    return fs
end

-- Kleine Bezeichnung über einer Gruppe (klein, gedämpft)
local function Label(parent, text, y)
    local fs = ns.Label(parent, SZ.small, C.text3, "OVERLAY", "Medium")
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetText(text)
    ns.Fit(fs, CW, 9)
    return fs
end

-- Erklärender Absatz über die volle Breite. Liefert die Höhe.
local function Paragraph(parent, text, y)
    local fs = ns.Label(parent, SZ.small, C.text2, "OVERLAY", "Medium")
    fs:SetPoint("TOPLEFT", 0, y)
    fs:SetWidth(CW)
    fs:SetWordWrap(true)
    fs:SetText(text)
    return fs:GetStringHeight()
end

-- Zeile: Bezeichnung links (klein, gedämpft), Erklärung rechts (Text, umbrechend). Liefert die Höhe.
local function InfoRow(parent, label, text, y)
    local l = ns.Label(parent, SZ.small, C.text3, "OVERLAY", "Medium")
    l:SetPoint("TOPLEFT", 0, y - 2)
    l:SetText(label)
    ns.Fit(l, LABEL_W - 8, 9)
    local t = ns.Label(parent, SZ.small, C.text2, "OVERLAY", "Medium")
    t:SetPoint("TOPLEFT", LABEL_W, y)
    t:SetWidth(CW - LABEL_W)
    t:SetWordWrap(true)
    t:SetText(text)
    return math.max(16, t:GetStringHeight()) + 10
end

-- Schalter-Zeile: Text links, Schalter rechts. Nach jeder Änderung gelten die Einstellungen sofort.
local function SwitchRow(page, label, y, get, set)
    local t = ns.Label(page, SZ.body, C.text, "OVERLAY", "Medium")
    t:SetPoint("TOPLEFT", 0, y - 3)
    t:SetText(label)
    ns.Fit(t, CW - 56, 10)
    local sw = Switch(page, get, function(value)
        set(value)
        if ns.ApplySettings then ns.ApplySettings() end
    end)
    sw:SetPoint("TOPRIGHT", 0, y)
    page.switches[#page.switches + 1] = sw
    return sw
end

-- Einstellung im Konto über einen Pfad ("travel.flights")
local function Account(path)
    local function walk()
        local t, last = ns.db, nil
        for key in path:gmatch("[^%.]+") do
            if last then t = t[last] end
            last = key
        end
        return t, last
    end
    return function() local t, k = walk() return t[k] end, function(v) local t, k = walk() t[k] = v end
end

local function Profession(key)
    return function() return ns.cdb.professions[key] ~= false end, function(on)
        ns.cdb.professions[key] = on and true or false
    end
end

-------------------------------------------------------------------------------
-- Seiten
-------------------------------------------------------------------------------
local GLYPHS = { "left", "right", "list", "settings", "minus" }

-- Rechteck in Token-Farbe (Skizze des Fensters: Balken stehen für Text, kein echter Text in Kleinstgröße)
local function Bar(parent, x, y, w, h, color, alpha)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetTexture(ns.WHITE)
    t:SetSize(w, h)
    t:SetPoint("TOPLEFT", x, y)
    Paint(t, color, alpha)
    return t
end

-- Nummer in einem Ring, verbindet Skizze und Legende
local function Badge(parent, n, x, y)
    local b = CreateFrame("Frame", nil, parent)
    b:SetSize(20, 20)
    b:SetPoint("TOPLEFT", x, y)
    ns.Round(b, "circle", 10, C.panel, "BACKGROUND")
    ns.Round(b, "ring", 10, C.text3, "BORDER")
    local fs = ns.Label(b, SZ.small, C.text, "OVERLAY", "Bold")
    fs:SetPoint("CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetText(tostring(n))
    return b
end

-- Skizze des Ultima-Fensters: Schiene mit Glutmarke, Kopf, XP, Statusleiste, Schrittsatz, Zeilen, Knöpfe
local SKETCH_W, SKETCH_H = 176, 222
local function Sketch(page, y0)
    local s = CreateFrame("Frame", nil, page)
    s:SetSize(SKETCH_W, SKETCH_H)
    s:SetPoint("TOPLEFT", 0, y0)
    ns.Round(s, "round", TH.radius.panel, C.card, "BACKGROUND")
    ns.Round(s, "ring", TH.radius.panel, C.cardBorder, "BORDER")
    -- Schiene
    Bar(s, 16, -1, 1, SKETCH_H - 2, C.cardBorder)
    for i = 0, 13 do Bar(s, 6, -10 - i * 15, 6, 1, i < 4 and C.text3 or C.cardBorder) end
    Bar(s, 3, -69, 12, 3, A1)
    -- Kopf: Routenname, Level, Schrittzeile
    Bar(s, 26, -12, 92, 9, C.text)
    Bar(s, 152, -12, 14, 9, C.text)
    Bar(s, 26, -28, 54, 4, C.text3)
    -- XP-Balken
    Bar(s, 26, -42, 140, 3, C.cardBorder)
    Bar(s, 26, -42, 56, 3, C.text)
    -- Statusleiste: vier Spalten, eine mit dem orangen Wort
    for i = 0, 3 do
        Bar(s, 26 + i * 36, -56, 22, 3, C.text3)
        Bar(s, 26 + i * 36, -64, 26, 5, i == 1 and A1 or C.text2)
    end
    Bar(s, 26, -78, 140, 1, C.cardBorder)
    -- Schrittsatz mit Entfernung rechts
    Bar(s, 26, -90, 96, 7, C.text)
    Bar(s, 140, -90, 26, 7, C.text)
    Bar(s, 148, -101, 18, 3, C.text3)
    -- Zeilen mit Verb-Spalte
    for i = 0, 2 do
        local y = -116 - i * 20
        Bar(s, 26, y + 1, 1 + 140, 1, C.cardBorder)
        Bar(s, 26, y - 6, 26, 4, C.text3)
        Bar(s, 60, y - 6, 70 - i * 12, 5, C.text2)
    end
    -- Knöpfe unten rechts
    for i, glyph in ipairs(GLYPHS) do
        local g = s:CreateTexture(nil, "ARTWORK")
        g:SetTexture(ns.TEX .. "ulx-glyph-" .. glyph)
        g:SetSize(10, 10)
        g:SetPoint("BOTTOMRIGHT", -8 - (5 - i) * 16, 10)
        Paint(g, C.text2)
    end
    -- Pfeil-Scheibe neben dem Fenster
    local dial = CreateFrame("Frame", nil, page)
    dial:SetSize(38, 38)
    dial:SetPoint("TOPLEFT", SKETCH_W + 10, y0 - 76)
    ns.Round(dial, "circle", 19, C.card, "BACKGROUND")
    ns.Round(dial, "ring", 19, C.cardBorder, "BORDER")
    local head = dial:CreateTexture(nil, "ARTWORK")
    head:SetTexture(ns.TEX .. "ulx_navigation_arrow-1")
    head:SetSize(22, 22)
    head:SetPoint("CENTER")
    Paint(head, A1)
    -- Nummern an den Teilen
    Badge(page, 1, -10, y0 - 60)
    Badge(page, 2, SKETCH_W - 6, y0 - 84)
    Badge(page, 3, SKETCH_W - 6, y0 - 52)
    Badge(page, 4, SKETCH_W + 34, y0 - 66)
    Badge(page, 5, SKETCH_W - 6, y0 - SKETCH_H + 14)
end

-- Legende: Nummer, Bezeichnung (Überschriftgröße), ein kurzer Satz
local LEGEND_X = SKETCH_W + 64
local function Legend(page, n, label, text, y)
    Badge(page, n, LEGEND_X, y)
    local l = ns.Label(page, SZ.body, C.text, "OVERLAY", "Bold")
    l:SetPoint("TOPLEFT", LEGEND_X + 28, y + 1)
    l:SetText(label)
    ns.Fit(l, CW - LEGEND_X - 28, 10)
    local t = ns.Label(page, SZ.small, C.text2, "OVERLAY", "Medium")
    t:SetPoint("TOPLEFT", LEGEND_X + 28, y - 18)
    t:SetWidth(CW - LEGEND_X - 28)
    t:SetWordWrap(true)
    t:SetText(text)
    return 22 + t:GetStringHeight() + 8
end

-- Funktion als kleine Kachel: Titel und ein Satz
local function Feature(page, label, text, x, y, w)
    local l = ns.Label(page, SZ.body, C.text, "OVERLAY", "Bold")
    l:SetPoint("TOPLEFT", x, y)
    l:SetText(label)
    ns.Fit(l, w - 8, 10)
    local t = ns.Label(page, SZ.small, C.text2, "OVERLAY", "Medium")
    t:SetPoint("TOPLEFT", x, y - 20)
    t:SetWidth(w - 12)
    t:SetWordWrap(true)
    t:SetText(text)
end

local function BuildHowTo(page)
    Heading(page, L["How Ultima works"], 0)
    local y0 = -32
    Sketch(page, y0)
    local y = y0
    y = y - Legend(page, 1, L["Route"], L["One tick per step. The orange mark is where you are."], y)
    y = y - Legend(page, 2, L["NOW"], L["Your next step with distance and walking time. Right-click a line to skip it."], y)
    y = y - Legend(page, 3, L["Bonuses"], L["An orange word means you can act: click it."], y)
    y = y - Legend(page, 4, L["Arrow"], L["Points the way. Drag it wherever you like."], y)
    Legend(page, 5, L["Buttons"], L["Eight buttons, each one explained on the next page."], y)
    -- Darunter vier Funktionen in zwei Spalten
    local fy = y0 - SKETCH_H - 22
    local rule = Hairline(page)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, fy + 10)
    rule:SetPoint("TOPRIGHT", 0, fy + 10)
    local half = CW / 2
    Feature(page, L["Routes"], L["Level 1 to 60, picked for your level, next route by itself."], 0, fy, half)
    Feature(page, L["Progress"], L["Reads quest log, bags and spells and ticks steps off."], half, fy, half)
    Feature(page, L["TRAVEL"], L["Boat, zeppelin, flight or Hearthstone, whatever is faster."], 0, fy - 54, half)
    Feature(page, L["Map"], L["Map and nameplate markers, buttons for quest items and targets."], half, fy - 54, half)
end

-- Seite Knöpfe: jeder Knopf des Fensters mit Symbol (wie im Fenster), Name und Zweck, zwei Spalten.
-- Quelle ist ns.PANEL_BUTTONS (Panel.lua): Knopfleiste und Erklärung bleiben immer gleich.
local function BuildButtons(page)
    Heading(page, L["The buttons"], 0)
    page.items = {}
    local half = CW / 2
    local CELL_H = 74
    for i, spec in ipairs(ns.PANEL_BUTTONS or {}) do
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        local x, y = col * half, -32 - row * CELL_H
        -- derselbe Knopf wie im Fenster, hier nur zum Zeigen
        local tile = ns.IconButton(page, spec.glyph, 32)
        tile:SetPoint("TOPLEFT", x, y)
        tile:EnableMouse(false)
        local name = ns.Label(page, SZ.body, C.text, "OVERLAY", "Bold")
        name:SetPoint("TOPLEFT", x + 42, y + 1)
        name:SetText(L[spec.name])
        ns.Fit(name, half - 52, 10)
        local desc = ns.Label(page, SZ.small, C.text2, "OVERLAY", "Medium")
        desc:SetPoint("TOPLEFT", x + 42, y - 19)
        desc:SetWidth(half - 52)
        desc:SetWordWrap(true)
        desc:SetText(L[spec.desc])
        page.items[#page.items + 1] = tile
    end
    local rows = math.ceil(#page.items / 2)
    local y = -32 - rows * CELL_H - 2
    local rule = Hairline(page)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, y + 8)
    rule:SetPoint("TOPRIGHT", 0, y + 8)
    Paragraph(page, L["The round Ultima button at the minimap: left-click shows the window, right-click opens the options."], y - 4)
end

local function BuildRoute(page)
    page.switches = {}
    local y = 0
    page.title = Heading(page, "", y)
    y = y - 30
    Label(page, L["Professions along the route"], y)
    y = y - 22
    SwitchRow(page, L["First Aid"], y, Profession("firstaid"))
    SwitchRow(page, L["Cooking"], y - SWITCH_ROW, Profession("cooking"))
    SwitchRow(page, L["Fishing"], y - 2 * SWITCH_ROW, Profession("fishing"))
    y = y - 3 * SWITCH_ROW - 4
    y = y - Paragraph(page, L["Off: Ultima leaves out trainer visits and skill-up steps and takes the route as if you never learned the profession."], y) - 20
    local rule = Hairline(page)
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", 0, y + 10)
    rule:SetPoint("TOPRIGHT", 0, y + 10)
    Label(page, L["Dungeons"], y)
    y = y - 22
    SwitchRow(page, L["Show dungeon steps"], y, Account("dungeonSteps"))
    SwitchRow(page, L["Routes with dungeons"], y - SWITCH_ROW,
        function() return ns.db.routeKind == "dungeonroute" end,
        function(on)
            ns.db.routeKind = on and "dungeonroute" or "route"
            if ns.Runner then ns.Runner.AutoSelect(true) end
        end)
    y = y - 2 * SWITCH_ROW - 4
    Paragraph(page, L["Dungeon steps send you into an instance for its quests. Routes with dungeons include whole dungeon runs."] .. " " ..
        L["To collect all quests for one dungeon first: the gate button at the bottom of the window."], y)
    function page:Refresh()
        self.title:SetText(ns.F("Your route for %s", UnitName and UnitName("player") or ""))
        ns.Fit(self.title, CW, 11)
        for _, sw in ipairs(self.switches) do sw:Refresh() end
    end
end

local function BuildHelpers(page)
    page.switches = {}
    local y = 0
    Heading(page, L["Helpers"], y)
    y = y - 30
    Label(page, L["Automation"], y)
    y = y - 22
    SwitchRow(page, L["Accept and turn in route quests"], y, Account("autoQuest"))
    SwitchRow(page, L["Buy the spells a step asks for"], y - SWITCH_ROW, Account("autoTrain"))
    SwitchRow(page, L["Pick the flight destination"], y - 2 * SWITCH_ROW, Account("autoFly"))
    SwitchRow(page, L["Suggest flights and Hearthstone"], y - 3 * SWITCH_ROW, Account("travel.flights"))
    y = y - 4 * SWITCH_ROW - 14
    Label(page, L["Display"], y)
    y = y - 22
    SwitchRow(page, L["Show the arrow"], y, Account("arrow.shown"))
    SwitchRow(page, L["Show hints"], y - SWITCH_ROW, Account("hints"))
    SwitchRow(page, L["Markers on the world map"], y - 2 * SWITCH_ROW, Account("pins.world"))
    SwitchRow(page, L["Quest and level markers on nameplates"], y - 3 * SWITCH_ROW, Account("questPlates.enabled"))
    SwitchRow(page, L["Show leveling talents in the talent window"], y - 4 * SWITCH_ROW, Account("talents.overlay"))
    y = y - 5 * SWITCH_ROW - 4
    Paragraph(page, L["Ultima never picks a quest reward for you."] .. " " ..
        L["Hold Shift to pause all automation for one interaction."] .. " " ..
        L["You can change all of this later in the options."], y)
    function page:Refresh()
        for _, sw in ipairs(self.switches) do sw:Refresh() end
    end
end

-------------------------------------------------------------------------------
-- Fenster
-------------------------------------------------------------------------------
local function Close()
    ns.cdb.welcomed = true
    frame:Hide()
end

local function Show(index)
    current = index
    for i, page in ipairs(pages) do page:SetShown(i == index) end
    if pages[index].Refresh then pages[index]:Refresh() end
    -- Schiene: Glutmarke auf der aktuellen Seite, erledigte Striche gedämpft hell
    for i, t in ipairs(ticks) do Paint(t, i < index and C.text3 or C.cardBorder) end
    frame.mark:ClearAllPoints()
    frame.mark:SetPoint("LEFT", ticks[index], "LEFT", -4, 0)
    frame.step:SetText(ns.F("Page %d of %d", index, #pages))
    frame.back:SetLabel(index == 1 and L["Skip"] or L["Back"])
    frame.next:SetLabel(index == #pages and L["Start leveling"] or L["Next"])
    frame.next:ClearAllPoints()
    frame.next:SetPoint("BOTTOMRIGHT", -RIGHT, 14)
    frame.back:ClearAllPoints()
    frame.back:SetPoint("RIGHT", frame.next, "LEFT", -10, 0)
    frame.fade()
end

local BUILDERS = { BuildHowTo, BuildButtons, BuildRoute, BuildHelpers }

local function Build()
    frame = CreateFrame("Frame", "UltimaWelcome", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 40)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetScript("OnHide", function() ns.cdb.welcomed = true end) -- auch Escape zählt als gesehen
    if UISpecialFrames then table.insert(UISpecialFrames, "UltimaWelcome") end
    ns.Round(frame, "shadow", 24, { 0, 0, 0, 0.6 }, "BACKGROUND", -2, 14)
    ns.Round(frame, "round", TH.radius.panel, C.panel, "BACKGROUND", 0)
    ns.Round(frame, "ring", TH.radius.panel, C.cardBorder, "BORDER")

    -- Schiene mit einem Strich je Seite
    local railLine = Hairline(frame)
    railLine:SetWidth(1)
    railLine:SetPoint("TOPLEFT", RAIL, -1)
    railLine:SetPoint("BOTTOMLEFT", RAIL, 1)
    for i = 1, #BUILDERS do
        local t = Hairline(frame)
        t:SetSize(7, 1)
        t:SetPoint("TOPLEFT", 8, -TOP - (i - 1) * 28)
        ticks[i] = t
    end
    frame.mark = frame:CreateTexture(nil, "OVERLAY")
    frame.mark:SetTexture(ns.WHITE)
    frame.mark:SetSize(15, 3)
    Paint(frame.mark, A1)

    -- Kopf: Produktname groß, darunter ein Satz
    local title = ns.Label(frame, SZ.figure, C.text, "OVERLAY", "Bold")
    title:SetPoint("TOPLEFT", LEFT, -18)
    title:SetText(ns.TITLE)
    ns.Fit(title, CW - 40, 15)
    local intro = ns.Label(frame, SZ.small, C.text2, "OVERLAY", "Medium")
    intro:SetPoint("TOPLEFT", LEFT, -52)
    intro:SetWidth(CW - 20)
    intro:SetWordWrap(true)
    intro:SetText(L["Ultima leads you from step to step. A few short pages, then you are on your way."])
    local close = ns.IconButton(frame, "kill", 28)
    close:SetPoint("TOPRIGHT", -12, -14)
    close:SetTip(L["Close"])
    close:SetScript("OnClick", Close)
    local headRule = Hairline(frame)
    headRule:SetHeight(1)
    headRule:SetPoint("TOPLEFT", LEFT, -88)
    headRule:SetPoint("TOPRIGHT", -RIGHT, -88)

    for i, builder in ipairs(BUILDERS) do
        local page = CreateFrame("Frame", nil, frame)
        page:SetPoint("TOPLEFT", LEFT, -TOP)
        page:SetSize(CW, HEIGHT - TOP - FOOTER_H)
        builder(page)
        page:Hide()
        pages[i] = page
    end
    frame.buttonsPage = pages[2]
    frame.choices = pages[3] -- Berufe und Dungeons (auch für den Oberflächen-Test)
    frame.helpers = pages[4]

    local footRule = Hairline(frame)
    footRule:SetHeight(1)
    footRule:SetPoint("BOTTOMLEFT", LEFT, FOOTER_H)
    footRule:SetPoint("BOTTOMRIGHT", -RIGHT, FOOTER_H)
    frame.step = ns.Label(frame, SZ.small, C.text3, "OVERLAY", "Medium")
    frame.step:SetPoint("BOTTOMLEFT", LEFT, 22)
    frame.next = Button(frame, L["Next"], true, function()
        if current < #pages then Show(current + 1) else Close() end
    end)
    frame.back = Button(frame, L["Skip"], false, function()
        if current > 1 then Show(current - 1) else Close() end
    end)
    frame.fade = ns.FadeIn(frame, TH.motion.base)
    frame:Hide()
end

function ns.ShowWelcome()
    if not frame then Build() end
    frame:Show()
    Show(1)
end

-- Erster Start dieses Charakters: kurz nach dem Betreten der Welt, nie mitten im Kampf
ns.On("READY", function()
    if ns.cdb.welcomed then return end
    local function Open()
        if ns.cdb.welcomed then return end
        if InCombatLockdown() then
            local wait = CreateFrame("Frame")
            wait:RegisterEvent("PLAYER_REGEN_ENABLED")
            wait:SetScript("OnEvent", function(self)
                self:UnregisterAllEvents()
                ns.ShowWelcome()
            end)
            return
        end
        ns.ShowWelcome()
    end
    if C_Timer and C_Timer.After then C_Timer.After(3, Open) else Open() end
end)
