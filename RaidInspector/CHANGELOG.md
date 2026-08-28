# Changelog

All notable changes to Raid Inspector are documented in this file.

## Unreleased
- Raid achievement check on inspected players. The detail panel now shows `ICC10 / ICC25 / RS10 / RS25` with a green check or a red X next to each, read live from the player you inspected. It uses the game's own achievement comparison, so it needs nothing outside the client and no bridge - the same requirement as gear: the player has to be inspectable. A raid nobody has scanned shows `?` rather than a red X, because "not scanned" and "has not killed it" are different answers. `/ri ach` prints the achievement IDs the build looks up so they can be verified in-game at a glance.
- MS changes are now picked up from say and whisper as well as raid and party chat, so a player can send their spec privately or from right next to you instead of only in raid chat. Whispers work even if they are not in the raid yet. Only incoming whispers count, so your own never register, and nothing is recorded at all while registering is off.
- The row's chat line now names the channel for a whispered or said MS, since those are easy to miss in a busy chat frame.
- The toggle-on announcement is now `MS changes now!: MS xxx`, so the call to action carries the format players should type.
- The `? Info` help window no longer runs off its frame. The text had grown past the fixed dialog and was spilling off the top and behind the Close button; it now sits in a scrollable panel (mouse wheel works) and the dialog is capped to the screen height.

## 0.16.1-alpha - 2026-08-03
- Fixed a scan/retry loop. A player who had already been scanned - standing right next to you - would flip to `out of range, retrying`, get re-scanned, and repeat every few seconds. Autoscan was re-queueing the whole raid on every pass, and an inspect that comes back with no items (as much a timing race as a real out-of-range unit) was being recorded as a failed attempt, which the retry sweep then picked up again.
- Once a player's gear has been collected they are no longer re-inspected on their own at all. Autoscan still watches the roster and scans anyone who joins, but skips people it already has gear for. Re-scanning is now always deliberate: the row `Refresh` button, the `Raid` button, or `/ri refreshstale`.
- An empty re-read on someone whose gear is already stored no longer disturbs their row - the gear and the `ready` status both stay put, so nothing flickers. Players with no GS are still retried automatically until a scan lands.

## 0.16.0-alpha - 2026-08-03
- Fixed gear disappearing when a player walked out of range after being scanned. An inspect on someone who has drifted away still reports success, but hands back no items at all, and that empty result was being written straight over the good scan - the row kept saying `ready` while the item list, GS and audit all went blank. A scan that returns no gear no longer replaces gear that is already stored.
- Players who leave or are kicked are now removed from the list as soon as the roster changes, instead of only while Autoscan was on. Only players who were actually seen in your group are removed this way - anyone added by hand with `/ri inspect` stays - and leaving the raid yourself still keeps the whole list.

- New MS tracking. Raid members announce a spec change the way they already do - by typing `MS resto` in raid chat - and the addon records it against whoever typed it. Recording is gated behind a new `MS: on/off` button (and `/ri ms on|off`), so it only listens during the MS-change window and ignores everything said before or after. `ms heal`, `MS: boomy`, `MS - frost`, `mainspec fury` and `main spec disc` all register; `msg me for inv`, a bare `ms`, an `ms` in the middle of a sentence, and a pasted item link do not.
- The leader's own announcements are not mistaken for a spec: `MS CHANGE CLOSE`, `ms close`, `ms open` and similar open/close calls are recognised as control messages and never stored as somebody's main spec. The same applies to the loot chatter that fills that window - `MS > OS`, `ms only`, `ms rolls first`, `ms or os?` are all ignored.
- `MS Share` output is not read back in as data. The posted list starts with "MS changes", which would otherwise be picked up by the addon's own chat hook and stored as the sharer's main spec, then re-posted and re-recorded on every share.
- Anything typed by hand - through the right-click box or `/ri ms set` - goes through the same checks as a chat line, so a pasted colour code or a very long line cannot corrupt the row display or the outgoing chat message. Non-Latin specs are kept intact and are never cut in the middle of a character.
- A recorded MS replaces the scan age on that player's row, so the row reads `MS:resto` in gold instead of `Scanned=4m`. Players with no recorded MS still show their scan age as before.
- MS records live in their own list, separate from the scan results, so rescans, `/reload` and logging out all keep them. `Clear` wipes them along with the queue and results, and the new `MS Clear` button (or `/ri ms clear`) wipes only the MS list and leaves the scan list alone. Both ask to confirm.
- New `MS Share` button posts the whole recorded list to the ticked Share channels, split across as many messages as it takes to stay under the chat length limit.
- New `RW` Share channel for Raid Warning, next to Raid/Say/Whisper/Guild. It applies to normal shares too, and tells you when you are not raid leader or assistant instead of silently dropping the message.
- Toggling MS registering now announces it to the raid, so opening the window is a single click. Turning it on sends `MS CHANGES IN RAID CHAT NOW: MS blabla` and turning it off sends `MS CHANGE CLOSED`, both as a raid warning - or as normal raid chat if you are not leader or assistant, so the call still goes out. Nothing is sent when you are not in a raid, and flipping the toggle to the state it is already in never re-announces.
- New `MS Changes` sort mode: everyone who announced a spec change floats to the top, most recent first.
- `Save All` now stores the recorded MS with the report, and loading that report shows the specs it was saved with rather than whatever is in the current MS list - so a report stays a true snapshot of that raid even after the MS list is cleared or refilled. Single-player saves and the shared summary line carry it too (`MS: resto`). Reports saved before this version simply have no MS and keep showing the scan age.
- Right-clicking a player row now opens a small box to set or correct that player's MS by hand, for people who never typed it or typed it wrong. Saving an empty box clears their MS. Copying a player's name moved to shift+right-click, matching how the gear rows already work.
- Also available from chat: `/ri ms` (toggle), `/ri ms list`, `/ri ms set <name> <spec>`, `/ri ms share`, `/ri ms clear`.

