-- Eigene Anzeigetexte je Handlung in der Oberflächen-Sprache (ns.L), mit Namen aus dem Spiel.
-- Hinweistexte aus den Daten tragen Marken wie {enemy:Name}; Render() faerbt sie ein.
-- NPC-Namen aus den Daten sind englisch; ns.npcNames (Sprach-Addon) übersetzt sie in die Client-Sprache.
local _, ns = ...
local T = {}
ns.Text = T
local S = ns.State
local L = ns.L

-- NPC-Name in der Sprache des Clients (so wie er im Spiel über dem Kopf steht)
function ns.NPC(name)
    return ns.npcNames and ns.npcNames[name] or name
end

local MARK_COLOR = {
    enemy = "ff5f4a", friendly = "4ade80", loot = "38bdf8", pick = "d946ef", buy = "22c55e",
    warn = "facc15", quest = "fbbf24", item = "60a5fa",
}

-- {kind:Inhalt} -> farbiger Text, unbekannte Arten in Hinweisfarbe.
function T.Render(s)
    if not s then return nil end
    s = s:gsub("{(%l+):(.-)}", function(kind, inner)
        -- Personen-Marken tragen englische NPC-Namen, teils mit "::ID" am Ende
        if kind == "friendly" or kind == "enemy" then inner = ns.NPC((inner:gsub("::%d+$", ""))) end
        return "|cff" .. (MARK_COLOR[kind] or "cbd5e1") .. inner .. "|r"
    end)
    return s
end

local function Quest(a)
    local title = S.QuestTitle(a.q)
    -- Titel noch nicht im Cache: Name aus dem englischen Datentext ("Accept X", "Turn in X")
    if not title and a.t then
        local stripped, n = a.t:gsub("^Accept%s+", ""):gsub("^Turn%s+in%s+", "")
        if stripped ~= a.t or n > 0 then title = stripped end
    end
    return "|cff" .. MARK_COLOR.quest .. (title or ns.F("Quest %s", tostring(a.q))) .. "|r"
end

local function Names(list)
    if not list or #list == 0 then return "" end
    local out = {}
    for i, n in ipairs(list) do out[i] = ns.NPC(n) end
    return "|cff" .. MARK_COLOR.enemy .. table.concat(out, ", ") .. "|r"
end

local function Place(a)
    local name = S.MapName(a.m) or a.z
    if a.w or not a.x then return name or L["Waypoint"] end
    return ("%s %.0f, %.0f"):format(name or "", a.x, a.y)
end

-- Zielort einer Reise-Handlung: Kartenname aus der ID (Client-Sprache), sonst der Name aus den Daten
local function Destination(a)
    return (a.zm and S.MapName(a.zm)) or a.to or "?"
end

local function ItemLabel(i)
    return S.ItemName(i) or ns.F("Item %s", tostring(i))
end

-- Haupttext, Fortschritt (vorhanden, benoetigt) und Hinweis.
function T.Action(a)
    local tag = a[1]
    local hint = a.t and T.Render(a.t)
    if tag == "accept" then return ns.F("Accept: %s", Quest(a)), nil, nil, hint end
    if tag == "turnin" then return ns.F("Turn in: %s", Quest(a)), nil, nil, hint end
    if tag == "complete" then
        local _, text, have, need = S.Objective(a.q, a.o or 1)
        if text and text ~= "" then return text, have, need, hint end
        return hint or ns.F("Objective %d: %s", a.o or 1, Quest(a)), nil, nil, nil
    end
    if tag == "collect" then
        return ns.F("Collect: %s", "|cff" .. MARK_COLOR.item .. ItemLabel(a.i) .. "|r"), S.ItemCount(a.i), a.n, nil
    end
    if tag == "goto" then return ns.F("Go to %s", Place(a)), nil, nil, hint end
    if tag == "xp" then
        if a.away then return ns.F("Level %d until %d XP are left", a.lvl - 1, a.away), nil, nil, hint end
        if a.pct then return ns.F("Level %d at %d %%", a.lvl, math.floor(a.pct * 100)), nil, nil, hint end
        return ns.F("Reach level %d", a.lvl or 0), nil, nil, hint
    end
    if tag == "train" then
        return ns.F("Train: %s", S.SpellName(a.sp) or ns.F("Spell %s", tostring(a.sp))), nil, nil, hint
    end
    if tag == "hs" then return L["Use your Hearthstone"], nil, nil, hint end
    if tag == "home" then return L["Bind your Hearthstone here"], nil, nil, hint end
    if tag == "fly" then return ns.F("Fly to %s", a.to or "?"), nil, nil, hint end
    if tag == "fp" then return ns.F("Get the flight path: %s", a.to or "?"), nil, nil, hint end
    if tag == "zone" then return ns.F("Travel to %s", Destination(a)), nil, nil, hint end
    if tag == "subzone" then return ns.F("Travel to %s", S.AreaName(a.area) or "?"), nil, nil, hint end
    if tag == "abandon" then return ns.F("Abandon: %s", Quest(a)), nil, nil, hint end
    if tag == "vendor" then return hint or L["Vendor: empty your bags"], nil, nil, nil end
    if tag == "trainer" then return hint or L["Visit your class trainer"], nil, nil, nil end
    if tag == "use" or tag == "equip" then return hint or ns.F("Use: %s", ItemLabel(a.i)), nil, nil, nil end
    if tag == "mob" or tag == "unitscan" then return ns.F("Enemies: %s", Names(a.names)), nil, nil, hint end
    if tag == "target" then return ns.F("Talk to: %s", Names(a.names)), nil, nil, hint end
    return hint, nil, nil, nil
end
