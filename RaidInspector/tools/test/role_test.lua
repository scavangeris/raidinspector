-- Group-by-role: the checkbox layers tank/heal/mdps/rdps grouping on top of
-- whatever sort mode is chosen, and rows get a role tag only while it is on.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

local built, buildErr = pcall(function() addon:ToggleWindow(true) end)
check("main window builds", built and addon.ui ~= nil, buildErr)
check("by-role checkbox exists", addon.ui.sortByRoleCheck ~= nil)
check("by-role checkbox label", (_G["RaidInspectorSortByRoleCheckText"] and _G["RaidInspectorSortByRoleCheckText"]:GetText()) == "by role")

-- Six players: one per role, two healers, one never scanned.
local function add(id, name, class, spec, gs)
    local key = string.lower(name .. "-testrealm")
    table.insert(_G.RaidInspectorDB.requests, { id = id, name = name, realm = "TestRealm", key = key, status = gs and "ready" or "queued", requestedAt = 1000, updatedAt = 1000 })
    if gs then
        _G.RaidInspectorDB.results[key] = { name = name, realm = "TestRealm", class = class, spec = spec, gearScore = gs, items = { {} }, updatedAt = 1000, issuesCount = 0 }
    end
    return key
end
_G.RaidInspectorDB.requests = {}
_G.RaidInspectorDB.results = {}
add(1, "Tanky", "WARRIOR", "Protection", 6000)
add(2, "Holyp", "PRIEST", "Holy", 6500)
add(3, "Stabby", "ROGUE", "Combat", 6300)
add(4, "Boomy", "MAGE", "Arcane", 6700)
add(5, "Palah", "PALADIN", "Holy", 6100)
add(6, "Ghost", nil, nil, nil)
addon:SetFilterMode("all")
addon:SetSortMode("gs")

local function order()
    local names = {}
    for _, e in ipairs(addon:GetOverviewEntries()) do table.insert(names, e.req.name) end
    return table.concat(names, ",")
end

-- 1. Off: plain GS order ------------------------------------------------------------
check("group-by-role defaults to off", addon:IsGroupByRole() == false)
check("GS sort alone: highest first, unscanned last", order() == "Boomy,Holyp,Stabby,Palah,Tanky,Ghost", order())
local rowOff = addon:BuildOverviewRowText(addon:GetOverviewEntries()[1])
check("no role tag while off", rowOff:sub(1, 1) == "#", rowOff:sub(1, 12))

-- 2. On: tanks, healers, melee, ranged, unknown - GS inside each group ----------------
check("SetGroupByRole(true)", addon:SetGroupByRole(true) == true)
check("flag persisted", _G.RaidInspectorDB.settings.overview.groupByRole == true)
check("grouped: T, H(6500), H(6100), M, R, unknown", order() == "Tanky,Holyp,Palah,Stabby,Boomy,Ghost", order())

-- Role ranks and tags.
local entries = addon:GetOverviewEntries()
check("tank rank 1", addon:GetEntryRoleRank(entries[1]) == 1)
check("healer rank 2", addon:GetEntryRoleRank(entries[2]) == 2)
check("melee rank 3", addon:GetEntryRoleRank(entries[4]) == 3)
check("ranged rank 4", addon:GetEntryRoleRank(entries[5]) == 4)
check("unknown rank 5", addon:GetEntryRoleRank(entries[6]) == 5)
check("tank row carries a T tag", addon:BuildOverviewRowText(entries[1]):find("^|cff%x%x%x%x%x%xT|r #1 ") ~= nil, addon:BuildOverviewRowText(entries[1]))
check("healer row carries an H tag", addon:BuildOverviewRowText(entries[2]):find("H|r #2 ", 1, true) ~= nil)
check("melee row carries an M tag", addon:BuildOverviewRowText(entries[4]):find("M|r #3 ", 1, true) ~= nil)
check("ranged row carries an R tag", addon:BuildOverviewRowText(entries[5]):find("R|r #4 ", 1, true) ~= nil)
check("unscanned row carries a grey ?", addon:BuildOverviewRowText(entries[6]):find("?|r #6 ", 1, true) ~= nil)

-- 3. The underlying sort still applies inside groups --------------------------------------
addon:SetSortMode("name")
check("name sort inside groups: Holyp before Palah stays, Boomy still after Stabby", order() == "Tanky,Holyp,Palah,Stabby,Boomy,Ghost", order())
addon:SetSortMode("recent")
check("recent sort inside groups: newer request first within healers", order() == "Tanky,Palah,Holyp,Stabby,Boomy,Ghost", order())
addon:SetSortMode("gs")

