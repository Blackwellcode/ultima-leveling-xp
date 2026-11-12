-- Kit: gemeinsame Bausteine für scharfe Darstellung und lose Kopplung der Module.
--   Tokens - Farben, Schriften und Maße kommen aus Theme.lua (Hausstil Blackwellcode)
--   Einpassen - Texte bleiben in ihrer Breite (Fit), Schutz für Bild-Schleifen (Guard)
--   Schrift - Barlow aus dem eigenen media-Ordner, für Kyrillisch und CJK die Client-Schrift
local _, ns = ...
local U = ns
local TH = ns.Theme

local WHITE = "Interface\\Buttons\\WHITE8x8"
U.WHITE = WHITE
-- Kurznamen der Theme-Tokens für den Frame-Code. Genau ein Akzent (Glut): er markiert, was "jetzt" ist.
U.ACCENT = TH.color.accent
U.COLORS = {
    panel = TH.color.surface,
    card = TH.color.surface2,
    cardBorder = TH.color.rule,
    text = TH.color.ink,
    text2 = TH.color.ink2,
    text3 = TH.color.muted,
    ok = TH.color.good,
    warn = TH.color.warn,
    bad = TH.color.bad,
    -- Erholt-Anteil der XP: die Farbe des Spiels für Erholt, keine Hausfarbe
    rest = { 0.38, 0.65, 0.98 },
}

