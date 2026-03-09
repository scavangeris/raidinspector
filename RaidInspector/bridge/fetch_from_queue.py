#!/usr/bin/env python3
"""
Fetch queued RaidInspector requests from SavedVariables and write bridge inbox.

Usage example:
  python3 fetch_from_queue.py \
    --raid-inspector-sv "WTF/Account/SCAVROGUE/SavedVariables/RaidInspector.lua" \
    --bridge-output "WTF/Account/SCAVROGUE/SavedVariables/RaidInspectorBridge.lua" \
    --max 5
"""

from __future__ import annotations

import argparse
import json
import pathlib
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import urlparse
from typing import Any, Dict, List, Optional


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


def find_table_block(text: str, marker: str) -> Optional[str]:
    marker_index = text.find(marker)
    if marker_index < 0:
        return None

    start = text.find("{", marker_index)
    if start < 0:
        return None

    depth = 0
    for i in range(start, len(text)):
        ch = text[i]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start : i + 1]

    return None


def split_top_level_tables(table_text: str) -> List[str]:
    body = table_text[1:-1]
    out: List[str] = []
    depth = 0
    start = -1

    for i, ch in enumerate(body):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start >= 0:
                out.append(body[start : i + 1])
                start = -1

    return out


def parse_field_str(block: str, key: str) -> Optional[str]:
    match = re.search(rf'\["{re.escape(key)}"\]\s*=\s*"([^"]*)"', block)
    return match.group(1) if match else None


def parse_field_int(block: str, key: str) -> Optional[int]:
    match = re.search(rf'\["{re.escape(key)}"\]\s*=\s*(\d+)', block)
    if not match:
        return None
    return int(match.group(1))


def parse_requests(saved_variables_path: pathlib.Path) -> List[Dict[str, Any]]:
    text = saved_variables_path.read_text(encoding="utf-8", errors="replace")
    requests_block = find_table_block(text, '["requests"] = {')
    if not requests_block:
        return []

    out: List[Dict[str, Any]] = []
    for entry in split_top_level_tables(requests_block):
        name = parse_field_str(entry, "name")
        realm = parse_field_str(entry, "realm")
        key = parse_field_str(entry, "key")
        status = parse_field_str(entry, "status") or "queued"
        req_id = parse_field_int(entry, "id")

        if not name or not realm:
            continue

        normalized_key = (key or f"{name}-{realm}").lower()
        out.append(
            {
                "id": req_id,
                "name": name,
                "realm": realm,
                "key": normalized_key,
                "status": status,
            }
        )

    return out


def dedupe_requests(requests: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    out: List[Dict[str, Any]] = []
    for req in requests:
        if req["key"] in seen:
            continue
        seen.add(req["key"])
        out.append(req)
    return out


def make_summary_url(name: str, realm: str) -> str:
    q_name = urllib.parse.quote(name, safe="")
    q_realm = urllib.parse.quote(realm, safe="")
    return f"https://armory.warmane.com/api/character/{q_name}/{q_realm}/summary"


def make_cot_url(template: str, name: str, realm: str, key: str) -> str:
    values = {
        "name": urllib.parse.quote(name, safe=""),
        "realm": urllib.parse.quote(realm, safe=""),
        "key": urllib.parse.quote(key, safe=""),
        "name_raw": name,
        "realm_raw": realm,
        "key_raw": key,
    }
    return template.format(**values)


def extract_cot_gearscore(cot_payload: Any) -> Optional[int]:
    value = find_first_value(
        cot_payload,
        [
            "gearScore",
            "gearscore",
            "gs",
            "score",
            "totalGearScore",
            "overallGearScore",
            "characterGearScore",
        ],
    )
    return as_int(value)


def http_get_json(url: str, timeout: float) -> Dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": "RaidInspectorBridge/0.1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        payload = response.read().decode(charset, errors="replace")
    return json.loads(payload)


def http_get_json_flexible(url: str, timeout: float) -> Any:
    # Some endpoints require browser-like headers or return JSON wrapped in extra text.
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            "Accept": "application/json,text/plain,*/*",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        payload = response.read().decode(charset, errors="replace")

    payload = payload.strip()
    if not payload:
        raise ValueError("empty response body")

    try:
        return json.loads(payload)
    except json.JSONDecodeError:
        pass

    start_obj = payload.find("{")
    end_obj = payload.rfind("}")
    if start_obj >= 0 and end_obj > start_obj:
        snippet = payload[start_obj : end_obj + 1]
        try:
            return json.loads(snippet)
        except json.JSONDecodeError:
            pass

    start_arr = payload.find("[")
    end_arr = payload.rfind("]")
    if start_arr >= 0 and end_arr > start_arr:
        snippet = payload[start_arr : end_arr + 1]
        try:
            return json.loads(snippet)
        except json.JSONDecodeError:
            pass

    raise ValueError("response is not valid JSON")


def find_first_value(data: Any, key_candidates: List[str]) -> Any:
    want = {k.lower() for k in key_candidates}
    queue: List[Any] = [data]
    seen = 0

    while queue and seen < 20000:
        current = queue.pop(0)
        seen += 1

        if isinstance(current, dict):
            for k, v in current.items():
                if isinstance(k, str) and k.lower() in want:
                    return v
            for v in current.values():
                if isinstance(v, (dict, list)):
                    queue.append(v)
        elif isinstance(current, list):
            for v in current:
                if isinstance(v, (dict, list)):
                    queue.append(v)

    return None


def as_int(value: Any) -> Optional[int]:
    if value is None:
        return None
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, float):
        return int(value)
    if isinstance(value, str):
        value = value.strip()
        if value.isdigit():
            return int(value)
    return None


