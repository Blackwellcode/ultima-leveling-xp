-- Optionsfenster: Seitenleiste mit Kategorien, rechts die Einstellungen der Kategorie.
-- Aufbau nach dem Vorbild von BlackwellUI: Einstellungen sind Daten (Liste von Einträgen), die Seite baut
-- daraus Schalter, Stufenregler ("- Wert +"), Auswahl ("< Wert >") und Knöpfe. Jede Änderung wirkt sofort
-- (ns.ApplySettings), jede Kategorie hat "Zurücksetzen". Alle Texte laufen über ns.L.
-- Öffnen: /ultima options (auch /ultima optionen, /ultima config), Rechtsklick+Umschalt auf das Minimap-Symbol.
local _, ns = ...
local L = ns.L
local C, A1 = ns.COLORS, ns.ACCENT
local TH = ns.Theme

local WIDTH, HEIGHT, SIDEBAR, HEADER, FOOTER = 680, 500, 172, 44, 48
local ROW, ROW_HINT = 30, 44
local frame, pages, sideButtons, current = nil, {}, {}, nil

-------------------------------------------------------------------------------
-- Zugriff auf Einstellungen über Pfade ("window.scale")
-------------------------------------------------------------------------------
-- "char.<Pfad>" meint die Einstellungen dieses Charakters (ns.cdb), alles andere das Konto (ns.db)
local function Root(path)
    if path:sub(1, 5) == "char." then return ns.cdb, path:sub(6), ns.DEFAULTS.char end
    return ns.db, path, ns.DEFAULTS.account
end

local function Get(path)
    local t
    t, path = Root(path)
    for key in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[key]
    end
    return t
end

local function Set(path, value)
    local t, last
    t, path = Root(path)
    for key in path:gmatch("[^%.]+") do
        if last then
            if type(t[last]) ~= "table" then t[last] = {} end
            t = t[last]
        end
        last = key
    end
    t[last] = value
end

local function Default(path)
    local t
    _, path, t = Root(path)
    for key in path:gmatch("[^%.]+") do
        if type(t) ~= "table" then return nil end
        t = t[key]
    end
    return t
end

