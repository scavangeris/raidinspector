-- Raid achievement comparison: ids, queue discipline, request/ready round
-- trip, silent-failure guard, priority, timeout, re-arm wiring, rendering.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

check("db initialised", type(_G.RaidInspectorDB) == "table")
check("results table exists", type(_G.RaidInspectorDB.results) == "table")

-- 1. IDs resolve -------------------------------------------------------------
printed = {}
addon:PrintAchievementIds()
local idDump = table.concat(printed, "\n")
check("ach ids: icc10 -> 4530", idDump:find("icc10 = 4530", 1, true) ~= nil, idDump)
check("ach ids: icc25 -> 4597", idDump:find("icc25 = 4597", 1, true) ~= nil)
check("ach ids: rs10 -> 4817", idDump:find("rs10 = 4817", 1, true) ~= nil)
check("ach ids: rs25 -> 4815", idDump:find("rs25 = 4815", 1, true) ~= nil)
check("ach ids: all six resolve to names", idDump:find("unresolved") == nil, idDump)

-- 2. Queue discipline (keys are lowercase, as MakePlayerKey produces them) ----
local KEY = "pizdulka-testrealm"
_G.RaidInspectorDB.results[KEY] = { gearScore = 5400, items = { {} }, raidAchievements = {} }
check("queues a player with gear but no ach data", addon:QueueAchievementScan(KEY, "Pizdulka", "TestRealm") == true)
check("does not double-queue the same key", addon:QueueAchievementScan(KEY, "Pizdulka", "TestRealm") == false)

_G.RaidInspectorDB.results[KEY].raidAchievements = { icc10 = true, source = "local-inspect" }
addon.achQueue, addon.achQueuedKeys, addon.achAttempted = {}, {}, {}
check("never re-queues once data is stored", addon:QueueAchievementScan(KEY, "Pizdulka", "TestRealm") == false)

_G.RaidInspectorDB.results[KEY].raidAchievements = {}
addon.achQueue, addon.achQueuedKeys = {}, {}
addon:MarkAchievementAttempt(KEY)
check("failed attempt is not retried automatically", addon:QueueAchievementScan(KEY, "Pizdulka", "TestRealm") == false)
addon:ClearAchievementAttempt(KEY)
check("manual re-arm allows a new attempt", addon:QueueAchievementScan(KEY, "Pizdulka", "TestRealm") == true)

-- 3. Round trip -------------------------------------------------------------
_G.__units["raid1"] = { name = "Pizdulka", realm = "TestRealm", guid = "0xGUID1", class = "MAGE", level = 80 }
_G.__numRaid = 3
_G.RaidInspectorDB.results[KEY].raidAchievements = {}
addon.achQueue = { { key = KEY, name = "Pizdulka", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY] = true }
addon.achAttempted, addon.achCurrent, addon.achLastRequestAt = {}, nil, 0
addon.inspectCurrent, addon.inspectQueue = nil, {}
registeredEvents["INSPECT_ACHIEVEMENT_READY"] = 0
addon:ProcessAchievementQueue()
check("comparison unit was set", achComparisonUnit == "raid1", tostring(achComparisonUnit))
check("event registered only while in flight", (registeredEvents["INSPECT_ACHIEVEMENT_READY"] or 0) == 1)
check("request is tracked", addon.achCurrent ~= nil and addon.achCurrent.key == KEY)

_G.__achPoints = 8420
_G.__achData = { [4530] = true, [4597] = false, [4817] = true, [4815] = false, [3917] = true, [3916] = false }
addon:OnInspectAchievementReady("0xGUID1")
local stored = _G.RaidInspectorDB.results[KEY].raidAchievements
check("icc10 recorded true", stored.icc10 == true)
check("icc25 recorded false", stored.icc25 == false)
check("rs10 recorded true", stored.rs10 == true)
check("rs25 recorded false", stored.rs25 == false)
check("toc collected too", stored.toc10 == true and stored.toc25 == false)
check("source stamped", stored.source == "local-inspect")
check("achievement points captured", _G.RaidInspectorDB.results[KEY].achievementPoints == 8420)
check("comparison unit cleared after read", achComparisonUnit == nil)
check("request state cleared", addon.achCurrent == nil)
check("event unregistered after read", (unregisteredEvents["INSPECT_ACHIEVEMENT_READY"] or 0) >= 1)