def extract_gems(raw_item: Dict[str, Any]) -> List[int]:
    gem_values = None
    for key in ["gems", "gemIds", "socketedGems", "sockets"]:
        if key in raw_item:
            gem_values = raw_item[key]
            break

    if gem_values is None:
        return []

    gems: List[int] = []
    if isinstance(gem_values, list):
        for entry in gem_values:
            if isinstance(entry, dict):
                gem_id = as_int(entry.get("id") or entry.get("itemId") or entry.get("gem"))
            else:
                gem_id = as_int(entry)
            if gem_id:
                gems.append(gem_id)
    elif isinstance(gem_values, dict):
        for entry in gem_values.values():
            gem_id = as_int(entry.get("id") if isinstance(entry, dict) else entry)
            if gem_id:
                gems.append(gem_id)

    return gems


def normalize_item(raw_item: Dict[str, Any], slot_hint: Optional[str]) -> Optional[Dict[str, Any]]:
    item_id = as_int(
        raw_item.get("itemId")
        or raw_item.get("id")
        or raw_item.get("entry")
        or raw_item.get("item")
    )
    item_name = raw_item.get("name") or raw_item.get("itemName")
    item_level = as_int(raw_item.get("itemLevel") or raw_item.get("ilvl") or raw_item.get("level"))
    enchant_id = as_int(
        raw_item.get("enchant")
        or raw_item.get("enchantId")
        or raw_item.get("permanentEnchant")
    )
    slot = (
        slot_hint
        or raw_item.get("slot")
        or raw_item.get("slotName")
        or raw_item.get("inventoryType")
    )
    gems = extract_gems(raw_item)

    if not any([item_id, item_name, item_level, enchant_id, gems]):
        return None

    out: Dict[str, Any] = {}
    if slot:
        out["slot"] = str(slot)
    if item_id:
        out["itemId"] = item_id
    if item_name:
        out["name"] = str(item_name)
    if item_level:
        out["ilvl"] = item_level
    if enchant_id:
        out["enchantId"] = enchant_id
    if gems:
        out["gems"] = gems
    return out


def extract_items(summary: Dict[str, Any]) -> List[Dict[str, Any]]:
    equip = find_first_value(summary, ["equipment", "gear", "items", "equippedItems", "itemList"])
    if equip is None:
        return []

    out: List[Dict[str, Any]] = []

    if isinstance(equip, list):
        for raw_item in equip:
            if isinstance(raw_item, dict):
                normalized = normalize_item(raw_item, None)
                if normalized:
                    out.append(normalized)
    elif isinstance(equip, dict):
        for slot, raw_item in equip.items():
            if isinstance(raw_item, dict):
                normalized = normalize_item(raw_item, str(slot))
                if normalized:
                    out.append(normalized)

    return out


def items_to_maps(items: List[Dict[str, Any]]) -> Dict[str, Dict[str, Any]]:
    enchants: Dict[str, int] = {}
    gems: Dict[str, List[int]] = {}

    for item in items:
        slot = item.get("slot")
        if not slot:
            continue
        if "enchantId" in item:
            enchants[str(slot)] = int(item["enchantId"])
        if "gems" in item and item["gems"]:
            gems[str(slot)] = [int(g) for g in item["gems"]]

    return {"enchants": enchants, "gems": gems}


def make_result(
    name: str,
    realm: str,
    now: int,
    summary: Optional[Dict[str, Any]],
    source: str,
    include_raw: bool,
    error: Optional[str] = None,
) -> Dict[str, Any]:
    if summary is None:
        return {
            "name": name,
            "realm": realm,
            "source": source,
            "fetchedAt": now,
            "updatedAt": now,
            "error": error or "unknown error",
            "items": [],
            "enchants": {},
            "gems": {},
        }

    items = extract_items(summary)
    maps = items_to_maps(items)

    gear_score = find_first_value(summary, ["gearScore", "gearscore", "gs"])
    level = find_first_value(summary, ["level", "playerLevel"])
    class_name = find_first_value(summary, ["class", "playerClass"])
    spec = find_first_value(summary, ["spec", "specialization"])
    guild = find_first_value(summary, ["guild", "guildName"])

    result: Dict[str, Any] = {
        "name": name,
        "realm": realm,
        "source": source,
        "fetchedAt": now,
        "updatedAt": now,
        "gearScore": as_int(gear_score),
        "gearScoreSource": "warmane-summary",
        "level": as_int(level),
        "class": class_name,
        "spec": spec,
        "guild": guild,
        "items": items,
        "enchants": maps["enchants"],
        "gems": maps["gems"],
    }

    if include_raw:
        result["raw"] = summary

    return result