## 0.15.0-alpha - 2026-07-27
- New gear preview window. Every list row that has scanned gear now shows a small armor icon on the right; click it to open a character-panel-style window with that player's equipment laid out in slots. Each slot shows the item icon with a quality-colored border, and hovering a slot shows the full item tooltip (name, enchant, gems, stats) just like the in-game character/inspect screen. It reads from the gear RaidInspector has stored, so it works for saved reports and for players who are offline or have left the raid - no re-inspect needed. The window is movable and closes with Escape.
- In the gear preview, any slot that is missing an enchant it should have, or that has an empty gem socket, is flagged with a red icon (matching the same rule as the Issues filter), so gaps are obvious at a glance. Slots that are fine keep their normal icon and quality-colored border.
- Right-clicking an item slot in the gear preview opens that item in AtlasLoot (shift+right-click copies its name instead), the same as right-clicking a row in the gear detail list.
- Fixed players showing as `ready` when their inspect had actually failed. If someone had been scanned before, a later failed scan (out of range, timeout, unit gone) left the row reading `ready` with no hint that the gear on screen was from the earlier scan - the data was stale but looked current. Failed scans are now always reported as such: the row shows `[error]` with the reason and the scan age, while the previously cached gear stays on screen instead of being thrown away.
- Fixed the automatic retry skipping the players who needed it most. The 15-second retry sweep ignored anyone who already had a cached result, so a player whose data had gone stale was never re-inspected even though the overview said "retrying". Stale entries are now retried as promised and refresh themselves as soon as the player is inspectable. Players who scanned successfully are still never re-queued, and out-of-range players are still skipped until they are actually inspectable, so this does not add inspect traffic.

## 0.14.0-alpha - 2026-07-16
- Players who are out of range are no longer written off. Anyone who fails to inspect for a temporary reason (not inspectable / unit not found / unit changed / inspect timeout) is now retried automatically every 15 seconds until they come into range and get inspected. Only players who are inspectable at that moment are re-queued, so retries never waste a queue slot, and the overview now reads "not inspectable, retrying" instead of looking final.
- New `Autoscan` toggle button on the Inspector tab (next to `Raid`). While it is on, the raid is rescanned automatically: once whenever someone joins or leaves the raid, and every 10 seconds once the inspect queue has drained, so it never fights work already in flight. The setting is saved per character and can also be driven from chat with `/ri autoscan [on|off]`.
- Autoscan keeps the list in sync with the raid: anyone who leaves is removed from the list automatically, along with their queued inspect and cached result. Leaving the raid yourself does not wipe the list. The manual `Raid` button is unaffected and never removes anything.
- Autoscan rescans are quiet - they do not print a scan summary every 10 seconds, and they keep updating the current raid history entry while the roster is unchanged instead of appending a new entry per scan.
- Fixed the version shown on login: the addon printed `loaded (0.12.2-alpha)` regardless of the actual release.

