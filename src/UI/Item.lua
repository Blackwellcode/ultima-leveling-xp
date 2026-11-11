-- Item-Knopf: Verlangt der aktuelle Schritt, einen Gegenstand zu benutzen (Quest-Item), zeigt Ultima ihn
-- als Knopf links oben neben dem Fenster. Ein Klick benutzt ihn. Der Knopf ist geschützt
-- (SecureActionButton): Inhalt und Sichtbarkeit ändern sich nur außerhalb des Kampfes.
local _, ns = ...
local R, P, S = ns.Runner, ns.Progress, ns.State

local button, shownItem, wantedItem

-- Erster Gegenstand zum Benutzen in den angezeigten Schritten, der in den Taschen liegt
local function StepItem(view)
    if not (view and view.route) then return nil end
    local player = S.Player()
    for _, ref in ipairs(R.Shown(view, false)) do
        for _, entry in ipairs(P.Actions(ref.route.s[ref.si], player)) do
            local a = entry.a
            if a[1] == "use" and a.i and S.ItemCount(a.i) > 0 then return a.i end
        end
    end
    return nil
end

local function Apply()
    if not button or InCombatLockdown() then return end -- im Kampf gesperrt, wird danach nachgeholt
    if wantedItem == shownItem then return end
    shownItem = wantedItem
    if shownItem then
        button:SetAttribute("type", "item")
        button:SetAttribute("item", "item:" .. shownItem)
        local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(shownItem)
        button.icon:SetTexture(icon or "Interface/Icons/INV_Misc_Gear_01")
        button:Show()
    else
        button:SetAttribute("type", nil)
        button:SetAttribute("item", nil)
        button:Hide()
    end
end

local function Build()
    if not ns.panel then return end
    button = CreateFrame("Button", "UltimaItemButton", ns.panel, "SecureActionButtonTemplate")
    button:SetSize(40, 40)
    button:SetPoint("TOPRIGHT", ns.panel, "TOPLEFT", -8, -16)
    button:RegisterForClicks("AnyUp", "AnyDown")
    ns.Round(button, "round", 10, { 0.055, 0.059, 0.071, 0.92 }, "BACKGROUND")
    ns.Round(button, "ring", 10, { ns.ACCENT[1], ns.ACCENT[2], ns.ACCENT[3], 0.6 }, "BORDER")
    button.icon = ns.Icon(button, 28)
    button.icon:SetPoint("CENTER")
    button:SetScript("OnEnter", function(self)
        if not shownItem then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.F("Use: %s", S.ItemName(shownItem) or ns.F("Item %s", tostring(shownItem))), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    button:Hide()
    -- Nach dem Kampf nachholen, was im Kampf nicht geändert werden durfte
    button:RegisterEvent("PLAYER_REGEN_ENABLED")
    button:SetScript("OnEvent", function() ns.Guard("Item", Apply) end)
end

ns.On("READY", Build)
ns.On("VIEW", function(view)
    wantedItem = ns.db.buttons.item and StepItem(view) or nil
    ns.Guard("Item", Apply)
end)