-- 4. No data must NOT become six red Xs ---------------------------------------
local KEY2 = "ghost-testrealm"
_G.RaidInspectorDB.results[KEY2] = { gearScore = 5000, items = { {} }, raidAchievements = {} }
_G.__units["raid2"] = { name = "Ghost", realm = "TestRealm", guid = "0xGUID2" }
addon.achQueue = { { key = KEY2, name = "Ghost", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY2] = true }
addon.achAttempted, addon.achCurrent, addon.achLastRequestAt = {}, nil, 0
addon:ProcessAchievementQueue()
_G.__achPoints, _G.__achData = nil, nil
addon:OnInspectAchievementReady("0xGUID2")
local ghost = _G.RaidInspectorDB.results[KEY2].raidAchievements
check("no flags written when data did not arrive", ghost.icc10 == nil and ghost.rs10 == nil)
check("failed read still ends the request", addon.achCurrent == nil)

-- 5. GUID mismatch ------------------------------------------------------------
local KEY3 = "other-testrealm"
_G.RaidInspectorDB.results[KEY3] = { gearScore = 5000, items = { {} }, raidAchievements = {} }
_G.__units["raid3"] = { name = "Other", realm = "TestRealm", guid = "0xGUID3" }
addon.achQueue = { { key = KEY3, name = "Other", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY3] = true }
addon.achAttempted, addon.achCurrent, addon.achLastRequestAt = {}, nil, 0
addon:ProcessAchievementQueue()
_G.__achPoints, _G.__achData = 100, { [4530] = true }
addon:OnInspectAchievementReady("0xSOMEONEELSE")
check("wrong guid does not write flags", _G.RaidInspectorDB.results[KEY3].raidAchievements.icc10 == nil)
check("wrong guid leaves request in flight", addon.achCurrent ~= nil)
addon:OnInspectAchievementReady("0xGUID3")
check("correct guid completes it", _G.RaidInspectorDB.results[KEY3].raidAchievements.icc10 == true)

