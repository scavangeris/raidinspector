# Raid Inspector Roadmap

## Progress Snapshot (2026-03-10)
- Done:
   - addon skeleton + queue UI
   - request queue commands (`/ri inspect`, `/ri inspecttarget`)
   - bridge inbox ingestion (`/ri sync`, auto import on login/reload)
   - bridge contract + sample writer script
   - real queue fetcher script (`bridge/fetch_from_queue.py`) using Warmane summary API
   - optional Cavern score enrichment in fetcher via `--cot-url-template`
   - bridge parser for real Warmane summary payload
   - item/enchant UI detail panel
   - save/export report snapshots for later reuse
   - current raid scan history with 30-day retention
   - confirmation window before destructive clear actions
- Next:
   - set class colors on character info (color values TBD; to be provided later)

## Phase 1 - Foundation
1. Define data contract between addon and bridge.
2. Finalize SavedVariables schema:
   - request queue (characters to inspect)
   - fetched data cache (per realm/player)
   - timestamps and API errors
3. Build minimal addon UI shell:
   - slash commands (`/ri`)
   - simple status frame
   - data freshness indicator

## Phase 2 - Addon Data Pipeline
1. Add inspect target capture:
   - selected unit name
   - raid roster scan
   - manual entry mode (`/ri inspect Name-Realm`)
2. Push requests into queue in SavedVariables.
3. Add cache read layer and normalize displayed player key format.
4. Show pending/ready/error state per player.

## Phase 3 - External Bridge (Required)
1. Create standalone bridge app (Python or Node.js).
2. Watch/addon request queue from SavedVariables file.
3. Fetch Warmane summary endpoint:
   - example: `https://armory.warmane.com/api/character/<name>/<realm>/summary`
4. Parse gear list, gems, enchants, talents, class/spec info.
5. Map items for score calculation endpoint compatibility.
6. Write merged result back to SavedVariables output section.

## Phase 4 - Gear Score and Validation
1. Integrate Cavern of Time scoring rules/API alignment.
2. Compute score from current item list.
3. Add fallback local score computation if API unavailable.
4. Store score breakdown per slot for transparency.

## Phase 5 - UI Features
1. Build main report window:
   - player header (name, class, realm, guild)
   - apply class color styling to character info in header/details (exact palette pending)
   - total score and confidence/source
   - slot-by-slot item table
2. Add enchant/gem audit indicators:
   - missing enchant
   - low-tier enchant
   - missing gem
3. Add sort/filter controls for raid overview.
4. Add quick export to chat (short summary format).
5. Keep display mode presets:
   - `advanced`
   - `easy`

## Phase 6 - Raid Workflow
1. Add raid snapshot mode (scan all raid members).
2. Batch enqueue all members to bridge.
3. Show progress bar for pending fetches.
4. Mark stale data and allow refresh per player.

## Phase 7 - Reliability and Performance
1. Add rate limiting and retry logic in bridge.
2. Add corruption-safe file writes for SavedVariables.
3. Add cache TTL policy (for example 10-30 minutes).
4. Guard against missing API fields and schema changes.

## Phase 8 - Packaging and Release
1. Add versioning and changelog.
2. Add user documentation and setup guide for bridge.
3. Test in raid scenarios (10/25 players).
4. Package addon + bridge release bundle.

## Phase 9 - Persistence and Safety UX
1. Add save/export workflow for generated reports:
   - persist report snapshots to SavedVariables
   - export latest or selected snapshot to chat/text format
2. Add current raid scan archive with retention policy:
   - store scan timestamp + roster + summary payload
   - keep 30 days of history, prune older records automatically
3. Add confirmation dialog for clear actions:
   - prompt before `Clear` / `clearqueue`
   - include explicit confirm/cancel actions

## Suggested First Build Milestone
1. `/ri inspect <name>` creates queue entry.
2. Bridge reads queue and writes one player result.
3. Addon shows item list for that player in a basic frame.