def write_bridge_file(output_path: pathlib.Path, results: Dict[str, Dict[str, Any]], generated_at: int) -> None:
    payload = {
        "schemaVersion": 1,
        "generatedAt": generated_at,
        "results": results,
    }
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("RaidInspectorBridgeInbox = " + to_lua(payload) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch queued requests from RaidInspector.lua and write bridge inbox")
    parser.add_argument("--raid-inspector-sv", required=True, help="Path to RaidInspector.lua saved variables")
    parser.add_argument("--bridge-output", required=True, help="Path to RaidInspectorBridge.lua output file")
    parser.add_argument("--status-filter", choices=["queued", "all"], default="queued")
    parser.add_argument("--max", type=int, default=0, help="Maximum requests to fetch; 0 means all")
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout per request")
    parser.add_argument("--cot-timeout", type=float, default=15.0, help="HTTP timeout for Cavern score enrichment")
    parser.add_argument("--include-raw", action="store_true", help="Include raw Warmane summary in bridge payload")
    parser.add_argument(
        "--cot-url-template",
        default="",
        help=(
            "Optional Cavern score endpoint template. Supported placeholders: "
            "{name}, {realm}, {key}, {name_raw}, {realm_raw}, {key_raw}. "
            "Example: https://example/api/gearscore/{name}/{realm}"
        ),
    )
    parser.add_argument(
        "--cot-overwrite-existing-score",
        action="store_true",
        help="Allow Cavern score to overwrite an existing Warmane score.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Fetch and print summary without writing output")
    parser.add_argument("--verbose", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    raid_sv_path = pathlib.Path(args.raid_inspector_sv)
    bridge_output_path = pathlib.Path(args.bridge_output)

    requests = parse_requests(raid_sv_path)
    requests = dedupe_requests(requests)

    if args.status_filter == "queued":
        requests = [r for r in requests if r.get("status") == "queued"]

    if args.max > 0:
        requests = requests[: args.max]

    if not requests:
        print("No matching requests found.")
        return 0

    generated_at = int(time.time())
    results: Dict[str, Dict[str, Any]] = {}

    for req in requests:
        name = str(req["name"])
        realm = str(req["realm"])
        key = str(req["key"]).lower()
        url = make_summary_url(name, realm)

        if args.verbose:
            print(f"Fetching {name}-{realm} -> {url}")

        try:
            summary = http_get_json(url, timeout=args.timeout)
            result = make_result(
                name=name,
                realm=realm,
                now=generated_at,
                summary=summary,
                source="warmane-api-bridge",
                include_raw=args.include_raw,
            )

            if args.cot_url_template:
                should_try_cot = args.cot_overwrite_existing_score or (result.get("gearScore") is None)
                if should_try_cot:
                    cot_url = make_cot_url(args.cot_url_template, name, realm, key)
                    if args.verbose:
                        print(f"  Cavern score lookup -> {cot_url}")

                    try:
                        cot_payload = http_get_json_flexible(cot_url, timeout=args.cot_timeout)
                        cot_score = extract_cot_gearscore(cot_payload)
                        if cot_score is not None:
                            result["gearScore"] = cot_score
                            result["gearScoreSource"] = "cavernoftime"
                            result["gearScoreProvider"] = urlparse(cot_url).netloc
                            if args.include_raw:
                                result["cotRaw"] = cot_payload
                        elif args.verbose:
                            print("  Cavern score lookup did not contain a numeric gear score")
                    except Exception as exc:
                        if args.verbose:
                            print(f"  Cavern score lookup failed: {exc}")
        except urllib.error.HTTPError as exc:
            result = make_result(
                name=name,
                realm=realm,
                now=generated_at,
                summary=None,
                source="warmane-api-bridge",
                include_raw=False,
                error=f"http {exc.code}",
            )
        except urllib.error.URLError as exc:
            result = make_result(
                name=name,
                realm=realm,
                now=generated_at,
                summary=None,
                source="warmane-api-bridge",
                include_raw=False,
                error=f"network error: {exc.reason}",
            )
        except Exception as exc:
            result = make_result(
                name=name,
                realm=realm,
                now=generated_at,
                summary=None,
                source="warmane-api-bridge",
                include_raw=False,
                error=f"parse error: {exc}",
            )

        results[key] = result

    if args.dry_run:
        print(json.dumps({"generatedAt": generated_at, "results": results}, indent=2, ensure_ascii=False))
        return 0

    write_bridge_file(bridge_output_path, results, generated_at)
    print(f"Wrote {len(results)} result(s) to: {bridge_output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
