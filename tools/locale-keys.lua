-- Liefert alle Text-Schlüssel, die der Code benutzt: L["..."], ns.F("..."), dazu die Daten-Einträge des
-- Optionsfensters (label = "...", hint = "...", Auswahl-Texte { Wert, "Text" }) und die Namen der
-- Verkehrsmittel. Gemeinsame Quelle für tools/test-locale.lua und für die Pflege der Sprachdateien.
-- Aufruf direkt (lua tools/locale-keys.lua) listet Schlüssel, die in enUS fehlen.
local M = {}

function M.Used()
    local used, format = {}, {}
    local find = io.popen('find src -name "*.lua"')
    for path in find:lines() do
        if not path:find("Locale") then
            local fh = assert(io.open(path, "rb"))
            local s = fh:read("a")
            fh:close()
            for k in s:gmatch('L%["(.-)"%]') do used[k] = path end
            for k in s:gmatch('ns%.F%("(.-)"[,)]') do used[k] = path; format[k] = true end
            if path:find("Options.lua", 1, true) then
                for k in s:gmatch('label = "(.-)"') do used[k] = path end
                for k in s:gmatch('hint = "(.-)"') do used[k] = path end
                -- Auswahl-Texte: { "wert", "Text" } ohne raw-Kennzeichen
                for k in s:gmatch('{ "[%w]+", "([^"]+)" }') do used[k] = path end
            end
        end
    end
    find:close()
    for _, k in ipairs({ "Boat", "Zeppelin", "Tram" }) do used[k] = "Travel.lua (KIND_NAME)" end
    return used, format
end

if arg and arg[0] and arg[0]:find("locale%-keys") then
    local en = {}
    local ns = { RegisterLocale = function(code, t) if code == "enUS" then en = t end end }
    assert(loadfile("src/Locale/enUS.lua"))("x", ns)
    local list = {}
    for k in pairs(M.Used()) do if en[k] == nil then list[#list + 1] = k end end
    table.sort(list)
    for _, k in ipairs(list) do print(k) end
    io.stderr:write(#list .. " Schlüssel fehlen in enUS\n")
end

return M
