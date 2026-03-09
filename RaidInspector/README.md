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

## Commands
- `/ri help`
- `/ri show`
- `/ri hide`
- `/ri toggle`
- `/ri inspect <name> <realm>`
- `/ri inspect <name-realm>`
- `/ri inspecttarget`
- `/ri sync`
- `/ri forcesync`
- `/ri status`
- `/ri clearqueue`

## SavedVariables Shape
```lua
RaidInspectorDB = {
	meta = { schemaVersion = 1, lastLoadedAt = 0 },
	settings = { window = { point = "CENTER", x = 0, y = 0 } },
	state = { nextRequestId = 1 },
	requests = {
		-- { id, name, realm, key, status, requestedAt, updatedAt }
	},
	results = {
		-- ["name-realm"] = { gearScore = 0, items = {...}, updatedAt = 0, source = "bridge" }
	}
}

RaidInspectorBridgeInbox = {
	-- written by external bridge script, then consumed by addon
	schemaVersion = 1,
	generatedAt = 0,
	results = {
		-- ["name-realm"] = { ...result payload... }
	}
}
```

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
	--status-filter queued \
	--max 10
```

Useful flags:
- `--dry-run` : fetch and print JSON, do not write bridge file.
- `--verbose` : print each API URL being fetched.
- `--include-raw` : include full Warmane response in the bridge payload.
- `--timeout 20` : set per-request timeout in seconds.
- `--cot-url-template "https://.../{name}/{realm}"` : optional Cavern score enrichment endpoint.
- `--cot-overwrite-existing-score` : let Cavern score replace an existing Warmane score.
- `--cot-timeout 20` : timeout for Cavern score lookup.

### Cavern Score Enrichment Notes
- Cavern integration is optional and endpoint-template based.
- Supported placeholders in `--cot-url-template`:
	- `{name}`, `{realm}`, `{key}` (URL-encoded)
	- `{name_raw}`, `{realm_raw}`, `{key_raw}` (not encoded)
- If Cavern endpoint is unreachable or not JSON, fetch continues and Warmane data is still written.
- In current testing, `https://mop.cavernoftime.com/api` paths returned HTML (not JSON), so no score was extracted automatically from that base path.