## 0.13.0-alpha - 2026-06-28
- Overview rows: replaced the text Refresh/Remove buttons with small square icon buttons (refresh arrow + red X, with tooltips).
- Replaced the Sort toggle button with a Sort dropdown (Recent / GS / Issues / Name) on its own row.
- Gear detail list is now a fixed-column table (Slot | Item Name | iLvl | Enchant | Gems) with a header row; long item names are shortened with an ellipsis to fit the column.
- Added an Options window (button next to ? Info): a window-scale slider (0.5-1.5) and PallyPower-style keybinds for Target / Raid / Share / Save All / Clear (click Set, press a key; applied as override bindings, saved per character).
- LFM presets: save the current message + Need table as a named preset, pick it from a dropdown to reload, and delete it with the X. Save Template / Import / Export buttons under the Need table. Export sends the preset to another player over addon comms (hex-encoded so achievement-link characters survive, chunked to fit, and broadcast over whisper + guild + party/raid with a recipient filter so it still arrives when the server blocks whisper addon messages). The receiver clicks Import to open a list of all pending templates (name + sender) and can Accept or Decline each one individually, or Accept All / Decline All. Re-sends of the same preset from the same sender replace the earlier copy, and channel duplicates are de-duped.

## 0.12.9-alpha - 2026-06-28
- Share summary now includes a `PvP Items: N` count (from resilience detection).
- Reduced the empty gap between the tab row and the Share row on the Inspector tab.

## 0.12.8-alpha - 2026-06-28
- LFM: replaced the single "Clear" button with per-field clear buttons - a small `X` next to the message box and one at the end of each Need row (Tank/Healer/Melee/Ranged).
- PvP detection reworked to be reliable: resilience is now found via a pattern match over `GetItemStats` keys plus a hidden-tooltip scan fallback, so PvP gear is correctly flagged orange with a `PVP` tag, `pvp=N` in the audit line, and an orange player name.
- Achievements can now be linked into the focused LFM box directly from the Achievement window: on this client that shift-click routes to the achievement tracking toggle (the "already completed" message), so `AchievementButton_ToggleTracking` is now intercepted while the LFM box is focused and inserts the achievement link instead. The previous "link via chat" method still works.

## 0.12.7-alpha - 2026-06-28
- Added a `Clear` button to the LFM tab that wipes the message and the Need table (channels/delay/repeat are kept).
- PvP gear detection: equipped items with a resilience stat are now flagged. The gear line is shown orange with a `PVP` tag, the audit line shows `pvp=N`, and a player with any PvP item has their name coloured orange in the overview and the selected header.
- Achievements can now be linked straight from the Achievement window into the focused LFM message box (hooked `HandleModifiedItemClick`, not just `ChatEdit_InsertLink`).

## 0.12.6-alpha - 2026-06-28
- Removed the live-overview status counts line (Queue/Ready/Fresh/Stale/Issues/Errors) from the Inspector tab.
- Player names no longer show the `-Realm` suffix in the overview list and the selected-player header.
- Added a `? Info` button (next to the tabs) that opens a help dialog explaining the buttons and mouse actions.
- Enlarged the window again (1100x560 -> 1180x610) and increased gear-list / overview row spacing and font size for readability.
- Removed the `Save One` button (use `Save All`; `/ri savereport` still saves a single selected player from chat).

## 0.12.5-alpha - 2026-06-28
- Removed the Advanced/Easy mode dropdown; the window now always uses the easy layout.
- Inspector action buttons: removed the Filter (`F:all`) and Status/Display buttons from the window (their `/ri filter` and `/ri status` slash commands still work). Renamed `Report` to `Save All` and `Save` to `Save One`.
- Added a `Guild` checkbox to the Share row (Inspector tab) so summaries/reports can be sent to guild chat (`SendSummaryMessage` now supports GUILD).
- Enlarged the main window (1000x500 -> 1100x560) and increased the visible overview rows and item-detail rows to use the extra space.
- `/ri` with no argument now opens the window (same as `/ri show`); `/ri help` shows the command list.

