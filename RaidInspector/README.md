# Raid Inspector

Raid Inspector is a WoW 3.3.5a addon project for raid gear analysis.

## Goal
- Show player gear list and enchant status.
- Pull character summary from Warmane armory API.
- Calculate/validate gear score using Cavern of Time API logic.

## Important Technical Constraint
WoW addons cannot perform direct HTTP/HTTPS requests.

Because of this, Raid Inspector must use an external bridge process (desktop script/app) that:
1. Reads target character names from addon output (or saved queue).
2. Calls external APIs outside of WoW.
3. Writes processed results into SavedVariables for the addon to display.

## Current Status
- Phase 1 implemented:
	- SavedVariables schema (`meta`, `settings`, `state`, `requests`, `results`)
	- queue commands (`/ri inspect`, `/ri inspecttarget`)
	- basic queue/results window (`/ri show`)
- Phase 2 starter implemented:
	- bridge inbox SavedVariables (`RaidInspectorBridgeInbox`)
	- addon-side sync command (`/ri sync`)
	- auto-import of bridge inbox on login/reload
	- dedicated storage addon: `RaidInspectorBridge`
- Bridge helper assets added under `bridge/`:
	- `bridge/BRIDGE_CONTRACT.md`
	- `bridge/sample_result.json`
	- `bridge/write_bridge_inbox.py`
- Full implementation plan is in `ROADMAP.md`.
- Release assets:
	- `CHANGELOG.md`
	- `bridge/BRIDGE_SETUP.md`
	- `tools/package_release.py`
- Persistence/safety additions:
	- saved report snapshots (`/ri savereport`, `/ri exportsaved`)
	- 30-day retained raid scan archive in SavedVariables
	- confirmation before destructive `Clear` / `/ri clearqueue`
- Detailed report additions:
	- `Report` action queues a full roster report file for bridge export
	- bridge writes timestamped JSON reports into `Interface/AddOns/RaidInspector/reports/`
	- saved report files can be loaded from the in-game dropdown after `/ri sync`

## Commands
- `/ri help`
- `/ri show`
- `/ri hide`
- `/ri toggle`
- `/ri inspect <name> <realm>`
- `/ri inspect <name-realm>`
- `/ri inspecttarget`
- `/ri inspectraid`
- `/ri sync`
- `/ri forcesync`
- `/ri sort [recent|gs|issues|name]`
- `/ri filter [all|snapshot|ready|queued|issues]`
- `/ri report`
- `/ri loadreport [latest|filename]`
- `/ri share [name-realm]`
- `/ri savereport [name-realm]`
- `/ri sharesaved [latest|id|name-realm]`
- `/ri export` remains as a compatibility alias for `/ri report`
- `/ri exportsaved` remains as a compatibility alias for `/ri sharesaved`
- `/ri status`
- `/ri refreshstale [minutes]`
- `/ri clearqueue [confirm]`

## Live Inspect Mode (No Restart Needed)
For nearby/inspectable players, the addon now supports in-session live inspection.

- `Target` button or `/ri inspecttarget`:
	- queues and inspects your current target immediately
- `Raid` button or `/ri inspectraid`:
	- queues raid snapshot and starts live inspect scan

This path does not require restarting WoW or running external scripts.

Limitations:
- WoW inspect API requires the unit to be inspectable (range/visibility/permissions).
- If a unit is not inspectable, keep bridge mode as fallback.

## SavedVariables Shape
```lua
RaidInspectorDB = {
	meta = { schemaVersion = 3, lastLoadedAt = 0 },
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
		-- ["name-realm"] = { gearScore = 0, items = {...}, updatedAt = 0, source = "bridge" }
	},
	reportSnapshots = {
		nextId = 1,
		items = {
			-- { id, savedAt, key, name, realm, message, payload = {...} }
		}
	},
	reportFileQueue = {
		nextId = 1,
		items = {
			-- { id, createdAt, fileName, label, report = {...} }
		}
	},
	savedReportFiles = {
		generatedAt = 0,
		items = {
			-- { fileName, label, createdAt, playerCount, report = {...} }
		}
	},
	raidScanHistory = {
		nextId = 1,
		scans = {
			-- { id, snapshotAt, updatedAt, roster = {...}, summaryPayloads = {...} }
		}
	}
}

RaidInspectorBridgeInbox = {
	-- written by external bridge script, then consumed by addon
	schemaVersion = 1,
	generatedAt = 0,
	results = {
		-- ["name-realm"] = { ...result payload... }
	},
	reportFiles = {
		-- { fileName, label, createdAt, playerCount, report = {...} }
	},
	processedReportQueueIds = { 1, 2, 3 }
}
```

Raid workflow additions:
- raid snapshot queueing (`/ri inspectraid`) with UI snapshot progress
- stale data requeue helper (`/ri refreshstale [minutes]`)

Phase 5 UI additions:
- selectable raid overview list (left panel)
- selected player detail panel with slot-by-slot table (right panel)
- saved detailed report dropdown with live/saved switching
- per-slot audit indicators:
	- enchant status (`E:OK`, `E:MISS`, `E:LOW`)
	- gem fill status (`G:x/y`)
- sort/filter controls in-window and slash command equivalents
- one-click detailed report generation to addon-folder JSON files
- display mode presets:
	- `advanced`
	- `easy`
- quick test-action buttons in-window:
	- `Target`, `Raid`, `Sync`, `Force`, `Stale 15m`, `Status`, `Clear`

Important: this inbox variable is stored in
`WTF/Account/<ACCOUNT>/SavedVariables/RaidInspectorBridge.lua`
(owned by addon `RaidInspectorBridge`).

