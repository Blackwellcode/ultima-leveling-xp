-- /ultima: Bedienung per Chat. Befehle auf Deutsch und Englisch (pfeil = arrow, ...).
local _, ns = ...
local R = ns.Runner
local L = ns.L

local ALIAS = {
    arrow = "pfeil", routes = "routen", border = "rahmen", hints = "tipps",
    language = "sprache", lang = "sprache", options = "optionen", config = "optionen", settings = "optionen",
    automation = "quests", talents = "talente",
}
-- Kurzformen für /ultima sprache
local LANG_SHORT = {
    de = "deDE", en = "enUS", fr = "frFR", es = "esES", it = "itIT", pt = "ptBR", ru = "ruRU",
    ko = "koKR", zh = "zhCN", cn = "zhCN", tw = "zhTW",
}

local function OnOff(value) return value and L["on"] or L["off"] end

local function SetLanguage(arg)
    if arg == "" then
        print(ns.PREFIX .. ns.F("Language: %s (setting: %s). Options: auto, %s", ns.LANG, ns.db.lang or "auto",
            table.concat(ns.LANGUAGES, ", ")))
        return
    end
    local code = arg == "auto" and "auto" or LANG_SHORT[arg]
    if not code then
        for _, c in ipairs(ns.LANGUAGES) do if c:lower() == arg then code = c end end
    end
    if not code then
        print(ns.WARN .. ns.F("Unknown language: %s", arg))
        return
    end
    -- Koreanisch und Chinesisch brauchen die Schrift eines Clients in dieser Sprache
    if ns.CJK[code] and not ns.CJK[ns.ClientLocale()] then
        print(ns.WARN .. L["Korean and Chinese need a game client in that language (font)."])
        return
    end
    ns.db.lang = code
    ns.db.langChosen = code ~= "auto" or nil -- eigene Wahl bleibt über Neustarts erhalten
    ns.ApplyLanguage()
    print(ns.PREFIX .. ns.F("Language: %s. Takes full effect after /reload.", ns.LANG))
    ns.RequestUpdate()
end

-- Eine Zeile Diagnose; schlägt eine Abfrage im Client fehl, steht der Fehler in der Zeile statt den Befehl abzubrechen
local function DebugLine(label, fn)
    local ok, result = pcall(fn)
    print(ns.PREFIX .. label .. ": " .. (ok and tostring(result) or ("Fehler/error: " .. tostring(result))))
end

