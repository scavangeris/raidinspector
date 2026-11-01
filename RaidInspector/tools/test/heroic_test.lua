-- [H]/[N] tag after item names: tooltip-based heroic detection, caching,
-- quality gate, uncached handling, and rendering that survives truncation.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

-- A hidden tooltip whose lines come from a per-item script.
local tooltipScripts = {}   -- itemId -> { "Name", "Heroic", ... }
local hyperlinks = {}
local tip = CreateFrame("GameTooltip", "RaidInspectorHeroicScanTooltip")
tip.SetHyperlink = function(self, link)
    table.insert(hyperlinks, link)
    local id = tonumber(link:match("item:(%d+)"))
    local lines = tooltipScripts[id] or {}
    self.__lines = #lines
    for i = 1, 6 do
        local fs = _G["RaidInspectorHeroicScanTooltipTextLeft" .. i] or CreateFrame("Frame", "RaidInspectorHeroicScanTooltipTextLeft" .. i)
        fs.text = lines[i]
    end
end
tip.NumLines = function(self) return self.__lines or 0 end
addon.heroicScanTooltip = tip

local cacheRequests = {}
addon.RequestItemCache = function(self, id) table.insert(cacheRequests, id) end

-- Heroic and normal Legguards of Lost Hope, a crafted epic, a blue, an unseen item.
_G.__itemInfo[50867] = { name = "Legguards of Lost Hope", quality = 4 }   -- heroic id
tooltipScripts[50867] = { "Legguards of Lost Hope", "Heroic", "Binds when picked up" }
_G.__itemInfo[50645] = { name = "Leggings of Northern Lights", quality = 4 }
tooltipScripts[50645] = { "Leggings of Northern Lights", "Binds when picked up", "Legs" }
_G.__itemInfo[49907] = { name = "Deathfrost Boots", quality = 4 }
tooltipScripts[49907] = { "Deathfrost Boots", "Binds when equipped", "Equip: heroic stuff" }
_G.__itemInfo[40000] = { name = "Some Blue", quality = 3 }
tooltipScripts[40000] = { "Some Blue", "Heroic" }

-- 1. Detection --------------------------------------------------------------------
check("heroic item detected", addon:IsHeroicItemId(50867) == true)
check("normal item detected", addon:IsHeroicItemId(50645) == false)
check("'heroic' further down the tooltip does not count", addon:IsHeroicItemId(49907) == false)
hyperlinks = {}
check("result is cached", addon:IsHeroicItemId(50867) == true and #hyperlinks == 0, #hyperlinks)

-- Uncached item: unknown, requested, not cached as false.
check("uncached item is unknown (nil)", addon:IsHeroicItemId(51999) == nil)
check("uncached item is requested for caching", cacheRequests[1] == 51999, cacheRequests[1])
check("unknown is not stored as normal", addon.heroicItemCache[51999] == nil)
_G.__itemInfo[51999] = { name = "Late Item", quality = 4 }
tooltipScripts[51999] = { "Late Item", "Heroic" }
check("once cached, it resolves", addon:IsHeroicItemId(51999) == true)

-- Empty tooltip (data not there yet) is not cached either.
_G.__itemInfo[52000] = { name = "Racey", quality = 4 }
check("empty tooltip -> unknown", addon:IsHeroicItemId(52000) == nil and addon.heroicItemCache[52000] == nil)

-- 2. Tag ----------------------------------------------------------------------------
check("[H] tag for heroic epic", (addon:GetItemDifficultyTag({ itemId = 50867, quality = 4 }) or ""):find("[H]", 1, true) ~= nil)
check("[N] tag for normal epic", (addon:GetItemDifficultyTag({ itemId = 50645, quality = 4 }) or ""):find("[N]", 1, true) ~= nil)
check("no tag below epic quality", addon:GetItemDifficultyTag({ itemId = 40000, quality = 3 }) == nil)
check("quality falls back to GetItemInfo", (addon:GetItemDifficultyTag({ itemId = 50867 }) or ""):find("[H]", 1, true) ~= nil)
check("no tag without an item id", addon:GetItemDifficultyTag({ name = "x" }) == nil)
check("no tag while unknown", addon:GetItemDifficultyTag({ itemId = 52000, quality = 4 }) == nil)

-- 3. Columns + rendering --------------------------------------------------------------
local cols = addon:BuildSlotColumns("legs", { itemId = 50867, quality = 4, name = "Legguards of Lost Hope", ilvl = 277 })
check("columns carry the tag separately from the name", cols.name == "Legguards of Lost Hope" and (cols.nameTag or ""):find("[H]", 1, true) ~= nil)

local built = pcall(function() addon:ToggleWindow(true) end)
check("window builds", built and addon.ui and addon.ui.detailRows)
local entry = {
    key = "x-testrealm", state = "ready",
    req = { name = "X", realm = "TestRealm", key = "x-testrealm", status = "ready" },
    result = { gearScore = 6000, class = "DRUID", spec = "Balance", level = 80, issueSummary = {},
        items = {
            { slot = "legs", itemId = 50867, quality = 4, name = "Legguards of Lost Hope", ilvl = 277 },
            { slot = "feet", itemId = 50645, quality = 4, name = "Leggings of Northern Lights", ilvl = 264 },
        } },
}
addon:RefreshDetailPanel(entry)
local found = {}
for _, row in ipairs(addon.ui.detailRows) do
    local fs = row.colFS and row.colFS.name
    local t = fs and fs:GetText() or ""
    if t:find("Legguards", 1, true) then found.h = t end
    if t:find("Northern", 1, true) then found.n = t end
end
check("rendered heroic row ends with [H]", (found.h or ""):find("Legguards of Lost Hope |cff%x+%[H%]|r$") ~= nil, found.h)
check("rendered normal row ends with [N]", (found.n or ""):find("%[N%]|r$") ~= nil, found.n)

finish()
