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
        text = ns.TITLE,
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
            tooltip:AddLine(ns.TITLE)
            local view = ns.view
            if view and view.route then tooltip:AddLine(view.route.n, ns.COLORS.text[1], ns.COLORS.text[2], ns.COLORS.text[3]) end
            local muted = ns.COLORS.text3
            for _, line in ipairs({ ns.L["Left: window"], ns.L["Right: options"], ns.L["Shift: arrow"] }) do
                tooltip:AddLine(line, muted[1], muted[2], muted[3])
            end
        end,
    })
    icon:Register(ns.NAME, launcher, ns.db.minimap)
    function ns.ApplyMinimapButton()
        if ns.db.minimap.hide then icon:Hide(ns.NAME) else icon:Show(ns.NAME) end
    end
end)
