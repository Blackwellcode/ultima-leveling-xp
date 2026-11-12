-- Masterwork 1.0.0 · house: blackwellcode 1.2.0 · signature: the route rail with the ember step
-- critique: pending the in-game screenshot review
-- Alle Farben, Schriften, Größen und Medienpfade des Addons stehen hier. Frame-Code nennt nur Tokens.
local addonName, ns = ...
local T = {}
ns.Theme = T

local MEDIA = "Interface\\AddOns\\" .. addonName .. "\\media\\"

local function hex(h, a)
    return { tonumber(string.sub(h, 1, 2), 16) / 255, tonumber(string.sub(h, 3, 4), 16) / 255,
        tonumber(string.sub(h, 5, 6), 16) / 255, a or 1 }
end

T.color = {
    surface = hex("16171A", 0.97),
    surface2 = hex("1E2024", 1),
    ink = hex("ECEBE6", 1),
    ink2 = hex("C9C8C2", 1),
    muted = hex("9B9EA6", 1),
    rule = hex("26282D", 1),
    accent = hex("FF6A3D", 1),
    accentInk = hex("16171A", 1),
    good = hex("8FD18A", 1),
    warn = hex("FFC24A", 1),
    bad = hex("FF5A4E", 1),
    -- Knöpfe als sichtbare Kacheln (Hausstil 1.2.0): Ruhe, darüber, gedrückt
    control = hex("2A2D33", 1),
    controlHover = hex("353840", 1),
    controlPress = hex("1A1B1F", 1),
    -- Texturen ohne Einfärbung (eigene Farben eines Bildes) und Lichtkanten
    neutral = hex("FFFFFF", 1),
}

T.font = {
    display = MEDIA .. "BarlowCondensed-SemiBold.ttf",
    body = MEDIA .. "Barlow-Medium.ttf",
    numbers = MEDIA .. "BarlowCondensed-SemiBold.ttf",
}

T.size = { display = 22, heading = 16, body = 15, small = 13, figure = 26, step = 4 }
T.radius = { panel = 4, control = 3 }
T.alpha = { panel = 0.97, combat = 0.6 }
T.motion = { fast = 0.15, base = 0.25, slow = 0.35 }

T.media = MEDIA