-- 4. Checkbox and refresh ------------------------------------------------------------------
addon:SetActiveTab("inspector")
addon:RefreshMainWindow()
check("checkbox reflects the saved state", addon.ui.sortByRoleCheck:GetChecked() == true)
addon.ui.sortByRoleCheck:SetChecked(false)
addon.ui.sortByRoleCheck:GetScript("OnClick")(addon.ui.sortByRoleCheck)
check("unticking turns grouping off", addon:IsGroupByRole() == false)
check("order back to plain GS", order() == "Boomy,Holyp,Stabby,Palah,Tanky,Ghost")
addon.ui.sortByRoleCheck:SetChecked(true)
addon.ui.sortByRoleCheck:GetScript("OnClick")(addon.ui.sortByRoleCheck)
check("ticking turns grouping on", addon:IsGroupByRole() == true)

-- 5. Slash command -------------------------------------------------------------------------------
local slash = SlashCmdList["RAIDINSPECTOR"]
printed = {}
slash("byrole off")
check("/ri byrole off", addon:IsGroupByRole() == false and (printed[#printed] or ""):find("group by role: off", 1, true) ~= nil, printed[#printed])
slash("byrole on")
check("/ri byrole on", addon:IsGroupByRole() == true)
slash("byrole")
check("/ri byrole toggles", addon:IsGroupByRole() == false)

-- 5b. Group headers between roles ------------------------------------------------------------------
addon:SetGroupByRole(false)
local plain = addon:GetOverviewEntries()
check("off: display list is the entries themselves", addon:BuildOverviewDisplayList(plain) == plain)

addon:SetGroupByRole(true)
local display = addon:BuildOverviewDisplayList(addon:GetOverviewEntries())
local shape = {}
for _, e in ipairs(display) do
    table.insert(shape, e.separator and ("[" .. e.rank .. ":" .. e.count .. "]") or e.req.name)
end
check("on: a header above every group with its count",
    table.concat(shape, ",") == "[1:1],Tanky,[2:2],Holyp,Palah,[3:1],Stabby,[4:1],Boomy,[5:1],Ghost", table.concat(shape, ","))
check("header text names the group and count", addon:FormatOverviewGroupHeader(display[3]):find("Healers (2)", 1, true) ~= nil, addon:FormatOverviewGroupHeader(display[3]))
check("unknown group header wording", addon:FormatOverviewGroupHeader(display[10]):find("No talent data yet (1)", 1, true) ~= nil)

-- The plain entry list must never grow headers (composition, share, reports).
local n = 0
for _, e in ipairs(addon:GetOverviewEntries()) do if e.separator then n = n + 1 end end
check("GetOverviewEntries never contains headers", n == 0)

-- Rendered rows.
addon:SetActiveTab("inspector")
for _, r in ipairs(addon.ui.overviewRows) do r.EnableMouse = function(self, v) self.__mouse = v end end
addon:RefreshMainWindow()
local rows = addon.ui.overviewRows
check("row 1 is the Tanks header", (rows[1].text:GetText() or ""):find("Tanks (1)", 1, true) ~= nil, rows[1].text:GetText())
check("header row has no key (nothing to select or edit)", rows[1].key == nil)
check("header row ignores the mouse", rows[1].__mouse == false)
check("row 2 is Tanky", rows[2].key == "tanky-testrealm" and rows[2].__mouse == true)
check("row 3 is the Healers header", (rows[3].text:GetText() or ""):find("Healers (2)", 1, true) ~= nil)
check("rows 4-5 are the two healers", rows[4].key == "holyp-testrealm" and rows[5].key == "palah-testrealm")
check("scroll count includes the headers", addon.ui.overviewEntryCount == 11, addon.ui.overviewEntryCount)
check("selection is still a player, never a header", addon:GetSelectedKey() ~= "" and addon:GetSelectedKey() ~= nil)

addon:SetGroupByRole(false)
addon:RefreshMainWindow()
check("off: row 1 is a player again", rows[1].key ~= nil and rows[1].__mouse == true, rows[1].key)
check("off: scroll count is the player count", addon.ui.overviewEntryCount == 6)
addon:SetGroupByRole(false)

-- 6. Hidden with the other inspector widgets on other tabs ------------------------------------------------
addon:SetActiveTab("bis")
addon:RefreshMainWindow()
check("checkbox hidden on the BIS tab", not addon.ui.sortByRoleCheck:IsShown())
addon:SetActiveTab("inspector")
addon:RefreshMainWindow()
check("checkbox shown on the Inspector tab", addon.ui.sortByRoleCheck:IsShown())

finish()
