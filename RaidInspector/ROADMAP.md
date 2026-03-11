# Raid Inspector Roadmap

## Progress Snapshot (2026-03-10)
- Done:
   - addon skeleton + queue UI
   - request queue commands (`/ri inspect`, `/ri inspecttarget`, `/ri inspectraid`)
   - live in-game inspect pipeline for target and raid units
   - item/enchant UI detail panel
   - save/export report snapshots for later reuse
   - detailed reports saved locally in SavedVariables with in-game dropdown loading
   - current raid scan history with 30-day retention
   - confirmation window before destructive clear actions
   - class colors on overview and selected-player character info
   - bridgeless runtime flow with no sync/import step
- Next:
   - show data source/confidence in UI:
      - overall result source (`local-inspect` vs `saved-report`)
      - gear score source
      - achievement/raid-achievement source
   - optimize loading when character info was gathered recently:
      - prefer fresh cached/local result reuse before re-inspecting
      - avoid unnecessary inspect requests for recently scanned players
   - add selected-player actions in the overview:
      - refresh the selected player directly without having to retarget them
      - remove the selected player from the current scan/queue

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

## Phase 3 - Bridgeless Runtime
1. Resolve slash/manual requests only against active in-game units.
2. Keep queue state aligned with inspectability and range limits.
3. Preserve saved reports purely inside `RaidInspectorDB`.
4. Remove bridge-only UI/help text from the player-facing addon flow.

## Phase 4 - Gear Score and Validation
1. Integrate Cavern of Time scoring rules/API alignment.
2. Compute score from current item list.
3. Add fallback local score computation if API unavailable.
4. Store score breakdown per slot for transparency.

## Phase 5 - UI Features
1. Build main report window:
   - player header (name, class, realm, guild)
   - apply class color styling to character info in header/details
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

## Current Notes
- Main `Report` action now stores a detailed local report for the current overview.
- Saved reports load from SavedVariables directly through the in-game dropdown.
- Remote/name-only inspection is intentionally out of scope on this branch.

## Phase 6 - Raid Workflow
1. Add raid snapshot mode (scan all raid members).
2. Batch enqueue all members for live inspect attempts.
3. Show progress bar for pending fetches.
4. Mark stale data and allow refresh per player.
5. Add selected-entry actions from the overview:
   - refresh one player directly from selection
   - remove one player from the active scan/queue

## Phase 7 - Reliability and Performance
1. Keep inspect throttling and timeout handling stable in raid conditions.
2. Improve refresh behavior for players moving in and out of inspect range.
3. Add cache TTL policy (for example 10-30 minutes).
4. Guard against missing API fields and schema changes.
5. Reuse recently gathered character data when it is still fresh enough to trust.

## Phase 8 - Packaging and Release
1. Add versioning and changelog.
2. Add user documentation for bridgeless limitations and workflow.
3. Test in raid scenarios (10/25 players).
4. Package addon release bundle.

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
2. Live inspect reads one in-range player result.
3. Addon shows item list for that player in a basic frame.
