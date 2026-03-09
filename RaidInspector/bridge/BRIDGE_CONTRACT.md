# Raid Inspector Bridge Contract

This document defines the external bridge input format used by the addon.

## Why This Exists
WoW addons cannot call external HTTP/HTTPS APIs directly.

Bridge flow:
1. Addon queues characters in `RaidInspectorDB.requests`.
2. External bridge fetches APIs (Warmane/Cavern of Time) outside WoW.
3. Bridge writes a SavedVariables Lua file for inbox data.
4. Addon imports inbox data with `/ri sync` or automatically on login/reload.

## Inbox SavedVariables File
Target file name:
- `RaidInspectorBridge.lua`

Typical path:
- `WTF/Account/<ACCOUNT_NAME>/SavedVariables/RaidInspectorBridge.lua`

The file must define global table `RaidInspectorBridgeInbox`.

This file is owned by addon `RaidInspectorBridge`.

## Required Structure
```lua
RaidInspectorBridgeInbox = {
  ["schemaVersion"] = 1,
  ["generatedAt"] = 1710000000,
  ["results"] = {
    ["name-realm"] = {
      ["name"] = "PlayerName",
      ["realm"] = "Icecrown",
      ["gearScore"] = 6200,
      ["gearScoreSource"] = "cavernoftime",
      ["source"] = "warmane+cot-bridge",
      ["fetchedAt"] = 1710000000,
      ["updatedAt"] = 1710000000,
      ["items"] = {
        -- optional bridge-defined item structures
      },
      ["enchants"] = {
        -- optional bridge-defined enchant structures
      },
      ["gems"] = {
        -- optional bridge-defined gem structures
      },
      ["error"] = nil
    }
  }
}
```

## Key Rules
- `results` keys must be normalized lowercase `name-realm`.
- `schemaVersion` must be numeric and currently `1`.
- `fetchedAt`/`updatedAt` should be unix timestamps (seconds).
- If bridge fails for a player, set `error` to a string and still provide `name` and `realm`.
- Addon clears `RaidInspectorBridgeInbox.results` after import.

## Import Behavior In Addon
- On login/reload: addon auto-imports inbox results.
- Manual command: `/ri sync`.
- Imported rows update:
  - `RaidInspectorDB.results[key]`
  - matching request status -> `ready` (or `error` when `error` field exists)

## Recommended Dev Cycle
1. In game: queue character with `/ri inspect Name Realm`.
2. Logout and close WoW so SavedVariables are written to disk.
3. Run bridge and write `RaidInspectorBridge.lua`.
4. Start WoW again (addon auto-imports inbox on login), then verify with `/ri show` or `/ri status`.