Note: `/ri sync` imports from the in-memory `RaidInspectorBridgeInbox` table.
If you overwrite `RaidInspectorBridge.lua` while WoW is already running,
you must relog/reload so WoW loads the updated file into memory first.
`/ri sync` only imports when `generatedAt` is newer than the last import.
Use `/ri forcesync` to re-import the current in-memory bridge table anyway.

## Quick Bridge Test
1. Queue a player in game:
	- `/ri inspect Nifang Icecrown`
2. Logout and close WoW to persist SavedVariables safely.
3. Run bridge writer script:
	- `python3 bridge/write_bridge_inbox.py --input-json bridge/sample_result.json --output "<WTF>/Account/<ACCOUNT>/SavedVariables/RaidInspectorBridge.lua"`
4. Start WoW again and inspect status/window:
	- `/ri show`
	- `/ri status`

## Real Queue Fetcher (Warmane API)
Use the queue fetcher to read queued requests from `RaidInspector.lua` and write bridge output automatically.

Example for your current account:
```bash
cd "/media/jatulis/GamesSSD/World of Warcraft 3.3.5a (no install) moded"
/usr/bin/python3 "Interface/AddOns/RaidInspector/bridge/fetch_from_queue.py" \
	--raid-inspector-sv "WTF/Account/SCAVROGUE/SavedVariables/RaidInspector.lua" \
	--bridge-output "WTF/Account/SCAVROGUE/SavedVariables/RaidInspectorBridge.lua" \
	--report-output-dir "Interface/AddOns/RaidInspector/reports" \
	--status-filter queued \
	--max 10
```

Useful flags:
- `--dry-run` : fetch and print JSON, do not write bridge file.
- `--verbose` : print each API URL being fetched.
- `--report-output-dir "Interface/AddOns/RaidInspector/reports"` : where detailed report JSON files are written.
- `--include-raw` : include full Warmane response in the bridge payload.
- `--cache-ttl-minutes 20` : skip fetch for keys with fresh existing addon cache.
- `--retries 2` : retry count for transient network errors.
- `--retry-backoff 1.0` : exponential backoff base seconds.
- `--request-delay 0.2` : minimum delay between outbound HTTP requests.
- `--timeout 20` : set per-request timeout in seconds.
- `--achievements-timeout 20` : timeout for Warmane achievement category checks.
- `--armory-html-timeout 20` : timeout for Warmane HTML enrichment fetch.
- `--skip-armory-html` : disable HTML rel parsing fallback.
- `--item-ilvl-timeout 20` : timeout for item-level lookup pages.
- `--skip-item-ilvl` : disable item-level enrichment fallback.
- `--skip-raid-achievements` : disable ICC/TOC/RS achievement presence checks.
- `--item-ilvl-cache "path/to/item_ilvl_cache.json"` : custom cache path.
- `--cot-url-template "https://.../{name}/{realm}"` : optional Cavern score enrichment endpoint.
- `--cot-overwrite-existing-score` : let Cavern score replace an existing Warmane score.
- `--cot-timeout 20` : timeout for Cavern score lookup.

### Daemon-Like Bridge Loop
For less manual testing, run the loop helper to call the fetcher periodically:

```bash
/usr/bin/python3 "Interface/AddOns/RaidInspector/bridge/daemon_loop.py" \
	--raid-inspector-sv "WTF/Account/SCAVROGUE/SavedVariables/RaidInspector.lua" \
	--bridge-output "WTF/Account/SCAVROGUE/SavedVariables/RaidInspectorBridge.lua" \
	--interval 30 \
	--fetch-args --status-filter all --cache-ttl-minutes 20 --retries 2 --retry-backoff 1.0 --request-delay 0.2 --verbose
```

Use `--once` to run a single cycle using the same wrapper command.

### Bridge Output Additions
The fetcher now enriches each player result with:
- `estimatedGearScore` : fallback estimate (GearScoreLite-style first, avg-ilvl fallback second)
- `issuesCount` : quick count (`missingEnchant + missingGems`)
- `issueSummary` : detailed audit counters:
	- `missingEnchant`
	- `missingGems`
	- `itemsWithoutSlot`
	- `itemsAnalyzed`
	- `itemsWithSockets`
	- `totalSockets`
	- `filledSockets`
- `achievementPoints` : Warmane summary achievement points
- `raidAchievements` : raid-presence flags
	- `icc10`, `icc25`, `toc10`, `toc25`, `rs10`, `rs25`

Current limitation: some Warmane summary responses do not include slot/socket/enchant metadata,
so the fetcher uses an armory HTML enrichment fallback (`rel="item=...&ench=...&gems=..."`) to recover slot/enchant/gem data.
If this HTML format changes, run with `--skip-armory-html` and the bridge will continue in summary-only mode.

When item level is missing in summary data, the fetcher can enrich ilvl by scraping
`https://wotlk.cavernoftime.com/item=<id>` pages and cache results in:
`Interface/AddOns/RaidInspector/bridge/item_ilvl_cache.json`.

### Cavern Score Enrichment Notes
- Cavern integration is optional and endpoint-template based.
- Supported placeholders in `--cot-url-template`:
	- `{name}`, `{realm}`, `{key}` (URL-encoded)
	- `{name_raw}`, `{realm_raw}`, `{key_raw}` (not encoded)
- If Cavern endpoint is unreachable or not JSON, fetch continues and Warmane data is still written.
- In current testing, `https://mop.cavernoftime.com/api` paths returned HTML (not JSON), so no score was extracted automatically from that base path.

### Reliability Hardening (Phase 7)
- Retry + backoff: transient HTTP/network failures are retried (`--retries`, `--retry-backoff`).
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
