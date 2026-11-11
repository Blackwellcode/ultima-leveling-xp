-- Einstellungen anwenden: Größe (automatisch nach Auflösung oder von Hand), Deckkraft, Sichtbarkeit,
-- Sprache. Wird vom Optionsfenster nach jeder Änderung gerufen, beim Betreten der Welt und wenn sich
-- Auflösung oder UI-Skalierung ändern.
local _, ns = ...

local SCALE_MIN, SCALE_MAX = 0.6, 1.3
-- UI-Höhe, bei der Maßstab 1,00 passt. Das Fenster ist 384 Einheiten breit und soll etwa 27 % der
-- UI-Höhe einnehmen: 384 / 0,27 = 1420. (Mit 1080 war es auf 3440x1440 bei UI-Skalierung 0,65 zu groß.)
local REFERENCE_HEIGHT = 1420

-- Maßstab passend zur UI-Fläche: Das Fenster soll auf jedem Bildschirm etwa denselben Anteil der Höhe
-- einnehmen. UIParent:GetHeight() enthält Auflösung und UI-Skalierung des Spiels bereits.
function ns.AutoScale()
    local height = UIParent and UIParent:GetHeight()
    if not height or height <= 0 then return 1 end
    local scale = height / REFERENCE_HEIGHT
    if scale < SCALE_MIN then scale = SCALE_MIN elseif scale > SCALE_MAX then scale = SCALE_MAX end
    return math.floor(scale * 100 + 0.5) / 100
end

local pendingAfterCombat = false

-- resetPosition = true setzt Fenster und Pfeil an ihre Ausgangslage (Positionen wurden zuvor gelöscht).
function ns.ApplySettings(resetPosition)
    local db = ns.db
    if not db then return end
    if db.window.autoScale then db.window.scale = ns.AutoScale() end
    ns.ApplyLanguage()

    local panel = ns.panel
    if panel then
        if InCombatLockdown() then
            -- Größe und Lage des Fensters sind im Kampf gesperrt (geschützte Knöpfe): danach nachholen
            pendingAfterCombat = resetPosition and "reset" or (pendingAfterCombat or true)
        else
            panel:SetScale(db.window.scale)
            if resetPosition then
                panel:ClearAllPoints()
                panel:SetPoint("TOPRIGHT", UIParent, "RIGHT", -60, 280)
            end
        end
        if ns.ApplyPanelAlpha then ns.ApplyPanelAlpha() end
    end
    if ns.ApplyArrow then ns.ApplyArrow(resetPosition) end
    if ns.ApplyMinimapButton then ns.ApplyMinimapButton() end
    if ns.RefreshQuestPlates then ns.RefreshQuestPlates() end
    if ns.Nav and ns.Nav.Redraw then ns.Nav.Redraw() end
    if ns.RefreshTalents then ns.RefreshTalents() end
    if ns.RequestUpdate then ns.RequestUpdate() end
end

ns.On("READY", function()
    local frame = CreateFrame("Frame")
    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "DISPLAY_SIZE_CHANGED", "UI_SCALE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
        local ok = pcall(frame.RegisterEvent, frame, event)
        if not ok then
            ns.missingEvents = ns.missingEvents or {}
            ns.missingEvents[#ns.missingEvents + 1] = event
        end
    end
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" then
            if not pendingAfterCombat then return end
            local reset = pendingAfterCombat == "reset"
            pendingAfterCombat = false
            ns.Guard("Settings", ns.ApplySettings, reset)
        else
            ns.Guard("Settings", ns.ApplySettings)
        end
    end)
end)