-------------------------------------------------------------------------------
-- Kategorien und Einstellungen (Reihenfolge = Anzeige)
--   toggle: path                    step: path, min, max, step, fmt ("pct", "x", "n", "s")
--   cycle: path, values = { { Wert, Text-Schlüssel }, ... }       button: fn       header / note: nur Text
-------------------------------------------------------------------------------
local function LanguageValues()
    local list = { { "auto", "Automatic (client language)" } }
    for _, code in ipairs(ns.LANGUAGES) do
        if not ns.CJK[code] or ns.CJK[ns.ClientLocale()] then list[#list + 1] = { code, code, raw = true } end
    end
    return list
end

local CATEGORIES = {
    { key = "general", label = "General", options = {
        { type = "header", label = "Size" },
        { type = "toggle", path = "window.autoScale", label = "Scale automatically",
          hint = "Fits the size to your resolution and UI scale." },
        { type = "step", path = "window.scale", label = "Window scale", min = 0.5, max = 2, step = 0.05, fmt = "x",
          manual = "window.autoScale" },
        { type = "step", path = "window.alpha", label = "Window opacity", min = 0.3, max = 1, step = 0.05, fmt = "pct" },
        { type = "step", path = "window.combatAlpha", label = "Opacity in combat", min = 0.2, max = 1, step = 0.05, fmt = "pct" },
        { type = "header", label = "Window" },
        { type = "toggle", path = "window.locked", label = "Lock position" },
        { type = "toggle", path = "minimap.hide", label = "Minimap button", invert = true },
        { type = "button", label = "Reset positions", fn = function()
            ns.db.window.point, ns.db.arrow.point = nil, nil
            ns.ApplySettings(true)
        end },
    } },
    { key = "route", label = "Route", options = {
        { type = "header", label = "Route choice" },
        { type = "cycle", path = "routeKind", label = "Route type",
          values = { { "route", "Quest routes" }, { "dungeonroute", "Routes with dungeons" } } },
        { type = "toggle", path = "predecessorFirst", label = "Finish the previous route first",
          hint = "Avoids being sent to enemies far above your level." },
        { type = "toggle", path = "dungeonSteps", label = "Show dungeon steps",
          hint = "Steps that send you into a dungeon." },
        { type = "button", label = "Choose the best route now", fn = function()
            ns.Runner.AutoSelect(true)
            ns.RequestUpdate()
        end },
        { type = "header", label = "Step display" },
        { type = "toggle", path = "hints", label = "Show hints" },
        { type = "step", path = "hintCount", label = "Hints per step", min = 1, max = 3, step = 1, fmt = "n" },
        { type = "toggle", path = "showNext", label = "Show the next step" },
    } },
    { key = "auto", label = "Automation", options = {
        { type = "note", label = "Hold Shift to pause all automation for one interaction." },
        { type = "toggle", path = "autoQuest", label = "Accept and turn in route quests",
          hint = "Never chooses between several rewards for you." },
        { type = "toggle", path = "autoTrain", label = "Buy the spells a step asks for" },
        { type = "toggle", path = "autoFly", label = "Pick the flight destination" },
        { type = "toggle", path = "fastLoot", label = "Loot instantly",
          hint = "With auto loot on, everything is picked up at once." },
        { type = "header", label = "Travel planner" },
        { type = "toggle", path = "travel.flights", label = "Suggest flights and Hearthstone" },
        { type = "step", path = "travel.minSaving", label = "Only if it saves at least", min = 30, max = 300, step = 30, fmt = "s" },
    } },
    { key = "prof", label = "Professions", options = {
        { type = "note", label = "Off: Ultima leaves out trainer visits and skill-up steps and takes the route as if you never learned the profession." },
        { type = "header", label = "Professions along the route" },
        { type = "toggle", path = "char.professions.firstaid", label = "First Aid" },
        { type = "toggle", path = "char.professions.cooking", label = "Cooking" },
        { type = "toggle", path = "char.professions.fishing", label = "Fishing" },
        { type = "button", label = "Show the welcome window again", fn = function() ns.ShowWelcome() end },
    } },
    { key = "bonus", label = "Bonuses", options = {
        { type = "toggle", path = "tiles.shown", label = "Show the bonus tiles",
          hint = "Rested, food buff, sleeping bag and camp." },
        { type = "toggle", path = "announce", label = "Announce lost bonuses on screen" },
        { type = "header", label = "Warnings" },
        { type = "toggle", path = "dangerWarn", label = "Warn about dangerous enemies" },
        { type = "step", path = "dangerGap", label = "Dangerous from this many levels above you", min = 2, max = 6, step = 1, fmt = "n" },
        { type = "toggle", path = "groupWarn", label = "Warn about high-level group members" },
    } },
    { key = "nav", label = "Arrow and map", options = {
        { type = "header", label = "Arrow" },
        { type = "toggle", path = "arrow.shown", label = "Show the arrow" },
        { type = "step", path = "arrow.scale", label = "Arrow scale", min = 0.5, max = 2, step = 0.05, fmt = "x" },
        { type = "header", label = "Map" },
        { type = "toggle", path = "pins.world", label = "Markers on the world map" },
        { type = "toggle", path = "pins.minimap", label = "Markers on the minimap" },
        { type = "step", path = "pins.dots", label = "Path points on the minimap", min = 0, max = 12, step = 1, fmt = "n" },
        { type = "header", label = "Buttons" },
        { type = "toggle", path = "buttons.item", label = "Quest item button" },
        { type = "toggle", path = "buttons.target", label = "Target button" },
    } },
    { key = "plates", label = "Nameplates", options = {
        { type = "toggle", path = "questPlates.enabled", label = "Quest and level markers on nameplates" },
        { type = "toggle", path = "questPlates.border", label = "Level border" },
        { type = "step", path = "questPlates.dangerDiff", label = "Highlight from this many levels above you", min = 2, max = 8, step = 1, fmt = "n" },
        { type = "step", path = "questPlates.eliteDangerDiff", label = "For elites from", min = 1, max = 8, step = 1, fmt = "n" },
    } },
    { key = "talents", label = "Talents", options = {
        { type = "toggle", path = "talents.overlay", label = "Show leveling talents in the talent window" },
        { type = "toggle", path = "talents.remind", label = "Remind me of free talent points" },
        { type = "note", label = "Choose the build with the arrows next to the talent window." },
    } },
    { key = "lang", label = "Language", options = {
        { type = "cycle", path = "lang", label = "Interface language", values = LanguageValues, chosen = "langChosen" },
        { type = "note", label = "Route hints and NPC names follow your game client's language where a translation exists. Missing parts stay English: route hints in Korean, Russian, Traditional Chinese and Italian, NPC names in Portuguese and Italian, some German route hints." },
    } },
}
ns.OPTION_CATEGORIES = CATEGORIES

local function Format(opt, value)
    if opt.fmt == "pct" then return ("%d %%"):format(math.floor(value * 100 + 0.5)) end
    if opt.fmt == "x" then return ("%.2f"):format(value) end
    if opt.fmt == "s" then return ("%d s"):format(value) end
    return tostring(value)
end

-------------------------------------------------------------------------------
-- Bausteine
-------------------------------------------------------------------------------
-- Knöpfe aus dem gemeinsamen Baukasten (Kit.lua, Hausstil 1.2.0)
local function GlyphButton(parent, glyph, onClick)
    local b = ns.IconButton(parent, glyph, 24)
    b:SetScript("OnClick", onClick)
    return b
end

local function TextButton(parent, text, onClick)
    local b = ns.TextButton(parent, text, "secondary")
    b:SetScript("OnClick", onClick)
    return b
end

local function Changed(opt)
    if opt.chosen then ns.db[opt.chosen] = Get(opt.path) ~= "auto" or nil end
    if opt.manual then Set(opt.manual, false) end -- von Hand gestellt: Automatik aus
    ns.ApplySettings()
    if current then current:Refresh() end
end

local function SetRowHeight(row, height)
    row:SetHeight(height)
    row.rowHeight = height
end

-- Eine Zeile je Einstellung. Liefert die Zeile; row.Refresh liest den Wert neu.
local function BuildRow(page, opt, width)
    local row = CreateFrame("Frame", nil, page)
    row:SetWidth(width)
    row.opt = opt
    local label = opt.raw and opt.label or L[opt.label]
    if opt.type == "header" then
        SetRowHeight(row, 28)
        row.text = ns.Label(row, TH.size.heading, C.text, "OVERLAY", "Bold")
        row.text:SetPoint("BOTTOMLEFT", 0, 6)
        row.text:SetText(label)
        function row:Refresh() end
        return row
    end
    if opt.type == "note" then
        row.text = ns.Label(row, 11, C.text3, "OVERLAY", "Light")
        row.text:SetPoint("TOPLEFT", 0, -4)
        row.text:SetWidth(width)
        row.text:SetWordWrap(true)
        row.text:SetText(label)
        SetRowHeight(row, 34)
        function row:Refresh() end
        return row
    end
    if opt.type == "button" then
        SetRowHeight(row, ROW + 4)
        row.button = TextButton(row, label, function()
            opt.fn()
            if current then current:Refresh() end
        end)
        row.button:SetPoint("LEFT", 0, 0)
        function row:Refresh() end
        return row
    end
    SetRowHeight(row, opt.hint and ROW_HINT or ROW)
    row.text = ns.Label(row, TH.size.body, C.text, "OVERLAY", "Medium")
    row.text:SetPoint("TOPLEFT", 0, -7)
    row.text:SetText(label)
    ns.Fit(row.text, width - 150, 10)
    if opt.hint then
        row.hint = ns.Label(row, 11, C.text3, "OVERLAY", "Light")
        row.hint:SetPoint("TOPLEFT", 0, -25)
        row.hint:SetText(L[opt.hint])
        ns.Fit(row.hint, width - 150, 9)
    end
    if opt.type == "toggle" then
        local sw = CreateFrame("Button", nil, row)
        sw:SetSize(40, 22)
        sw:SetPoint("TOPRIGHT", 0, -4)
        sw.bg = ns.Round(sw, "circle", 11, C.cardBorder, "BACKGROUND")
        sw.knob = sw:CreateTexture(nil, "ARTWORK")
        sw.knob:SetTexture(ns.TEX .. "ulx-circle")
        sw.knob:SetSize(16, 16)
        sw:SetScript("OnClick", function()
            local on = Get(opt.path) and true or false
            if opt.invert then on = not on end
            on = not on
            if opt.invert then Set(opt.path, not on) else Set(opt.path, on) end
            Changed(opt)
        end)
        function row:Refresh()
            local on = Get(opt.path) and true or false
            if opt.invert then on = not on end
            sw.knob:ClearAllPoints()
            sw.knob:SetPoint(on and "RIGHT" or "LEFT", on and -3 or 3, 0)
            -- an: helle Spur mit Graphit-Knopf; aus: Linienfarbe mit gedämpftem Knopf (Akzent bleibt frei)
            local track, knob = on and C.text or C.cardBorder, on and TH.color.accentInk or C.text3
            sw.bg:SetColor(track[1], track[2], track[3], 1)
            sw.knob:SetVertexColor(knob[1], knob[2], knob[3], 1)
        end
        return row
    end
    -- step und cycle teilen sich das Bild "< Wert >"
    local value = ns.Label(row, 12, C.text, "OVERLAY", "Medium")
    value:SetJustifyH("CENTER")
    local function Move(dir)
        if opt.type == "step" then
            local v = (Get(opt.path) or opt.min) + dir * opt.step
            v = math.floor(v / opt.step + 0.5) * opt.step
            if v < opt.min then v = opt.min elseif v > opt.max then v = opt.max end
            Set(opt.path, v)
        else
            local values = type(opt.values) == "function" and opt.values() or opt.values
            local index = 1
            for i, entry in ipairs(values) do if entry[1] == Get(opt.path) then index = i end end
            index = index + dir
            if index < 1 then index = #values elseif index > #values then index = 1 end
            Set(opt.path, values[index][1])
        end
        Changed(opt)
    end
    local right = GlyphButton(row, opt.type == "step" and "plus" or "right", function() Move(1) end)
    right:SetPoint("TOPRIGHT", 0, -3)
    local left = GlyphButton(row, opt.type == "step" and "minus" or "left", function() Move(-1) end)
    left:SetPoint("RIGHT", right, "LEFT", -86, 0)
    value:SetPoint("LEFT", left, "RIGHT", 4, 0)
    value:SetPoint("RIGHT", right, "LEFT", -4, 0)
    function row:Refresh()
        if opt.type == "step" then
            value:SetText(Format(opt, Get(opt.path) or opt.min))
        else
            local values = type(opt.values) == "function" and opt.values() or opt.values
            local text = tostring(Get(opt.path))
            for _, entry in ipairs(values) do
                if entry[1] == Get(opt.path) then text = entry.raw and entry[2] or L[entry[2]] end
            end
            value:SetText(text)
        end
        ns.Fit(value, 78, 9)
    end
    return row
end

local function BuildPage(category)
    local width = WIDTH - SIDEBAR - 2 * 20
    local page = CreateFrame("Frame", nil, frame)
    page:SetPoint("TOPLEFT", SIDEBAR + 20, -HEADER - 8)
    page:SetSize(width, HEIGHT - HEADER - FOOTER - 16)
    page.rows = {}
    local y = 0
    for _, opt in ipairs(category.options) do
        local row = BuildRow(page, opt, width)
        row:SetPoint("TOPLEFT", 0, y)
        y = y - row.rowHeight
        page.rows[#page.rows + 1] = row
    end
    function page:Refresh()
        for _, row in ipairs(self.rows) do row:Refresh() end
    end
    page:Hide()
    return page
end

local function Select(key)
    for _, category in ipairs(CATEGORIES) do
        local page, button = pages[category.key], sideButtons[category.key]
        local on = category.key == key
        page:SetShown(on)
        button.hl:SetShown(on)
        button.mark:SetShown(on)
        button.text:SetTextColor(on and C.text[1] or C.text2[1], on and C.text[2] or C.text2[2], on and C.text[3] or C.text2[3])
        if on then
            current = page
            current.category = category
            page:Refresh()
        end
    end
    ns.db.optionsPage = key
end

-- Einstellungen einer Kategorie auf die Vorgaben zurücksetzen
local function ResetCategory(category)
    for _, opt in ipairs(category.options) do
        if opt.path then
            local value = Default(opt.path)
            if type(value) ~= "table" then Set(opt.path, value) end
            if opt.chosen then ns.db[opt.chosen] = nil end
        end
    end
    ns.ApplySettings()
end

local function Build()
    frame = CreateFrame("Frame", "UltimaOptions", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", 0, 20)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    ns.Round(frame, "shadow", 24, { 0, 0, 0, 0.6 }, "BACKGROUND", -2, 14)
    ns.Round(frame, "round", TH.radius.panel, C.panel, "BACKGROUND", 0)
    ns.Round(frame, "ring", TH.radius.panel, C.cardBorder, "BORDER")
    if UISpecialFrames then table.insert(UISpecialFrames, "UltimaOptions") end -- Escape schließt

    local logo = frame:CreateTexture(nil, "ARTWORK")
    logo:SetTexture(ns.TEX .. "ulx_logo-64")
    logo:SetSize(26, 26)
    logo:SetPoint("TOPLEFT", 16, -10)
    local title = ns.Label(frame, TH.size.display, C.text, "OVERLAY", "Bold")
    title:SetPoint("LEFT", logo, "RIGHT", 10, 0)
    title:SetText(ns.TITLE)
    local close = GlyphButton(frame, "kill", function() frame:Hide() end)
    close:SetTip(L["Close"])
    close:SetPoint("TOPRIGHT", -12, -10)

    -- Seitenleiste
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT", 10, -HEADER)
    side:SetSize(SIDEBAR - 10, HEIGHT - HEADER - 12)
    -- Seitenleiste ohne eigene Fläche, eine Haarlinie trennt sie von der Seite
    local sideRule = side:CreateTexture(nil, "BORDER")
    sideRule:SetTexture(ns.WHITE)
    sideRule:SetWidth(1)
    sideRule:SetPoint("TOPRIGHT", 0, 0)
    sideRule:SetPoint("BOTTOMRIGHT", 0, 0)
    sideRule:SetVertexColor(C.cardBorder[1], C.cardBorder[2], C.cardBorder[3], 1)
    for i, category in ipairs(CATEGORIES) do
        local b = CreateFrame("Button", nil, side)
        b:SetSize(SIDEBAR - 26, 28)
        b:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 30)
        -- gewählte Seite: erhöhte Fläche und die Glutmarke links (das "Jetzt" dieses Fensters)
        b.hl = ns.Round(b, "round", TH.radius.control, C.card, "BACKGROUND")
        b.hl:SetShown(false)
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetTexture(ns.WHITE)
        b.mark:SetSize(3, 14)
        b.mark:SetPoint("LEFT", 0, 0)
        b.mark:SetVertexColor(A1[1], A1[2], A1[3], 1)
        b.mark:Hide()
        b.text = ns.Label(b, TH.size.heading, C.text2, "OVERLAY", "Medium")
        b.text:SetPoint("LEFT", 10, 0)
        b.text:SetText(L[category.label])
        ns.Fit(b.text, SIDEBAR - 46, 10)
        b:SetScript("OnClick", function() Select(category.key) end)
        sideButtons[category.key] = b
        pages[category.key] = BuildPage(category)
    end

    -- Fußzeile
    local reset = TextButton(frame, L["Reset this page"], function()
        if current and current.category then
            ResetCategory(current.category)
            current:Refresh()
        end
    end)
    reset:SetPoint("BOTTOMRIGHT", -16, 12)
    local version = ns.Label(frame, 11, C.text3, "OVERLAY", "Light")
    version:SetPoint("BOTTOMLEFT", SIDEBAR + 20, 18)
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    version:SetText("v" .. tostring(getMeta and getMeta(ns.NAME, "Version") or "?"))
    frame:Hide()
end

function ns.ToggleOptions()
    if not frame then Build() end
    if frame:IsShown() then
        frame:Hide()
        return
    end
    frame:Show()
    Select(pages[ns.db.optionsPage] and ns.db.optionsPage or CATEGORIES[1].key)
end
