# Bridge Setup Guide

This guide covers the safe runtime flow and recommended bridge command options.

## 1. Safe Runtime Order
1. Queue players in-game (`/ri inspectraid` or `/ri inspect <name> <realm>`).
2. Fully close WoW.
3. Run `fetch_from_queue.py` from the game root folder.
4. Start WoW.
5. Run `/ri sync` (or `/ri forcesync` if needed).

Important: if WoW is running while bridge files are rewritten, in-memory tables can remain stale.

## 2. Recommended Command
Run from your game root:

```bash
/usr/bin/python3 "Interface/AddOns/RaidInspector/bridge/fetch_from_queue.py" \
  --raid-inspector-sv "WTF/Account/SCAVROGUE/SavedVariables/RaidInspector.lua" \
  --bridge-output "WTF/Account/SCAVROGUE/SavedVariables/RaidInspectorBridge.lua" \
  --report-output-dir "Interface/AddOns/RaidInspector/reports" \
  --status-filter all \
  --max 20 \
  --cache-ttl-minutes 20 \
  --retries 2 \
  --retry-backoff 1.0 \
  --request-delay 0.2 \
  --verbose
```

## 3. Flag Notes
- `--status-filter queued`: fetch only queued requests.
- `--status-filter all`: refresh all tracked keys.
- `--cache-ttl-minutes`: skip network calls for fresh cached keys.
- `--report-output-dir`: directory where detailed report JSON files are written.
- `--retries` and `--retry-backoff`: transient failure retry behavior.
- `--request-delay`: pacing between outbound HTTP requests.
- `--achievements-timeout`: timeout used for raid achievement presence lookups.
- `--skip-raid-achievements`: disable ICC/TOC/RS 10/25 achievement checks.
- `--dry-run`: print resulting payload without writing bridge file.

## 4. Periodic Loop Mode (Daemon-Like)
If you want recurring fetches without retyping commands:

```bash
/usr/bin/python3 "Interface/AddOns/RaidInspector/bridge/daemon_loop.py" \
  --raid-inspector-sv "WTF/Account/SCAVROGUE/SavedVariables/RaidInspector.lua" \
  --bridge-output "WTF/Account/SCAVROGUE/SavedVariables/RaidInspectorBridge.lua" \
  --interval 30 \
  --fetch-args --status-filter all --cache-ttl-minutes 20 --request-delay 0.2 --retries 2 --retry-backoff 1.0 --verbose
```

Use `--once` to execute just one wrapped fetch cycle.

## 5. Quick Troubleshooting
- `No matching requests found.`
: There are no matching requests for current filter.
- `No matching requests found (all candidates skipped by cache TTL).`
: Current cached entries are still fresh under TTL.
- Addon shows old data after bridge run
: restart/reload client then run `/ri sync`.