local function Handle(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local cmd, arg = msg:match("^(%S*)%s*(.-)$")
    cmd = ALIAS[cmd] or cmd
    if cmd == "" then
        ns.TogglePanel()
    elseif cmd == "pfeil" then
        ns.ToggleArrow()
    elseif cmd == "routen" then
        ns.ToggleRoutePicker()
    elseif cmd == "auto" then
        local id = R.AutoSelect(true)
        print(ns.PREFIX .. (id and ns.F("Route: %s", R.Get(id).n) or L["No matching route found."]))
        -- Begründung der Wahl (technische Ausgabe): Routen im Levelbereich mit offenen Quests und Folge-Routen
        local player = ns.State.Player()
        for _, r in ipairs(R.Candidates(player, ns.db.routeKind or "route")) do
            if r.lo <= player.level and player.level <= r.hi then
                print("  " .. ns.F("%s: %d quests still open", r.n, R.OpenQuests(r, player)))
            end
        end
        ns.RequestUpdate()
    elseif cmd == "rahmen" then
        ns.db.questPlates.border = not ns.db.questPlates.border
        if ns.RefreshQuestPlates then ns.RefreshQuestPlates() end
        print(ns.PREFIX .. ns.F("Level border %s", OnOff(ns.db.questPlates.border)))
    elseif cmd == "tipps" then
        ns.db.hints = not ns.db.hints
        print(ns.PREFIX .. ns.F("Hints %s", OnOff(ns.db.hints)))
        ns.RequestUpdate()
    elseif cmd == "optionen" then
        ns.ToggleOptions()
    elseif cmd == "quests" then
        ns.db.autoQuest = not ns.db.autoQuest
        print(ns.PREFIX .. ns.F("Quest automation %s", OnOff(ns.db.autoQuest)))
    elseif cmd == "sprache" then
        SetLanguage(arg)
    elseif cmd == "talente" then
        for _, line in ipairs(ns.TalentReport()) do print(ns.PREFIX .. line) end
    elseif cmd == "reset" then
        ns.db.window.point, ns.db.arrow.point = nil, nil
        print(ns.PREFIX .. L["Positions reset, takes effect after /reload."])
    elseif cmd == "debug" then
        -- Zustand ausgewaehlter Texte, um unsichtbare Schrift im Spiel einzugrenzen (technische Ausgabe)
        print(ns.PREFIX .. "debug")
        DebugLine("lang", function()
            return ns.LANG .. ", client " .. ns.ClientLocale() .. ", routeText " .. tostring(ns.routeTextLocale or "-")
        end)
        DebugLine("auraIds", function()
            local ids = {}
            for key, id in pairs(ns.db.auraIds or {}) do ids[#ids + 1] = key .. "=" .. tostring(id) end
            return #ids > 0 and table.concat(ids, ", ") or "-"
        end)
        DebugLine("bags", function() return ns.Bonus.DebugBags() end)
        DebugLine("paths", function()
            return (ns.Paths.IsReady() and "ready" or "building") .. ", " .. tostring(ns.Paths.stats.nodes) .. " nodes, "
                .. tostring(ns.Paths.stats.edges) .. " edges, " .. tostring(ns.Paths.stats.links) .. " links"
        end)
        local p = ns.panel
        if not p then
            print(ns.WARN .. "panel missing")
            return
        end
        for _, entry in ipairs({ { "title", p.title }, { "tip", p.tip }, { "next", p.nextText }, { "xp", p.xpLeft } }) do
            local fs = entry[2]
            DebugLine(entry[1], function()
                local font, size = fs:GetFont()
                local r, g, b, a = fs:GetTextColor()
                return ("shown=%s visible=%s text=%d w=%.0f h=%.0f font=%s %s color=%.2f,%.2f,%.2f,%.2f"):format(
                    tostring((fs:IsShown())), tostring((fs:IsVisible())), #(fs:GetText() or ""), fs:GetStringWidth() or 0,
                    fs:GetStringHeight() or 0, tostring(font):match("[^\\/]+$") or "?", tostring(size),
                    r or 0, g or 0, b or 0, a or 0)
            end)
        end
    elseif cmd == "status" then
        local view = ns.view or {}
        print(ns.PREFIX .. ns.F("Route: %s, step: %s, routes loaded: %s", view.route and view.route.id or "-",
            tostring(view.main), tostring(ns.routes and #ns.routes or 0)))
        if ns.missingEvents and #ns.missingEvents > 0 then
            print(ns.PREFIX .. ns.F("Events missing in this client: %s", table.concat(ns.missingEvents, ", ")))
        end
        if ns.questieMissing then print(ns.PREFIX .. L["Questie is not loaded, quest markers stay off."]) end
        if ns.questieIncompatible then
            print(ns.PREFIX .. ns.F("This Questie version is not supported, quest markers stay off (%s).", ns.questieIncompatible))
        end
    else
        print(ns.PREFIX .. L["/ultima [options | arrow | routes | auto | quests | talents | border | hints | language | reset | status | debug]"])
    end
end

SLASH_ULTIMALEVELING1 = "/ultima"
SLASH_ULTIMALEVELING2 = "/ulx"
-- Fehler im Befehl erscheinen als Chatzeile. Ohne diese Klammer bricht WoW das Senden ab und der Text bleibt
-- im Eingabefeld stehen (BugSack verschluckt die Meldung).
SlashCmdList.ULTIMALEVELING = function(msg)
    local ok, err = pcall(Handle, msg)
    if not ok then print(ns.WARN .. "/ultima: " .. tostring(err)) end
end
