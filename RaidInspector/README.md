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
- Achievement comparison is currently disabled in this bridgeless build.
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
- `/ri lfm`
- `/ri inspector`
- `/ri post [message]`
- `/ri savereport [name-realm]`
- `/ri sharesaved [latest|id|name-realm]`
- `/ri export` remains as a compatibility alias for `/ri report`
- `/ri exportsaved` remains as a compatibility alias for `/ri sharesaved`
- `/ri status`
- `/ri refreshstale [minutes]`
- `/ri clearqueue [confirm]`
- `/ri ms [on|off]`
- `/ri ms list`
- `/ri ms set <name> <spec>`
- `/ri ms share`
- `/ri ms clear`

## Main Window Actions
- `Target`: inspect the current target immediately.
- `Raid`: queue and inspect current raid members.
- `Share`: send the selected/current summary to chat.
- `Save`: save the selected/current single-player snapshot.
- `Report`: save the full current overview as a detailed local report.
- `Refresh`: attempt live refresh for stale entries that are currently present in target/party/raid.
- `Status`: print runtime status into chat.
- `Clear`: clear queued requests, cached live-inspect results and recorded MS changes.
- `MS: on/off`: start/stop recording MS changes from raid chat.
- `MS Share`: post the recorded MS list to the ticked Share channels.
- `MS Clear`: wipe the recorded MS list (asks to confirm).
- Selected row actions: `Refresh` re-queues a live inspect for that player, `Remove` deletes that player from the live list/cache.
- Right-click a player row to set or edit that player's MS by hand.

## MS Tracking

Raid members call out spec changes in raid chat, and the addon records them.

1. Click `MS: off` so it reads `MS: on` (or `/ri ms on`) when you open the MS-change window.
2. Players type `MS <spec>` in raid or party chat - `MS resto`, `ms heal`, `MS: boomy`, `MS - frost`, `mainspec fury` all work.
3. Click `MS: on` again (or `/ri ms off`) to stop listening once the window closes.

Recorded players show `MS:<spec>` on their overview row in place of `Scanned=<age>`. Use the `MS Changes` sort to bring everyone who changed to the top.

What is deliberately ignored:
- open/close announcements such as `MS CHANGE CLOSE`, `ms close`, `ms open`
- lines where `ms` is not the first word (`anyone need ms?`)
- words that merely start with `ms` (`msg me for inv`)
- a bare `ms` with no spec, and messages containing an item/achievement link

Corrections: right-click a player's row to type their MS by hand, or `/ri ms set <name> <spec>`. Saving an empty box clears that player's MS. Shift+right-click still copies the player's name.

Reporting: `MS Share` (or `/ri ms share`) posts the list to the ticked Share channels, split across several messages when needed. The `RW` checkbox adds Raid Warning as a target and requires raid leader or assistant.

MS records are stored separately from scan results, so rescans, `/reload` and relogging all keep them. They are wiped by `Clear` (along with the queue and results) or by `MS Clear` / `/ri ms clear`, which removes only the MS list and leaves the scan list alone.

Saved reports keep their own copy of the MS. `Save All` writes the recorded MS into the report, and loading it shows the specs from when it was saved - not the current MS list - so clearing or refilling the MS list never rewrites an old report. Reports saved before `0.16.0-alpha` have no MS stored and keep showing the scan age.

## LFM Tab (Initial)
- Use the `LFM` tab to compose your recruitment message.
- Write your post, link an achievement in any chat window, and paste that achievement link into the LFM message box.
- Supported channel checkboxes: `Yell`, `/general`, `/global`.
- Delay dropdown options: `10s`, `20s`, `30s`, `60s`.
- Click `POST` to broadcast the message.
- If multiple channels are selected, posts are sent one-by-one using the selected delay to reduce mute penalty risk.
- A channel status line shows joined/missing state for `/general` and `/global`.
- While the message box is focused, Shift-clicking an achievement link inserts it into your message.

## Saved Data
Detailed reports now stay inside `RaidInspectorDB.savedReportFiles.items` instead of being written to addon-folder JSON files.

Single-player reusable share snapshots stay in `RaidInspectorDB.reportSnapshots.items`.

Raid snapshot history remains in `RaidInspectorDB.raidScanHistory.scans`.

## SavedVariables Shape
```lua
RaidInspectorDB = {
	meta = { schemaVersion = 5, lastLoadedAt = 0 },
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
	},
	msTracking = {
		enabled = false,
		startedAt = 0,
		nextSeq = 1,
		entries = {
			-- ["name-realm"] = { key, name, realm, spec, previousSpec, at, seq, source, changeCount }
		}
	}
}
```

Saved report payloads additionally carry `mainSpec`, `mainSpecAt` and `mainSpecPrevious`, copied from the MS list when the report is saved.

MS records are kept in `RaidInspectorDB.msTracking.entries`, outside `results`, so a rescan never drops them. `Clear` and `MS Clear` wipe them explicitly.

## Bridge Status
Bridge assets were removed from this repository to keep the release branch fully in-game and self-contained.

The addon no longer depends on `RaidInspectorBridge` or bridge-generated SavedVariables files.

## Release Packaging (Phase 8)
Build a release zip that contains only the runtime addon folder (`RaidInspector`).

```bash
cd "Interface/AddOns/RaidInspector"
/usr/bin/python3 "tools/package_release.py"
```

Default output:
- `Interface/AddOns/RaidInspectorRelease/RaidInspector-v<version>.zip`

Optional arguments:
- `--addons-root ".../Interface/AddOns"`
- `--output-dir ".../output/folder"`
- `--version "0.12.2-alpha"`

## Roadmap
Planned work is tracked in `ROADMAP.md`.

Upcoming planning includes a raid composition tab where you can configure target counts for tanks, healers, melee DPS, and ranged DPS, then compare those targets against spec-based roster totals tracked inside the addon. It also includes a chat post composer with a one-line message input, achievement-link support, channel checkboxes (`/1`, `/y`, `/6`, `/7`), and a `POST` button to broadcast to selected channels. Share-summary formatting is also planned to use `Missing Gems (x), Missing Enchants (x)`.
