-- Bedingungen der Routendaten auswerten.
-- Grammatik: "/" trennt Alternativen (oder), Leerzeichen verbindet (und), "!" verneint,
-- Klammern gruppieren. Begriffe: Rasse, Klasse, Fraktion, Mindestlevel (Zahl), Spiel, Geschlecht.
-- Beispiel: "!NightElf !Hunter/!Dwarf !Hunter" = (kein Nachtelf und kein Jaeger) oder (kein Zwerg und kein Jaeger)
local _, ns = ...
local C = {}
ns.Cond = C

local cache, cacheKey = {}, nil

local function Token(entry, ctx)
    local level = tonumber(entry)
    if level then return ctx.level >= level end
    if entry == "Undead" then entry = "Scourge" end
    local upper = entry:upper()
    if upper == "DK" then upper = "DEATHKNIGHT" end
    if upper == "MALE" then return ctx.sex == 2 end
    if upper == "FEMALE" then return ctx.sex == 3 end
    return upper == ctx.class or entry == ctx.race or entry == ctx.faction or upper == ctx.game
        or entry == ctx.locale
end

local function Parse(text, ctx)
    -- %b() greift zusammengehörige Klammern, auch verschachtelte: "!(A/(B C))"
    text = text:gsub("(!?)(%b())", function(op, group)
        local v = Parse(group:sub(2, -2), ctx)
        if op == "!" then v = not v end
        return v and " __T " or " __F "
    end)
    for alternative in text:gmatch("[^/]+") do
        local ok, any = true, false
        for token in alternative:gmatch("!?[%w_]+") do
            any = true
            local negate = token:sub(1, 1) == "!"
            if negate then token = token:sub(2) end
            local v
            if token == "__T" then v = true elseif token == "__F" then v = false else v = Token(token, ctx) end
            if negate then v = not v end
            if not v then ok = false break end
        end
        if ok and any then return true end
    end
    return false
end

-- ctx: { race, class, faction, level, game, sex, locale }. Ohne Text gilt die Bedingung.
function C.Eval(text, ctx)
    if not text or text == "" then return true end
    ctx = ctx or ns.State.Player()
    local key = ctx.race .. ctx.class .. ctx.faction .. ctx.level
    if key ~= cacheKey then cache, cacheKey = {}, key end
    local v = cache[text]
    if v == nil then
        v = Parse(text, ctx)
        cache[text] = v
    end
    return v
end
