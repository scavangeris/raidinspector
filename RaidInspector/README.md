# Raid Inspector

Raid Inspector is a WoW 3.3.5a addon for raid gear analysis on the bridgeless branch.

## Branch Goal
- Work fully in-game with no external bridge, desktop script, or file export step.
- Inspect nearby or raid-visible players through the WoW inspect API.
- Save detailed roster reports and single-player snapshots directly in SavedVariables.

## What Works In This Branch
- Target inspection with live gear parsing.
- Raid snapshot scanning for current raid members.
- Gear score estimation from inspected items.
- Enchant and gem auditing.
- Talent/spec detection from in-game talent inspection.
- Achievement comparison for inspectable targets when the client supports it.
- Saved detailed reports loaded directly from the in-game dropdown.
- Saved single-player share snapshots for chat export.

## Important Limitation
WoW addons cannot perform HTTP requests or write arbitrary files while the client is running.

Because of that, this branch only works with players that currently exist as inspectable in-game units, typically:
- your current target
- party members
- raid members

Name-only remote lookups are intentionally not supported here.

## Commands
- `/ri help`
- `/ri show`
- `/ri hide`
- `/ri toggle`
- `/ri inspect <name> <realm>`
- `/ri inspect <name-realm>`
- `/ri inspecttarget`
- `/ri inspectraid`
- `/ri sort [recent|gs|issues|name]`
- `/ri filter [all|snapshot|ready|queued|issues]`
- `/ri report`
- `/ri loadreport [latest|report-id]`
- `/ri share [name-realm]`
- `/ri savereport [name-realm]`
- `/ri sharesaved [latest|id|name-realm]`
- `/ri export` remains as a compatibility alias for `/ri report`
- `/ri exportsaved` remains as a compatibility alias for `/ri sharesaved`
- `/ri status`
- `/ri refreshstale [minutes]`
- `/ri clearqueue [confirm]`

## Main Window Actions
- `Target`: inspect the current target immediately.
- `Raid`: queue and inspect current raid members.
- `Share`: send the selected/current summary to chat.
- `Save`: save the selected/current single-player snapshot.
- `Report`: save the full current overview as a detailed local report.
- `Refresh`: attempt live refresh for stale entries that are currently present in target/party/raid.
- `Status`: print runtime status into chat.
- `Clear`: clear queued requests and cached live-inspect results.

## Saved Data
Detailed reports now stay inside `RaidInspectorDB.savedReportFiles.items` instead of being written to addon-folder JSON files.

Single-player reusable share snapshots stay in `RaidInspectorDB.reportSnapshots.items`.

Raid snapshot history remains in `RaidInspectorDB.raidScanHistory.scans`.

## SavedVariables Shape
```lua
RaidInspectorDB = {
	meta = { schemaVersion = 4, lastLoadedAt = 0 },
	settings = { window = { point = "CENTER", x = 0, y = 0 } },
	state = {
		nextRequestId = 1,
		lastSnapshot = { at = 0, historyId = 0, members = {} },
		ui = { selectedSavedReportFile = "" },
	},
	requests = {
		-- { id, name, realm, key, status, requestedAt, updatedAt }
	},
	results = {
		-- ["name-realm"] = { gearScore = 0, items = {...}, updatedAt = 0, source = "local-inspect" }
	},
	reportSnapshots = {
		nextId = 1,
		items = {
			-- { id, savedAt, key, name, realm, message, payload = {...} }
		}
	},
	savedReportFiles = {
		generatedAt = 0,
		items = {
			-- { fileName, label, createdAt, report = {...} }
		}
	},
	raidScanHistory = {
		nextId = 1,
		scans = {
			-- { id, snapshotAt, updatedAt, roster = {...}, summaryPayloads = {...} }
		}
	}
}
```

## Legacy Bridge Assets
The `bridge/` folder and bridge-related docs are kept in the repository as historical implementation assets from `main`, but they are not part of the bridgeless runtime flow.
- Request pacing: outbound requests are rate-limited with `--request-delay`.
- Atomic writes: bridge and item-ilvl cache files are written via temp-file + replace to reduce corruption risk.
- Cache TTL guard: `--cache-ttl-minutes` skips network calls for recently updated keys from addon SavedVariables cache.
- Schema guard: non-dict API payloads are wrapped for resilient parsing instead of hard-failing.

## Release Packaging (Phase 8)
Build a release zip that contains both addons (`RaidInspector` + `RaidInspectorBridge`).

```bash
cd "Interface/AddOns/RaidInspector"
/usr/bin/python3 "tools/package_release.py"
```

Default output:
- `Interface/AddOns/RaidInspectorRelease/RaidInspector-v<version>.zip`

Optional arguments:
- `--addons-root ".../Interface/AddOns"`
- `--output-dir ".../output/folder"`
- `--version "0.6.0-alpha"`

Bridge operator guide:
- `bridge/BRIDGE_SETUP.md`
