-- BIS LIST tab: data, tab switching, selection persistence, row rendering,
-- the AtlasLoot bridge (index, source labels, name resolution, fallback),
-- tooltips, right-click and shift-click, the /ri bis command, and graceful
-- degradation without AtlasLoot.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

-- 1. Generated data ------------------------------------------------------------
local specs = addon:GetBiSSpecs()
check("27 specs loaded from RaidInspector_BiS.lua", #specs == 27, #specs)
check("first spec is Blood DK Tank (class order, workbook order)", specs[1] and specs[1].key == "blood-dk-tank", specs[1] and specs[1].key)
check("first spec head item is Broken Ram Skull Helm 50640",
    specs[1] and specs[1].items[1].slot == "Head" and specs[1].items[1].id == 50640)
local total, withId = 0, 0
local s, it
for _, s in ipairs(specs) do
    for _, it in ipairs(s.items) do
        total = total + 1
        if it.id then withId = withId + 1 end
    end
end
check("452 best-in-slot items", total == 452, total)
check("only the two linkless workbook entries lack ids", total - withId == 2, total - withId)
check("every spec has a class token", (function()
    for _, s in ipairs(specs) do if not s.class or s.class == "" then return false end end
    return true
end)())

-- 2. Window + tab switching -------------------------------------------------------
local built, buildErr = pcall(function() addon:ToggleWindow(true) end)
check("main window builds with the BIS panel", built and addon.ui and addon.ui.bisPanel ~= nil, buildErr)
check("BIS tab button exists", addon.ui.bisTabButton ~= nil)
check("18 list rows built", addon.ui.bisRows and #addon.ui.bisRows == 18)

check("SetActiveTab accepts bis", addon:SetActiveTab("bis") == true)
check("GetActiveTab returns bis", addon:GetActiveTab() == "bis")
addon:RefreshMainWindow()
check("BIS panel shown on its tab", addon.ui.bisPanel:IsShown())
check("LFM panel hidden on the BIS tab", not addon.ui.lfmPanel:IsShown())
check("BIS tab button highlighted", (addon.ui.bisTabButton:GetText() or ""):find("66ff66", 1, true) ~= nil)
check("subtitle describes the BIS tab", (addon.ui.subtitle:GetText() or ""):find("Best%-in%-slot") ~= nil)
check("status line names the spec", (addon.ui.statusText:GetText() or ""):find("Blood DK Tank", 1, true) ~= nil,
    addon.ui.statusText:GetText())

addon:SetActiveTab("lfm")
addon:RefreshMainWindow()
check("LFM tab shows the LFM panel", addon.ui.lfmPanel:IsShown())
check("LFM tab hides the BIS panel", not addon.ui.bisPanel:IsShown())
addon:SetActiveTab("inspector")
addon:RefreshMainWindow()
check("Inspector tab hides both", not addon.ui.bisPanel:IsShown() and not addon.ui.lfmPanel:IsShown())
addon:SetActiveTab("bis")
addon:RefreshMainWindow()

-- 3. Selection ------------------------------------------------------------------
check("default selection is the first spec", addon:GetSelectedBiSSpec().key == "blood-dk-tank")
check("unknown spec key is rejected", addon:SetSelectedBiSSpec("nope") == false)
check("selection unchanged after a bad key", addon:GetSelectedBiSSpec().key == "blood-dk-tank")
check("select Fury Warrior", addon:SetSelectedBiSSpec("fury-warrior") == true)
check("selection persisted in the DB", _G.RaidInspectorDB.state.ui.bisSpec == "fury-warrior")
check("dropdown text shows class and spec",
    (addon.ui.bisSpecDropDown.__text or ""):find("Warrior", 1, true) ~= nil and (addon.ui.bisSpecDropDown.__text or ""):find("Fury", 1, true) ~= nil,
    addon.ui.bisSpecDropDown.__text)

-- 4. Rows -----------------------------------------------------------------------
addon:SetSelectedBiSSpec("blood-dk-tank")
local rows = addon.ui.bisRows
check("row 1 slot is Head", rows[1].slotText:GetText() == "Head", rows[1].slotText:GetText())
check("row 1 ilvl 277", rows[1].ilvlText:GetText() == "277")
check("row 1 button carries the item", rows[1].bisButton.item and rows[1].bisButton.item.id == 50640)
check("row 1 has no alternative", not rows[1].altButton:IsShown())
check("row 2 (Neck) has an alternative", rows[2].altButton:IsShown() and rows[2].altButton.item.id == 50627)
check("rows past the spec's slots are hidden", not rows[17]:IsShown() and not rows[18]:IsShown())
check("16 rows shown for Blood DK Tank", (function()
    local n = 0
    for i = 1, #rows do if rows[i]:IsShown() then n = n + 1 end end
    return n
end)() == 16)

-- 5. Item name colouring ----------------------------------------------------------
_G.__itemInfo[50640] = { name = "Broken Ram Skull Helm", quality = 4 }
_G.__itemInfo[49623] = { name = "Shadowmourne", quality = 5 }
check("cached epic renders in epic colour", addon:FormatBiSItemName({ id = 50640, name = "x" }):find("a335ee", 1, true) ~= nil)
check("cached legendary renders in legendary colour", addon:FormatBiSItemName({ id = 49623, name = "x" }):find("ff8000", 1, true) ~= nil)
check("uncached item uses the data name in epic colour",
    addon:FormatBiSItemName({ id = 12345, name = "Mystery Helm" }):find("Mystery Helm", 1, true) ~= nil)
check("item with no id and no AtlasLoot renders grey",
    addon:FormatBiSItemName({ name = "Totem of Hex" }):find("9d9d9d", 1, true) ~= nil)

-- 6. Without AtlasLoot ---------------------------------------------------------------
check("AtlasLoot reported missing", addon:IsAtlasLootAvailable() == false)
check("status line says AtlasLoot is not installed", (addon:BuildBiSStatusText() or ""):find("not installed", 1, true) ~= nil)
check("no sources without AtlasLoot", #addon:GetBiSItemSources({ id = 50640, name = "x" }) == 0)
printed = {}
check("right-click without AtlasLoot returns false", addon:OpenBiSItemInAtlasLoot({ id = 50640, name = "x" }) == false)
check("right-click without AtlasLoot explains why", (printed[1] or ""):find("AtlasLoot is not installed", 1, true) ~= nil, printed[1])

-- 7. Fake AtlasLoot, shaped like v5.11.04's real tables -------------------------------
AtlasLoot_TableNames = {
    ICCLichKing = { "The Lich King", "AtlasLootWotLK" },
    ICCLichKing25Man = { "The Lich King", "AtlasLootWotLK" },
    ICCLichKingHEROIC = { "The Lich King", "AtlasLootWotLK" },
    ICCLichKing25ManHEROIC = { "The Lich King", "AtlasLootWotLK" },
    Halion = { "Halion", "AtlasLootWotLK" },
    Halion25Man = { "Halion", "AtlasLootWotLK" },
    HoRMarwyn = { "Marwyn", "AtlasLootWotLK" },
    HoRMarwynHEROIC = { "Marwyn", "AtlasLootWotLK" },
    TriumphVendor = { "Emblem of Triumph", "AtlasLootWotLK" },
    OldWorldThing = { "Ragnaros", "AtlasLoot" },
}
AtlasLoot_Data = {
    ICCLichKing25ManHEROIC = { { 1, 50640, "", "=q4=Broken Ram Skull Helm", "" }, { 2, 49623, "", "=q5=Shadowmourne", "" } },
    ICCLichKing25Man = { { 1, 50640, "", "=q4=Broken Ram Skull Helm", "" } },
    ICCLichKingHEROIC = { { 1, 50640, "", "=q4=Broken Ram Skull Helm", "" } },
    Halion = { { 1, 54577, "", "=q4=Halion Thing", "" } },
    HoRMarwynHEROIC = { { 1, 50318, "", "=q4=Marwyn Thing", "" } },
    TriumphVendor = { { 1, 47666, "", "=q4=Totem of Hex", "" }, { 2, "s12345", "", "=ds=Some Spell", "" } },
}
local shown = {}
AtlasLoot_ShowBossLoot = function(dataID, boss, pFrame) table.insert(shown, { dataID = dataID, boss = boss, pFrame = pFrame }) end
AtlasLootDefaultFrame = CreateFrame("Frame", "AtlasLootDefaultFrame")
AtlasLootDefaultFrame:Hide()
AtlasLootDefaultFrame_LootBackground = CreateFrame("Frame", "AtlasLootDefaultFrame_LootBackground")
local loadAllCalls = 0
AtlasLoot_LoadAllModules = function()
    loadAllCalls = loadAllCalls + 1
    AtlasLoot_Data.OldWorldThing = { { 1, 17182, "", "=q5=Sulfuras", "" } }
end
addon.bisAtlasIndex, addon.bisAtlasIndexScope = nil, nil
_G.__loadedAddons, _G.__loadAddOnCalls = nil, 0

check("AtlasLoot detected", addon:IsAtlasLootAvailable() == true)
local index = addon:EnsureAtlasLootIndex()
check("index built", index ~= nil and index.byId[50640] ~= nil)
check("WotLK module loaded on demand", _G.__loadedAddons and _G.__loadedAddons["AtlasLoot_WrathoftheLichKing"] == true)
check("index is cached (no rebuild)", addon:EnsureAtlasLootIndex() == index)
check("spell entries are skipped", index.byName["some spell"] == nil)

local sources = addon:GetBiSItemSources({ id = 50640, name = "Broken Ram Skull Helm" })
check("three tables drop the helm", #sources == 3, #sources)
check("25 HC sorts first", sources[1].dataID == "ICCLichKing25ManHEROIC", sources[1].dataID)
check("label: The Lich King (25 HC)", sources[1].label == "The Lich King (25 HC)", sources[1].label)
check("label: The Lich King (25)", sources[2].label == "The Lich King (25)", sources[2].label)
check("label: The Lich King (10 HC)", sources[3].label == "The Lich King (10 HC)", sources[3].label)
check("label: Halion (10) from a 25-man sibling", addon:FormatAtlasLootSource("Halion") == "Halion (10)")
check("label: 5-man heroic is just (HC)", addon:FormatAtlasLootSource("HoRMarwynHEROIC") == "Marwyn (HC)")
check("label: vendor has no size", addon:FormatAtlasLootSource("TriumphVendor") == "Emblem of Triumph")

-- Name resolution for the two linkless workbook items.
local totem = { name = "Totem of Hex" }
check("linkless item resolved by name through AtlasLoot", addon:ResolveBiSItemId(totem) == 47666)
check("resolved id is cached on the item", totem.id == 47666)
check("linkless item now colours as an item, not grey", addon:FormatBiSItemName(totem):find("9d9d9d", 1, true) == nil)

-- Miss in WotLK data -> one full-module load, then found.
local sulf = addon:GetBiSItemSources({ id = 17182, name = "Sulfuras" })
check("miss triggers AtlasLoot_LoadAllModules once", loadAllCalls == 1, loadAllCalls)
check("item found after the full load", #sulf == 1 and sulf[1].dataID == "OldWorldThing")
addon:GetBiSItemSources({ id = 424242, name = "Nothing" })
check("second miss does not reload everything again", loadAllCalls == 1, loadAllCalls)

-- 8. Tooltip --------------------------------------------------------------------------
-- The hidden scan tooltip records what it was asked to fetch.
local scanRequests = {}
addon.scanTooltip = CreateFrame("GameTooltip", "RaidInspectorScanTooltip")
addon.scanTooltip.SetHyperlink = function(self, link) table.insert(scanRequests, link) end

local btn = { item = { id = 50640, name = "Broken Ram Skull Helm", ilvl = 277 } }
addon:ShowBiSItemTooltip(btn)
check("tooltip uses the item hyperlink", tooltipHyperlink == "item:50640", tooltipHyperlink)
local joined = table.concat(tooltipLines, "\n")
check("tooltip does not duplicate the name when cached", joined:find("Broken Ram Skull Helm", 1, true) == nil, joined)
check("tooltip lists the drop source", joined:find("Drops from: The Lich King (25 HC)", 1, true) ~= nil, joined)
check("tooltip lists further sources", joined:find("The Lich King (25)", 1, true) ~= nil)
check("tooltip advertises right-click", joined:find("Right%-click") ~= nil)
check("tooltip advertises shift-click", joined:find("Shift%-click") ~= nil)

local uncached = { item = { id = 51309, name = "Sanctified Scourgelord Pauldrons", ilvl = 277 } }
scanRequests = {}
addon:ShowBiSItemTooltip(uncached)
joined = table.concat(tooltipLines, "\n")
check("uncached item never puts a hyperlink on the visible tooltip (3.3.5 disconnect guard)",
    tooltipHyperlink == nil, tooltipHyperlink)
check("uncached item is requested through the hidden scan tooltip",
    scanRequests[1] == "item:51309", scanRequests[1])
check("uncached item still shows its name", joined:find("Sanctified Scourgelord Pauldrons", 1, true) ~= nil, joined)
check("uncached item shows its item level", joined:find("Item Level 277", 1, true) ~= nil)
check("uncached item says data is pending", joined:find("not cached yet", 1, true) ~= nil)
check("uncached item with no AtlasLoot table says so", joined:find("not found in AtlasLoot", 1, true) ~= nil)

-- 9. Right-click -> AtlasLoot -------------------------------------------------------------
shown = {}
check("right-click opens AtlasLoot", addon:OpenBiSItemInAtlasLoot({ id = 50640, name = "Broken Ram Skull Helm" }) == true)
check("default AtlasLoot frame shown first", AtlasLootDefaultFrame:IsShown())
check("boss page requested is the 25 HC table", shown[1] and shown[1].dataID == "ICCLichKing25ManHEROIC", shown[1] and shown[1].dataID)
check("boss title passed through", shown[1] and shown[1].boss == "The Lich King (25 HC)")
check("anchored inside AtlasLoot's loot background", shown[1] and shown[1].pFrame and shown[1].pFrame[2] == "AtlasLootDefaultFrame_LootBackground")
printed = {}
check("right-click on an item AtlasLoot lacks returns false", addon:OpenBiSItemInAtlasLoot({ id = 424242, name = "Nothing" }) == false)
check("...and says so", (printed[1] or ""):find("no loot table", 1, true) ~= nil, printed[1])

-- Through the real button handler.
shown = {}
addon:OnBiSItemClick({ item = { id = 50640, name = "x" } }, "RightButton")
check("OnClick RightButton routes to AtlasLoot", #shown == 1)
_G.__insertedLink = nil
_G.__shiftDown = true
addon:OnBiSItemClick({ item = { id = 50640, name = "x" } }, "LeftButton")
check("shift-left-click inserts the item link", _G.__insertedLink and _G.__insertedLink:find("item:50640", 1, true) ~= nil, _G.__insertedLink)
_G.__shiftDown = false
_G.__insertedLink = nil
addon:OnBiSItemClick({ item = { id = 50640, name = "x" } }, "LeftButton")
check("plain left-click does nothing", _G.__insertedLink == nil)
check("click with no item is a no-op", pcall(addon.OnBiSItemClick, addon, {}, "RightButton"))

-- 10. /ri bis ------------------------------------------------------------------------------
addon:SetActiveTab("inspector")
addon:HandleBiSCommand("fury")
check("/ri bis fury selects Fury Warrior", addon:GetSelectedBiSSpec().key == "fury-warrior", addon:GetSelectedBiSSpec().key)
check("/ri bis switches to the BIS tab", addon:GetActiveTab() == "bis")
addon:HandleBiSCommand("holy priest")
check("/ri bis matches a full label", addon:GetSelectedBiSSpec().key == "holy-priest")
printed = {}
addon:HandleBiSCommand("nosuchspec")
check("/ri bis with a bad spec keeps the selection", addon:GetSelectedBiSSpec().key == "holy-priest")
check("/ri bis with a bad spec explains", (printed[1] or ""):find("no spec matches", 1, true) ~= nil)

-- 11. Cache warm-up ---------------------------------------------------------------------------
scanRequests = {}
addon.bisWarmedSpecKey = nil
local bloodDk = addon:GetBiSSpecByKey("blood-dk-tank")
local requested = addon:WarmBiSItemCache(bloodDk)
check("warm-up requests the spec's uncached items", requested > 0 and #scanRequests == requested, requested)
check("warm-up skips items already cached (50640)", (function()
    for _, l in ipairs(scanRequests) do if l == "item:50640" then return false end end
    return true
end)())
check("warm-up runs once per spec", addon:WarmBiSItemCache(bloodDk) == 0)
scanRequests = {}
addon:SetSelectedBiSSpec("holy-priest")
check("rendering a new spec warms its cache", #scanRequests > 0, #scanRequests)
scanRequests = {}
addon:RefreshBiSPanel()
check("re-rendering the same spec does not re-request", #scanRequests == 0, #scanRequests)

-- 12. Status line with AtlasLoot present -----------------------------------------------------------
check("status line says AtlasLoot is ready", (addon:BuildBiSStatusText() or ""):find("AtlasLoot: ready", 1, true) ~= nil)

finish()