-- 6. Gear has priority --------------------------------------------------------
addon.achQueue = { { key = KEY, name = "Pizdulka", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY] = true }
addon.achCurrent, addon.achLastRequestAt = nil, 0
addon.inspectCurrent = { key = "someone", unit = "raid1" }
achComparisonUnit = nil
addon:ProcessAchievementQueue()
check("no comparison while a gear inspect is running", achComparisonUnit == nil)
check("queue is untouched while gear runs", #addon.achQueue == 1)
addon.inspectCurrent = nil
addon.inspectQueue = { { key = "pending" } }
addon:ProcessAchievementQueue()
check("no comparison while the gear queue is non-empty", achComparisonUnit == nil)
addon.inspectQueue = {}

-- 7. Timeout ------------------------------------------------------------------
_G.__now = 1000
addon.achCurrent = { key = "stuck", startedAt = 1000, unit = "raid1", guid = "x" }
addon.achAttempted = {}
_G.__now = 1003
addon:TickAchievementScan()
check("still in flight before the timeout", addon.achCurrent ~= nil)
_G.__now = 1010
addon:TickAchievementScan()
check("timeout drops the request", addon.achCurrent == nil)
check("timeout records the attempt so it is not retried", addon.achAttempted["stuck"] == true)
_G.__now = 1000

-- 8. Missing API disables the feature -----------------------------------------
local savedSet = SetAchievementComparisonUnit
SetAchievementComparisonUnit = nil
addon.achDisabled = nil
addon.achQueue = { { key = KEY, name = "Pizdulka", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY] = true }
addon.achCurrent, addon.achLastRequestAt = nil, 0
addon:ProcessAchievementQueue()
check("missing API disables scanning", addon.achDisabled == true)
check("disabled scanner queues nothing further", addon:QueueAchievementScan("new-testrealm", "New", "TestRealm") == false)
SetAchievementComparisonUnit = savedSet
addon.achDisabled = nil

-- 9. Out of range is marked, not retried --------------------------------------
local KEY4 = "faraway-testrealm"
_G.RaidInspectorDB.results[KEY4] = { gearScore = 5000, items = { {} }, raidAchievements = {} }
addon.achQueue = { { key = KEY4, name = "Faraway", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY4] = true }
addon.achAttempted, addon.achCurrent, addon.achLastRequestAt = {}, nil, 0
achComparisonUnit = nil
addon:ProcessAchievementQueue()
check("unreachable player starts no request", addon.achCurrent == nil)
check("unreachable player sets no comparison unit", achComparisonUnit == nil)
check("unreachable player is marked attempted", addon.achAttempted[KEY4] == true)

-- 10. Rendering ---------------------------------------------------------------
local built, buildErr = pcall(function() addon:ToggleWindow(true) end)
check("main window builds", built and addon.ui ~= nil and addon.ui.detailMeta ~= nil, buildErr)
if built and addon.ui and addon.ui.detailMeta then
    local entry = {
        key = KEY, state = "ready",
        req = { name = "Pizdulka", realm = "TestRealm", key = KEY, status = "ready" },
        result = {
            gearScore = 5400, class = "MAGE", spec = "Frost", level = 80, items = {}, issueSummary = {},
            raidAchievements = { icc10 = true, icc25 = false, rs10 = true, source = "local-inspect" },
        },
    }
    addon:RefreshDetailPanel(entry)
    local meta = addon.ui.detailMeta:GetText() or ""
    check("detail line still shows the talent spec", meta:find("Frost", 1, true) ~= nil, meta)
    check("ICC10 label present", meta:find("ICC10", 1, true) ~= nil)
    check("ICC25 label present", meta:find("ICC25", 1, true) ~= nil)
    check("RS10 label present", meta:find("RS10", 1, true) ~= nil)
    check("RS25 label present", meta:find("RS25", 1, true) ~= nil)
    check("a green check texture is emitted", meta:find("ReadyCheck%-Ready") ~= nil)
    check("a red X texture is emitted", meta:find("ReadyCheck%-NotReady") ~= nil)
    check("unknown flag renders as ?", meta:find("?", 1, true) ~= nil)
    local _, checkCount = meta:gsub("ReadyCheck%-Ready:0", "")
    local _, crossCount = meta:gsub("ReadyCheck%-NotReady:0", "")
    check("two checks for the two completed raids", checkCount == 2, checkCount)
    check("one X for the one failed raid", crossCount == 1, crossCount)
    entry.result.raidAchievements = {}
    addon:RefreshDetailPanel(entry)
    local _, blankCrosses = (addon.ui.detailMeta:GetText() or ""):gsub("ReadyCheck%-NotReady:0", "")
    check("unscanned player shows no red Xs", blankCrosses == 0)
end

-- 11. MS regression guard -------------------------------------------------------
pcall(function() addon:SetMSTrackingEnabled(true) end)
addon:OnRaidChatMessage("CHAT_MSG_RAID", "MS resto", "Healer")
local msEntries = (_G.RaidInspectorDB.msTracking and _G.RaidInspectorDB.msTracking.entries) or {}
local found, echoed
for _, v in pairs(msEntries) do if v.name == "Healer" then found = v end end
check("MS still registers from raid chat", found ~= nil and found.spec == "resto")
addon:OnRaidChatMessage("CHAT_MSG_RAID", "MS changes (3): Bob=resto", "Sharer")
for _, v in pairs(msEntries) do if v.name == "Sharer" then echoed = v end end
check("MS self-echo guard still holds", echoed == nil)

-- 12. Re-arm wiring -------------------------------------------------------------
addon.achAttempted = { [KEY] = true, ["someone-testrealm"] = true }
pcall(function() addon:RefreshOverviewEntryByKey(KEY) end)
check("row Refresh re-arms that player", addon.achAttempted[KEY] == nil)
check("row Refresh leaves other players marked", addon.achAttempted["someone-testrealm"] == true)
addon.achAttempted = { [KEY] = true, ["someone-testrealm"] = true }
pcall(function() addon:QueueStaleRefresh("15") end)
check("Refresh (stale sweep) re-arms everyone", next(addon.achAttempted) == nil)
addon.achAttempted = { [KEY] = true }
pcall(function() addon:QueueRaidSnapshot({ silent = true, reuseHistory = true, pruneMissing = true, skipScanned = true }) end)
check("autoscan does not re-arm", addon.achAttempted[KEY] == true)
pcall(function() addon:QueueRaidSnapshot({}) end)
check("Raid button re-arms everyone", next(addon.achAttempted) == nil)
addon.achQueue = { { key = KEY, name = "Pizdulka", realm = "TestRealm" } }
addon.achQueuedKeys = { [KEY] = true }
addon.achCurrent = { key = KEY, startedAt = 1000 }
pcall(function() addon:ClearQueue() end)
check("Clear empties the achievement queue", #addon.achQueue == 0)
check("Clear drops the in-flight comparison", addon.achCurrent == nil)

finish()
