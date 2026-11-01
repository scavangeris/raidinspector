-- Raid scan history is capped by count, keeps the active entry, and is
-- pruned at load. Includes a run against the user's real 25 MB file.
dofile(ADDON_DIR .. "/tools/test/_harness.lua")

local history = addon:GetRaidScanHistory()
local function seed(n, activeId)
    history.scans = {}
    for i = 1, n do
        history.scans[i] = { id = i, snapshotAt = 1000 + i, updatedAt = 1000 + i, members = {}, summaryPayloads = {} }
    end
    RaidInspectorDB.state.lastSnapshot.historyId = activeId or 0
end
local function ids()
    local t = {}
    for _, e in ipairs(history.scans) do t[#t + 1] = e.id end
    return table.concat(t, ",")
end

_G.__now = 2000  -- all seeded entries are well inside the 30-day window

seed(5)
addon:PruneRaidScanHistory()
check("under the cap nothing is dropped", #history.scans == 5)

seed(342)
addon:PruneRaidScanHistory()
check("342 snapshots trimmed to 10", #history.scans == 10, #history.scans)
check("the newest 10 are the ones kept", ids() == "333,334,335,336,337,338,339,340,341,342", ids())

seed(342, 7)
addon:PruneRaidScanHistory()
check("an old active entry survives the cap", ids():find("^7,") ~= nil, ids())
check("...alongside the newest 10", #history.scans == 11, #history.scans)
check("active id still set", RaidInspectorDB.state.lastSnapshot.historyId == 7)

seed(342, 342)
addon:PruneRaidScanHistory()
check("active entry among the newest is not double-counted", #history.scans == 10)

-- Age rule still applies on top.
_G.__now = 1000 + 31 * 24 * 3600
seed(3)
addon:PruneRaidScanHistory()
check("entries older than 30 days still expire", #history.scans == 0)
_G.__now = nil

-- Pruned at load: a bloated table shrinks with no scan in the session.
seed(342)
addon:OnAddonLoaded("RaidInspector")
check("prune runs at load", #history.scans == 10, #history.scans)

-- The real file, if present (from the user's WTF folder).
local realPath = ADDON_DIR .. "/../../../WTF/Account/SCAVANGERIS3/SavedVariables/RaidInspector.lua"
local fh = io.open(realPath, "r")
if fh then
    fh:close()
    local saved = RaidInspectorDB
    RaidInspectorDB = nil
    dofile(realPath)
    local before = #RaidInspectorDB.raidScanHistory.scans
    addon:PruneRaidScanHistory()
    local after = #RaidInspectorDB.raidScanHistory.scans
    print(string.format("  real SavedVariables: %d snapshots -> %d", before, after))
    -- The file may already have been trimmed in-game, so only the cap is asserted.
check("real file: history within the cap", after <= 11, after)
    RaidInspectorDB = saved
end

finish()
