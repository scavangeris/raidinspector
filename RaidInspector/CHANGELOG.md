# Changelog

All notable changes to Raid Inspector are documented in this file.

## 0.10.1-alpha - 2026-03-10
- Removed the `super simple` display mode and its dedicated decision UI.
- Export summaries now include talent/spec information.
- Saved snapshot exports rebuild their message from stored payload data, so older saved reports can use the newer export format when talent data exists.

## 0.10.0-alpha - 2026-03-10
- Added `super simple` display mode:
  - new mode selector option alongside `advanced` and `easy`
  - dedicated `Req GS` and `+/-` inputs for simple pass/fail evaluation
  - large `OK` / `NO` decision label above character stats
  - simplified detail panel showing only the pass/fail inputs and reasons
- `super simple` pass rule now requires:
  - player gearscore inside the configured `+/-` range
  - no missing enchants
  - no missing gems
  - no low-tier enchants
- Clear button now uses the confirmation flow instead of bypassing it.

## 0.9.0-alpha - 2026-03-10
- Added report snapshot persistence:
  - `/ri savereport [name-realm]` saves the current or selected report summary into SavedVariables.
  - `/ri export` now also stores a reusable saved snapshot before sending chat output.
  - `/ri exportsaved [latest|id|name-realm]` re-exports a saved snapshot without needing the current overview state.
- Added retained raid scan archive:
  - each `/ri inspectraid` snapshot now writes a roster + summary payload archive entry.
  - history is pruned automatically to 30 days.
- Added safety UX for destructive clear actions:
  - `Clear` button and `/ri clearqueue` now require confirmation by default.
  - `/ri clearqueue confirm` bypasses the popup for explicit confirmation.
- Bumped addon SavedVariables schema to `2` for new persistence fields.

## 0.8.1-alpha - 2026-03-09
- UI layout polish:
  - moved action controls to a compact top-right toolbar
  - prevented overview/detail text overlap behind action buttons
- Added scroll support:
  - overview player list now scrollable (scrollbar + mouse wheel)
  - detail slot/info list now scrollable (scrollbar + mouse wheel)
- Improved in-session GS estimate parity:
  - local inspect now uses GearScoreLite-style estimate first, avg-ilvl fallback second
  - includes item quality in local inspect item model for better score fit
- Improved bridge achievement fetch reliability:
  - stronger AJAX-like headers + flexible response fallback parsing
  - broader achievement points field matching
- Improved bridge GS quality:
  - canonical slot normalization from summary/inventoryType values
  - better chance to produce `estimated-gearscorelite` instead of `estimated-ilvl`
- Added detail slot line colors:
  - green for complete slots
  - red for missing enchant/gems

## 0.8.0-alpha - 2026-03-09
- Improved bridge-side score estimation:
  - added GearScoreLite-aligned fallback scoring from per-slot item data
  - retains avg-ilvl fallback when slot/quality metadata is incomplete
- Added Warmane raid achievement presence enrichment in bridge payload:
  - `raidAchievements.icc10`, `icc25`, `toc10`, `toc25`, `rs10`, `rs25`
  - `achievementPoints` capture in result payload
- Added bridge loop helper script: `bridge/daemon_loop.py` for periodic fetch automation.
- Updated addon UI:
  - top action controls reorganized with grouped color-coded buttons
  - selected-player panel now shows AP and ICC/TOC/RS achievement flags
  - export summary now includes compact ICC25/RS25 flags

## 0.7.2-alpha - 2026-03-09
- Added queue/error reason diagnostics in UI:
  - overview rows now show reason hints for queued/error states
  - detail panel shows reason when no result is available
- Added explicit state reasons for live inspect lifecycle:
  - waiting inspect, inspecting, not inspectable, unit not found, unit changed, timeout

## 0.7.1-alpha - 2026-03-09
- Improved live inspect reliability on 3.3.5a:
  - added polling fallback to complete inspect when `INSPECT_READY` is delayed/missing
  - clears inspect state before each `NotifyInspect` request
  - centralizes inspect success/error finalization

## 0.7.0-alpha - 2026-03-09
- Added in-session live inspect pipeline using WoW inspect API (`INSPECT_READY`):
  - `Target` and `Raid` actions now queue and inspect without restart/reload.
  - Parses item links for itemId, enchantId, gems, socket counts, and ilvl.
  - Computes local issue summary and estimated GS from inspected gear.
- Added inspect queue processor with throttle/timeout handling for raid scans.
- Updated status output to include live inspect queue/activity.

## 0.6.1-alpha - 2026-03-09
- Added in-window test-action buttons to avoid typing slash commands repeatedly:
  - `Target`, `Raid`, `Sync`, `Force`, `Stale 15m`, `Status`, `Clear`
- Updated addon metadata version to `0.6.1-alpha`.

## 0.6.0-alpha - 2026-03-09
- Added Phase 7 bridge hardening:
  - retry + exponential backoff for transient network failures
  - request pacing (`--request-delay`)
  - atomic writes for bridge output and item ilvl cache
  - cache TTL guard (`--cache-ttl-minutes`)
  - resilient handling for non-dict API payloads
- Added bridge fallback that builds item entries from armory `rel` data when summary equipment is missing.
- Added UI quality improvements:
  - off-hand and ranged/relic missing enchant displays `E:OPT`
  - hands slot normalization fixes (`HandsSlot` mapping)
- Completed Phase 5 and Phase 6 roadmap milestones.

## 0.5.0-alpha - 2026-03-09
- Added two-panel raid overview + detail panel UI.
- Added slot-by-slot item detail rendering.
- Added overview sort/filter controls (`/ri sort`, `/ri filter`).
- Added quick chat summary export (`/ri export`).

## 0.4.0-alpha - 2026-03-09
- Added raid snapshot queue command (`/ri inspectraid`).
- Added stale refresh command (`/ri refreshstale [minutes]`).
- Added snapshot progress status in UI and `/ri status`.

## 0.3.0-alpha - 2026-03-09
- Added queue/results foundation window and basic slash commands.
- Added bridge inbox sync flow (`/ri sync`, `/ri forcesync`).

## 0.1.0 - 2026-03-09
- Initial project scaffolding for RaidInspector and bridge storage addon.
