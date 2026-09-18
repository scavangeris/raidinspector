-- Compact layout (gear list hidden) and the composition line under the buttons.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

local built, buildErr = pcall(function() addon:ToggleWindow(true) end)
check("main window builds", built and addon.ui and addon.ui.frame ~= nil, buildErr)

-- The stub's SetWidth is a no-op; record it so the width logic is observable.
local frame = addon.ui.frame
frame.SetWidth = function(self, w) self.__width = w end
addon.ui.statusText.SetWidth = function(self, w) self.__width = w end

-- 1. Defaults ------------------------------------------------------------------
check("collapsed flag defaults to false", _G.RaidInspectorDB.settings.window.collapsed == false)
check("not collapsed by default", addon:IsWindowCollapsed() == false)
check("collapse button exists", addon.ui.collapseButton ~= nil)
addon:SetActiveTab("inspector")
addon:RefreshMainWindow()
check("full width on the inspector tab", frame.__width == 1180, frame.__width)
check("button reads << when expanded", addon.ui.collapseButton:GetText() == "<<", addon.ui.collapseButton:GetText())
check("gear panel visible when expanded", addon.ui.detailHeader:IsShown() and addon.ui.detailContainer:IsShown())

-- 2. Composition line lives on the left now ------------------------------------------
check("composition header text is short", addon.ui.compositionHeader:GetText() == "Composition:", addon.ui.compositionHeader:GetText())
local comp = addon.ui.compositionSummary:GetText() or ""
check("composition summary uses the compact separators", comp:find("^Tanks: %d+ | Heals: %d+ | RDPS: %d+ | MDPS: %d+ | Total: %d+$") ~= nil, comp)

-- 3. Collapse -----------------------------------------------------------------------
check("SetWindowCollapsed(true) returns true", addon:SetWindowCollapsed(true) == true)
check("flag persisted in the DB", _G.RaidInspectorDB.settings.window.collapsed == true)
check("frame narrows to the compact width", frame.__width == 512, frame.__width)
check("status line narrows with it", addon.ui.statusText.__width == 512 - 48, addon.ui.statusText.__width)
check("button reads >> when collapsed", addon.ui.collapseButton:GetText() == ">>")
check("gear panel hidden: header", not addon.ui.detailHeader:IsShown())
check("gear panel hidden: score/meta/audit",
    not addon.ui.detailScore:IsShown() and not addon.ui.detailMeta:IsShown() and not addon.ui.detailAudit:IsShown())
check("gear panel hidden: item list", not addon.ui.detailContainer:IsShown() and not addon.ui.detailScroll:IsShown())
check("gear panel hidden: filter dropdown", not addon.ui.itemFilterDropDown:IsShown() and not addon.ui.itemFilterLabel:IsShown())
check("raid list still shown", addon.ui.rowsViewport:IsShown() and addon.ui.overviewScroll:IsShown())
check("composition still shown (it is on the left)", addon.ui.compositionHeader:IsShown() and addon.ui.compositionSummary:IsShown())
check("action buttons still shown", addon.ui.actionPanel:IsShown() and addon.ui.raidButton:IsShown())

-- 4. Other tabs always get the full width ----------------------------------------------
addon:SetActiveTab("bis")
addon:RefreshMainWindow()
check("BIS tab restores full width while collapsed", frame.__width == 1180, frame.__width)
check("BIS panel shown at full width", addon.ui.bisPanel:IsShown())
check("preference kept while on another tab", addon:IsWindowCollapsed() == true)
addon:SetActiveTab("lfm")
addon:RefreshMainWindow()
check("LFM tab restores full width while collapsed", frame.__width == 1180)
addon:SetActiveTab("inspector")
addon:RefreshMainWindow()
check("back on Inspector the window narrows again", frame.__width == 512)
check("...and the gear panel is hidden again", not addon.ui.detailHeader:IsShown())

-- 5. Expand ----------------------------------------------------------------------------------
check("SetWindowCollapsed(false) returns false", addon:SetWindowCollapsed(false) == false)
check("frame back to full width", frame.__width == 1180)
check("gear panel back", addon.ui.detailHeader:IsShown() and addon.ui.detailContainer:IsShown())
check("button reads << again", addon.ui.collapseButton:GetText() == "<<")

-- 6. Button click + slash command ---------------------------------------------------------------
addon.ui.collapseButton:GetScript("OnClick")(addon.ui.collapseButton)
check("clicking the button collapses", addon:IsWindowCollapsed() == true and frame.__width == 512)
addon.ui.collapseButton:GetScript("OnClick")(addon.ui.collapseButton)
check("clicking again expands", addon:IsWindowCollapsed() == false and frame.__width == 1180)

local slash = SlashCmdList["RAIDINSPECTOR"]
check("slash handler registered", type(slash) == "function")
printed = {}
slash("compact on")
check("/ri compact on collapses", addon:IsWindowCollapsed() == true, printed[1])
check("/ri compact reports its state", (printed[#printed] or ""):find("compact view: on", 1, true) ~= nil, printed[#printed])
slash("compact off")
check("/ri compact off expands", addon:IsWindowCollapsed() == false)
slash("compact")
check("/ri compact toggles", addon:IsWindowCollapsed() == true)
addon:SetActiveTab("bis")
slash("compact")
check("/ri compact switches to the Inspector tab", addon:GetActiveTab() == "inspector")

-- 7. Persistence across a reload: the saved flag drives the first render ----------------------------------
_G.RaidInspectorDB.settings.window.collapsed = true
frame.__width = nil
addon:RefreshMainWindow()
check("saved flag applies on refresh without a click", frame.__width == 512)
_G.RaidInspectorDB.settings.window.collapsed = false
addon:RefreshMainWindow()

-- 8. Tooltip text reflects the state ---------------------------------------------------------------------
tooltipLines = {}
GameTooltip.SetText = function(self, t) table.insert(tooltipLines, t) end
addon.ui.collapseButton:GetScript("OnEnter")(addon.ui.collapseButton)
check("expanded tooltip offers to hide the gear list", (tooltipLines[1] or ""):find("hide the gear list", 1, true) ~= nil, tooltipLines[1])
addon:SetWindowCollapsed(true)
tooltipLines = {}
addon.ui.collapseButton:GetScript("OnEnter")(addon.ui.collapseButton)
check("collapsed tooltip offers to show it again", (tooltipLines[1] or ""):find("Show the gear list", 1, true) ~= nil, tooltipLines[1])

finish()
