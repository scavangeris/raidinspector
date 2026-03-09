#!/usr/bin/env python3
"""
Generate RaidInspectorBridgeInbox.lua from JSON or CLI arguments.

Examples:
  python write_bridge_inbox.py \
    --input-json sample_result.json \
        --output "/path/to/WTF/Account/YourAccount/SavedVariables/RaidInspectorBridge.lua"

  python write_bridge_inbox.py \
    --name Nifang --realm Icecrown --gear-score 6201 \
        --output "/path/to/WTF/Account/YourAccount/SavedVariables/RaidInspectorBridge.lua"
"""

import argparse
import json
import pathlib
import time
from typing import Any, Dict, List


def make_key(name: str, realm: str) -> str:
    return f"{name}-{realm}".lower()


def lua_quote(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    return f'"{escaped}"'


def to_lua(value: Any, indent: int = 0) -> str:
    pad = " " * indent
    child = " " * (indent + 2)

    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return lua_quote(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        lines = ["{"]
        for item in value:
            lines.append(f"{child}{to_lua(item, indent + 2)},")
        lines.append(f"{pad}}}")
        return "\n".join(lines)
    if isinstance(value, dict):
        if not value:
            return "{}"
        lines = ["{"]
        for key in sorted(value.keys(), key=lambda x: str(x)):
            lines.append(f"{child}[{lua_quote(str(key))}] = {to_lua(value[key], indent + 2)},")
        lines.append(f"{pad}}}")
        return "\n".join(lines)

    return lua_quote(str(value))


def normalize_results(
    raw: Any,
    generated_at: int,
    preserve_input_timestamps: bool,
) -> Dict[str, Dict[str, Any]]:
    if isinstance(raw, dict) and "results" in raw:
        entries = raw["results"]
    elif isinstance(raw, list):
        entries = raw
    elif isinstance(raw, dict):
        entries = [raw]
    else:
        raise ValueError("Unsupported input format for results")

    if not isinstance(entries, list):
        raise ValueError("results must be a list")

    out: Dict[str, Dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict):
            continue

        name = str(entry.get("name", "")).strip()
        realm = str(entry.get("realm", "")).strip()
        if not name or not realm:
            continue

        key = make_key(name, realm)
        result = dict(entry)
        result.setdefault("name", name)
        result.setdefault("realm", realm)
        result.setdefault("source", "bridge-script")

        if preserve_input_timestamps:
            result.setdefault("fetchedAt", generated_at)
            result.setdefault("updatedAt", generated_at)
        else:
            result["fetchedAt"] = generated_at
            result["updatedAt"] = generated_at

        out[key] = result

    return out


def build_from_cli(args: argparse.Namespace, generated_at: int) -> Dict[str, Dict[str, Any]]:
    if not args.name or not args.realm:
        raise ValueError("--name and --realm are required when --input-json is not used")

    key = make_key(args.name, args.realm)
    result: Dict[str, Any] = {
        "name": args.name,
        "realm": args.realm,
        "gearScore": args.gear_score,
        "gearScoreSource": args.gear_score_source,
        "source": args.source,
        "fetchedAt": generated_at,
        "updatedAt": generated_at,
        "items": [],
        "enchants": {},
        "gems": {},
    }

    return {key: result}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Write RaidInspectorBridge.lua (containing RaidInspectorBridgeInbox)")
    parser.add_argument("--output", required=True, help="Output path for RaidInspectorBridgeInbox.lua")
    parser.add_argument("--input-json", help="JSON file with a result object or results list")
    parser.add_argument("--name", help="Character name (fallback mode)")
    parser.add_argument("--realm", help="Realm name (fallback mode)")
    parser.add_argument("--gear-score", type=int, default=0, help="Gear score for fallback mode")
    parser.add_argument("--gear-score-source", default="cavernoftime", help="Score source label")
    parser.add_argument("--source", default="bridge-script", help="Bridge source label")
    parser.add_argument(
        "--preserve-input-timestamps",
        action="store_true",
        help="Keep fetchedAt/updatedAt values from input JSON (default overrides with current time)",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    generated_at = int(time.time())

    if args.input_json:
        data = json.loads(pathlib.Path(args.input_json).read_text(encoding="utf-8"))
        results = normalize_results(data, generated_at, args.preserve_input_timestamps)
    else:
        results = build_from_cli(args, generated_at)

    inbox = {
        "schemaVersion": 1,
        "generatedAt": generated_at,
        "results": results,
    }

    lua_payload = to_lua(inbox)
    text = "RaidInspectorBridgeInbox = " + lua_payload + "\n"

    output_path = pathlib.Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(text, encoding="utf-8")

    print(f"Wrote {len(results)} result(s) to: {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