## 0.12.4-alpha - 2026-06-27
- Right-click a gear/item row in the detail panel now opens that item in AtlasLoot (search view); falls back to the copy dialog if AtlasLoot is not loaded. Shift+right-click still copies the item value. Added `## OptionalDeps: AtlasLoot`.
- Reworked the LFM "Need" picker: replaced the class/spec checkbox grid with a compact role table (Tank / Healer / Melee / Ranged), each row with a "Need" count box and a free-text "Class" box (e.g. `mage, boomy`). Output reads e.g. `NEED: 1 Melee (mage, boomy)`.
- LFM delay is now a typed numeric input (1-3600s) instead of a fixed dropdown; applied and saved on POST.
- Added an LFM "Repeat" input: the whole broadcast is queued repeat x channels times, each post spaced by the delay.
- Added an LFM "Cancel" button (and `/ri cancel`) to clear any pending posts.
- Added a `/guild` channel checkbox to the LFM "Post To" row (posts to GUILD when you are in a guild).

## 0.12.3-alpha - 2026-06-27
- Added right-click-to-copy in the main window:
  - right-click a player row in the overview to copy that character's name
  - right-click a gear/item row in the selected-player detail panel to copy the item name
  - both open a small movable dialog with a pre-selected, focused EditBox (press Ctrl+C to copy, Esc to close), since 3.3.5a has no direct clipboard API
  - left-clicking an overview row still selects the player as before

## 0.12.2-alpha - 2026-03-17
- Removed unused bridge import code from `RaidInspector.lua` in bridgeless mode.
- Removed legacy bridge assets from the repository:
  - deleted `RaidInspector/bridge/*`
  - deleted `RaidInspectorBridge/*`
- Updated release packaging script to build a zip containing only `RaidInspector/`.
- Updated release docs for a single-addon install path (drop `RaidInspector` into `Interface/AddOns`).

## 0.12.1-alpha - 2026-03-12
- Added initial `LFM` tab in the main window:
  - message input field for manual LFM post composition
  - channel checkboxes for `Yell`, `/general`, and `/global`
  - delay dropdown (`10s`, `20s`, `30s`, `60s`) for staggered posting control
  - `POST` button to broadcast the typed message to all selected channels
  - selected channels post in sequence using the selected delay to reduce mute penalty risk
  - live channel status indicator for `Yell`, `/general`, and `/global` availability
- Improved composition role interpretation for druid feral:
  - `Thick Hide` fully ranked => `Feral Tank`
  - otherwise => `Feral DPS` (counted as MDPS)
- Added more specific interpretation for other ambiguous specs:
  - DK `Blood` uses key talents to label `Blood Tank` vs `Blood DPS`
  - Paladin `Protection` uses key talents to label `Protection Tank` vs `Protection DPS`
  - Paladin `Holy` healer markers label `Holy Healer` vs `Holy DPS`
- Added slash helpers for tab/post flow:
  - `/ri lfm`
  - `/ri inspector`
  - `/ri post [message]`
- Added Shift-click link insertion support for the focused LFM message box (achievement links can be inserted directly).

## 0.12.0-alpha - 2026-03-10
- Added bridgeless branch behavior for fully in-game use:
  - removed bridge import from login/runtime flow
  - disabled `/ri sync` and `/ri forcesync` with an in-game guidance message
  - manual `/ri inspect` now only queues players that exist in current target/party/raid context
- Reworked detailed reports to stay fully in SavedVariables:
  - `Report` now saves the current overview directly into the addon database
  - saved-report dropdown loads those local reports without external files or bridge sync
  - existing queued report-file payloads are migrated into local saved reports on load
- Updated the main window for local-only workflow:
  - `Sync` button becomes `Share`
  - `Force` button becomes `Save`
  - `Stale` button is relabeled `Refresh`
  - status/detail text now describes live inspect instead of bridge usage

## 0.11.0-alpha - 2026-03-10
- Renamed the main `Export` action to `Report` and repurposed it for detailed roster reports.
- Added bridge-backed report file export:
  - queues a full multi-player report from the current overview
  - writes timestamped JSON files into `Interface/AddOns/RaidInspector/reports/`
  - preserves item, enchant, gem, GS, talent/spec, and audit data per player
- Added in-game saved report loading:
  - new saved-report dropdown in the main window
  - bridge sync imports a catalog of saved report files back into the addon
  - selecting a saved report loads it into the existing overview/detail panels
- Added slash-command updates:
  - `/ri report`
  - `/ri loadreport [latest|filename]`
  - `/ri share [name-realm]`
  - `/ri sharesaved [latest|id|name-realm]`
  - `/ri export` remains as a compatibility alias for `/ri report`

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
