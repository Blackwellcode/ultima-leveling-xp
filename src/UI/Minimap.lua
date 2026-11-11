-- Minimap-Symbol mit eigenem Logo. Links: Panel ein/aus. Rechts: Routenwahl. Umschalt-Links: Pfeil ein/aus.
local _, ns = ...
local ICON = "Interface\\AddOns\\" .. ns.NAME .. "\\Textures\\ulx-minimap-icon"

ns.On("READY", function()
    local ldb = LibStub("LibDataBroker-1.1", true)
    local icon = LibStub("LibDBIcon-1.0", true)
    if not (ldb and icon) then
        print(ns.WARN .. ns.L["Minimap library missing, use /ultima."])
        return
    end
    local launcher = ldb:NewDataObject(ns.NAME, {
        type = "launcher",
        text = "Ultima Leveling XP",
        icon = ICON,
        OnClick = function(_, button)
            if button == "RightButton" then
                ns.ToggleOptions()
            elseif IsShiftKeyDown() then
                ns.ToggleArrow()
            elseif button == "MiddleButton" then
                -- das Fenster trägt geschützte Knöpfe: im Kampf nicht ein- oder ausblenden
                if ns.panel and not ns.panel:IsShown() and not InCombatLockdown() then ns.panel:Show() end
                ns.ToggleRoutePicker()
            else
                ns.TogglePanel()
            end
        end,
        OnTooltipShow = function(tooltip)
            tooltip:AddLine("Ultima Leveling XP")
            local view = ns.view
            if view and view.route then tooltip:AddLine(view.route.n, 0.2, 0.84, 0.69) end
            tooltip:AddLine(ns.L["Left: window  ·  Right: options  ·  Shift: arrow"], 1, 1, 1)
        end,
    })
    icon:Register(ns.NAME, launcher, ns.db.minimap)
    function ns.ApplyMinimapButton()
        if ns.db.minimap.hide then icon:Hide(ns.NAME) else icon:Show(ns.NAME) end
    end
end)