-- Farbe als Farbcode für Texte: U.Hex(U.ACCENT) -> "ff6a3d"
function U.Hex(c)
    return ("%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-------------------------------------------------------------------------------
-- Schrift
-------------------------------------------------------------------------------
-- Rollen statt Schnitte: "Bold" = Anzeige (Barlow Condensed SemiBold, Titel, Schrittsatz, Zahlen),
-- "Medium" und "Light" = Text (Barlow Medium). Barlow deckt nur Lateinisch ab: Russisch nutzt die
-- kyrillische Spielschrift, Koreanisch und Chinesisch die Client-Schrift.
local CYRILLIC = "Fonts\\FRIZQT___CYR.TTF"
function U.FontPath(weight)
    local client = ns.ClientLocale()
    if ns.CJK[client] or ns.CJK[ns.LANG] then return STANDARD_TEXT_FONT end
    if client == "ruRU" then return STANDARD_TEXT_FONT end
    if ns.LANG == "ruRU" then return CYRILLIC end
    if weight == "Bold" then return TH.font.display end
    return TH.font.body
end

-- Ganzzahlige Groessen und Schatten statt Outline bleiben auch klein gestochen scharf.
-- weight: "Light", "Medium" (Standard) oder "Bold". Schlaegt die Schrift fehl, gilt die Standardschrift.
local labels = {}

-- Schriften aller Textfelder erneut setzen und den Text neu zeichnen. Läuft beim Betreten der Welt und kurz
-- danach: dann sind die Schriftdateien sicher geladen. Sitzt die eigene Schrift auch dann nicht, gilt die
-- Standardschrift, und das wird einmal gemeldet.
function U.EnsureFonts()
    for _, l in ipairs(labels) do
        local fs = l.fs
        local size = fs.fitSize or l.size
        fs:SetFont(U.FontPath(l.weight), size, "")
        local font = fs:GetFont()
        if not font then
            fs:SetFont(STANDARD_TEXT_FONT, size, "")
            if not U.fontWarned then
                U.fontWarned = true
                print(ns.WARN .. ns.F("Font %s could not be loaded, using the default font.", U.FontPath(l.weight)))
            end
        end
        local text = fs:GetText()
        if text then
            fs:SetText("")
            fs:SetText(text)
        end
    end
end

function U.Label(parent, size, color, layer, weight)
    -- Vorlage der Spielschrift: das Feld hat damit immer eine gültige Schrift, auch wenn die eigene
    -- Schriftdatei beim Laden des Addons noch nicht bereit ist (Text ohne Schrift bleibt unsichtbar).
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", GameFontHighlightSmall and "GameFontHighlightSmall" or nil)
    size = math.floor(size + 0.5)
    fs:SetFont(U.FontPath(weight), size, "")
    labels[#labels + 1] = { fs = fs, weight = weight, size = size }
    fs.baseSize = size -- gewünschte Größe; GetFont kann anfangs noch die kleinere Vorlagen-Größe melden
    -- Flache Schrift auf deckender Graphitfläche: kein Schatten (die Spielvorlage bringt einen mit)
    fs:SetShadowOffset(0, 0)
    local c = color or U.COLORS.text
    fs:SetTextColor(c[1], c[2], c[3], c[4] or 1)
    fs:SetJustifyH("LEFT")
    return fs
end

-------------------------------------------------------------------------------
-- Geschützte Werte ("secret values"): Der Forever-Client liefert manche Werte im Kampf geschützt aus
-- (z. B. GetUnitSpeed). Ein Addon darf sie nicht vergleichen oder verrechnen, sonst Lua-Fehler.
-------------------------------------------------------------------------------
function U.IsSecret(v)
    if type(v) == "table" then return issecrettable ~= nil and issecrettable(v) == true end
    return issecretvalue ~= nil and issecretvalue(v) == true
end

-- Sind Buff-Daten gerade geschützt (im Kampf)? Dann darf niemand Dauer oder Stapel lesen.
function U.AurasSecret()
    return C_Secrets ~= nil and C_Secrets.ShouldAurasBeSecret ~= nil and C_Secrets.ShouldAurasBeSecret() == true
end

-- Laufgeschwindigkeit in Yards/Sekunde für Zeitangaben. Geschützt oder Stillstand: zuletzt gemessene
-- Laufgeschwindigkeit (Start: 7, normales Laufen).
local lastSpeed = 7
function U.RunSpeed()
    local speed = GetUnitSpeed("player")
    -- erst auf Schutz pruefen: auch ein Vergleich mit nil ist bei geschuetzten Werten nicht sicher
    if U.IsSecret(speed) or speed == nil then return lastSpeed end
    if speed >= 1 then lastSpeed = speed end
    return lastSpeed
end

-- Schutz für Bild-Schleifen (OnUpdate): Ein Fehler erscheint einmal je Meldung im Chat und bricht die
-- Schleife nicht ab; ohne Schutz feuert er jedes Bild neu (Hunderte Meldungen) und das Fenster bleibt halb leer.
local reported = {}
function U.Guard(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        local key = label .. tostring(err)
        if not reported[key] then
            reported[key] = true
            print(ns.WARN .. label .. ": " .. tostring(err))
        end
    end
    return ok
end

-- Zeit als "m:ss", ab einer Stunde "h:mm h"
function U.Clock(seconds)
    local s = math.floor(seconds + 0.5)
    if s >= 3600 then return ("%d:%02d h"):format(math.floor(s / 3600), math.floor((s % 3600) / 60)) end
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Yards als Meter oder Kilometer
function U.Meters(yards)
    local m = yards * 0.9144
    if m >= 1000 then return ("%.1f km"):format(m / 1000) end
    return ("%d m"):format(math.floor(m))
end

-- Breite des Textes ohne Begrenzung durch die Breite des Feldes
local function TextWidth(fs)
    if fs.GetUnboundedStringWidth then return fs:GetUnboundedStringWidth() or 0 end
    return fs:GetStringWidth() or 0
end
U.TextWidth = TextWidth

-- Einpassen: Text bleibt in width. Erst wird die Schrift bis minSize verkleinert, reicht das nicht,
-- kürzt WoW das Ende mit "…" (feste Breite, kein Umbruch). Nach jedem SetText aufrufen.
-- So überlappt in keiner Sprache ein Text das nächste Element.
-- Mehrere eingepasste Felder auf die kleinste gemeinsame Schriftgröße bringen (nach U.Fit aufrufen).
function U.FitSame(list)
    local size
    for _, fs in ipairs(list) do
        if fs.fitSize and (not size or fs.fitSize < size) then size = fs.fitSize end
    end
    if not size then return end
    for _, fs in ipairs(list) do
        if fs.fitSize ~= size then
            local font, _, flags = fs:GetFont()
            if font then
                fs:SetFont(font, size, flags or "")
                fs.fitSize = size
            end
        end
    end
end

function U.Fit(fs, width, minSize)
    local font, size, flags = fs:GetFont()
    if not font then return end
    fs.fitBase = fs.baseSize or fs.fitBase or size
    fs:SetWidth(width)
    fs:SetWordWrap(false)
    local target = fs.fitBase
    if size ~= target then fs:SetFont(font, target, flags or "") end
    local floor = minSize or 9
    while TextWidth(fs) > width and target > floor do
        target = target - 1
        fs:SetFont(font, target, flags or "")
    end
    fs.fitSize = target
end

-------------------------------------------------------------------------------
-- Rundungen: 9 Teile aus einer Textur (Ecken fest, Kanten und Mitte gedehnt)
-------------------------------------------------------------------------------
local TEX = "Interface\\AddOns\\UltimaLevelingXP\\Textures\\"
U.TEX = TEX
local SLICES = {
    -- Anker, Gegenanker, Texturkoordinaten (l, r, t, b) als Anteil der Ecke f
    { "TOPLEFT", "TOPLEFT", 0, "f", 0, "f" }, { "TOPRIGHT", "TOPRIGHT", "1f", 1, 0, "f" },
    { "BOTTOMLEFT", "BOTTOMLEFT", 0, "f", "1f", 1 }, { "BOTTOMRIGHT", "BOTTOMRIGHT", "1f", 1, "1f", 1 },
}
local function coord(v, f)
    if v == "f" then return f elseif v == "1f" then return 1 - f end
    return v
end

-- Erzeugt eine abgerundete Flaeche. texture: "round" (Radius 25 %), "ring", "circle" (Pille), "shadow".
-- corner: Eckgroesse in UI-Einheiten. out: Auslauf nach aussen (für Schatten).
-- Liefert ein Objekt mit :SetColor(r, g, b, a) und :SetShown(bool).
function U.Round(frame, texture, corner, color, layer, sub, out)
    local path = TEX .. "ulx-" .. texture
    local f = (texture == "circle") and 0.5 or (texture == "shadow" and 0.375 or 0.25)
    out = out or 0
    local parts = {}
    local function tex()
        local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sub or 0)
        t:SetTexture(path)
        parts[#parts + 1] = t
        return t
    end
    local c = corner
    local corners = {}
    for i, s in ipairs(SLICES) do
        local t = tex()
        t:SetSize(c, c)
        local ox = (s[1]:find("LEFT") and -out or out)
        local oy = (s[1]:find("TOP") and out or -out)
        t:SetPoint(s[1], frame, s[2], ox, oy)
        t:SetTexCoord(coord(s[3], f), coord(s[4], f), coord(s[5], f), coord(s[6], f))
        corners[i] = t
    end
    local tl, tr, bl, br = corners[1], corners[2], corners[3], corners[4]
    local top = tex(); top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    top:SetTexCoord(f, 1 - f, 0, f)
    local bottom = tex(); bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    bottom:SetTexCoord(f, 1 - f, 1 - f, 1)
    local left = tex(); left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    left:SetTexCoord(0, f, f, 1 - f)
    local right = tex(); right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    right:SetTexCoord(1 - f, 1, f, 1 - f)
    local mid = tex(); mid:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); mid:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    mid:SetTexCoord(f, 1 - f, f, 1 - f)

    local obj = { parts = parts }
    function obj:SetColor(r, g, b, a) for _, t in ipairs(parts) do t:SetVertexColor(r, g, b, a or 1) end end
    function obj:SetShown(v) for _, t in ipairs(parts) do t:SetShown(v) end end
    if color then obj:SetColor(color[1], color[2], color[3], color[4] or 1) end
    return obj
end

-- Einfache Einblendung (Alpha 0 -> 1) für einen Frame; liefert eine Funktion zum Abspielen.
function U.FadeIn(frame, duration)
    local group = frame:CreateAnimationGroup()
    local a = group:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(duration or TH.motion.base)
    a:SetSmoothing("IN_OUT")
    return function() group:Stop(); group:Play() end
end

-- Icons aus dem 128-px-Paket ohne den eingebrannten Rand.
function U.Icon(parent, size, layer)
    local t = parent:CreateTexture(nil, layer or "ARTWORK")
    t:SetSize(size, size)
    t:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    return t
end

-------------------------------------------------------------------------------
-- Knöpfe des Hauses (Hausstil 1.2.0): jeder Knopf ist eine sichtbare Kachel mit Fläche, Haarlinien-Rand
-- und Zuständen aus einer Tabelle. Ein System für Panel, Willkommensfenster, Optionen und Talentkarte.
--   U.IconButton(parent, glyph, size)          Symbol-Knopf; b:SetTip(name, zweck), b:SetActive(on)
--   U.TextButton(parent, text, variant, glyph) "primary" (helle Fläche) oder "secondary" (Kachel)
-------------------------------------------------------------------------------
local function Tint(region, c, a)
    if region.SetTextColor then region:SetTextColor(c[1], c[2], c[3], a or 1) else region:SetVertexColor(c[1], c[2], c[3], a or 1) end
end

-- Zustände: Ruhe, darüber, gedrückt; Inhalt (Glyphe, Text) rückt beim Drücken 1 px nach unten
local function Wire(b, fills, content)
    local over, down = false, false
    local function Refresh()
        local fill = down and fills.press or (over and fills.hover or fills.rest)
        b.bg:SetColor(fill[1], fill[2], fill[3], fill[4] or 1)
        for _, part in ipairs(content) do
            Tint(part.region, over and part.over or part.rest, b.dim)
            part.region:ClearAllPoints()
            part.region:SetPoint(part.point, b, part.point, part.x, part.y - (down and 1 or 0))
        end
    end
    b.Refresh = Refresh
    b:SetScript("OnMouseDown", function() down = true; Refresh() end)
    b:SetScript("OnMouseUp", function() down = false; Refresh() end)
    b:SetScript("OnEnter", function(self)
        over = true
        Refresh()
        if self.tipName then
            GameTooltip:SetOwner(self, self.tipAnchor or "ANCHOR_TOP")
            GameTooltip:SetText(self.tipName, 1, 1, 1, 1, true)
            if self.tipText then
                local c = U.COLORS.text2
                GameTooltip:AddLine(self.tipText, c[1], c[2], c[3], true)
            end
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function()
        over, down = false, false
        Refresh()
        if GameTooltip_Hide then GameTooltip_Hide() end
    end)
    function b:SetTip(name, text, anchor) self.tipName, self.tipText, self.tipAnchor = name, text, anchor end
    function b:SetDisabled(off)
        self.dim = off and 0.4 or 1
        self:SetAlpha(off and 0.4 or 1)
        self:EnableMouse(not off)
        Refresh()
    end
    b.dim = 1
    Refresh()
end

function U.IconButton(parent, glyph, size)
    size = size or 30
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size, size)
    b.bg = U.Round(b, "round", TH.radius.control, TH.color.control, "BACKGROUND")
    b.ring = U.Round(b, "ring", TH.radius.control, U.COLORS.cardBorder, "BORDER")
    b.glyph = b:CreateTexture(nil, "ARTWORK")
    b.glyph:SetTexture(TEX .. "ulx-glyph-" .. glyph)
    local g = math.floor(size * 0.55 + 0.5)
    b.glyph:SetSize(g, g)
    -- an: kurzer heller Balken unter der Glyphe
    b.on = b:CreateTexture(nil, "OVERLAY")
    b.on:SetTexture(WHITE)
    b.on:SetSize(10, 2)
    b.on:SetPoint("BOTTOM", 0, 3)
    Tint(b.on, U.COLORS.text)
    b.on:Hide()
    Wire(b, { rest = TH.color.control, hover = TH.color.controlHover, press = TH.color.controlPress },
        { { region = b.glyph, point = "CENTER", x = 0, y = 0, rest = U.COLORS.text2, over = U.COLORS.text } })
    function b:SetGlyph(name) self.glyph:SetTexture(TEX .. "ulx-glyph-" .. name) end
    function b:SetActive(on) self.on:SetShown(on and true or false) end
    return b
end

function U.TextButton(parent, text, variant, glyph, glyphAfter)
    local primary = variant == "primary"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(32)
    local rest = primary and U.COLORS.text or TH.color.control
    local hover = primary and U.COLORS.text2 or TH.color.controlHover
    local press = primary and TH.color.muted or TH.color.controlPress
    b.bg = U.Round(b, "round", TH.radius.control, rest, "BACKGROUND")
    if not primary then b.ring = U.Round(b, "ring", TH.radius.control, U.COLORS.cardBorder, "BORDER") end
    local ink = primary and TH.color.accentInk or U.COLORS.text
    b.label = U.Label(b, TH.size.heading, ink, "OVERLAY", "Bold")
    b.label:SetJustifyH("CENTER")
    local content = { { region = b.label, point = "CENTER", x = 0, y = 0, rest = ink, over = ink } }
    if glyph then
        b.glyph = b:CreateTexture(nil, "ARTWORK")
        b.glyph:SetTexture(TEX .. "ulx-glyph-" .. glyph)
        b.glyph:SetSize(14, 14)
        content[#content + 1] = { region = b.glyph, point = glyphAfter and "RIGHT" or "LEFT", x = glyphAfter and -12 or 12, y = 0,
            rest = ink, over = ink }
    end
    function b:SetLabel(value)
        self.label:SetText(value)
        local w = TextWidth(self.label) + 32 + (glyph and 20 or 0)
        self:SetWidth(math.max(96, math.floor(w + 0.5)))
        -- Text mittig im Raum neben der Glyphe
        content[1].x = glyph and (glyphAfter and -10 or 10) or 0
        if self.Refresh then self.Refresh() end
    end
    Wire(b, { rest = rest, hover = hover, press = press }, content)
    b:SetLabel(text)
    return b
end

