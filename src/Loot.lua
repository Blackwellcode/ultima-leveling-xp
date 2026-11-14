-- Fast Loot: Ist automatisches Plündern aktiv (Spieleinstellung oder die Taste dafür), nimmt Ultima beim
-- Öffnen der Beute sofort alle Plätze auf, statt das Spiel sie nacheinander abarbeiten zu lassen. Ohne
-- automatisches Plündern bleibt das Beutefenster unberührt. Abschaltbar: ns.db.fastLoot.
local _, ns = ...

local GAP = 0.3 -- Sekunden: dieselbe Beute meldet das Spiel manchmal zweimal kurz nacheinander
local last = 0

-- Plündert das Spiel gerade automatisch? Das Ereignis sagt es; fehlt die Angabe, Einstellung und Taste
-- (die Taste kehrt die Einstellung um).
local function AutoLooting(autoLoot)
    if autoLoot ~= nil then return autoLoot == true end
    local setting = GetCVarBool and GetCVarBool("autoLootDefault") or false
    local toggled = IsModifiedClick and IsModifiedClick("AUTOLOOTTOGGLE") or false
    return setting ~= toggled
end

local function OnLootReady(autoLoot)
    if not (ns.db and ns.db.fastLoot) then return end
    if not AutoLooting(autoLoot) then return end
    local now = GetTime()
    if now - last < GAP then return end
    last = now
    -- von hinten nach vorn: aufgenommene Plätze verschieben die übrigen nicht
    for i = GetNumLootItems(), 1, -1 do
        local locked = select(6, GetLootSlotInfo(i))
        if not locked then LootSlot(i) end
    end
end

ns.On("READY", function()
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("LOOT_READY")
    frame:SetScript("OnEvent", function(_, _, autoLoot) ns.Guard("Fast Loot", OnLootReady, autoLoot) end)
end)
