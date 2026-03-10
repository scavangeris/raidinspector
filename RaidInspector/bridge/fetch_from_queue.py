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
import html
import json
import os
import pathlib
import re
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from urllib.parse import urlparse
from typing import Any, Dict, List, Optional, Tuple


DEFAULT_SLOT_ORDER = [
    "HeadSlot",
    "NeckSlot",
    "ShoulderSlot",
    "BackSlot",
    "ChestSlot",
    "WristSlot",
    "HandsSlot",
    "WaistSlot",
    "LegsSlot",
    "FeetSlot",
    "Finger0Slot",
    "Finger1Slot",
    "Trinket0Slot",
    "Trinket1Slot",
    "MainHandSlot",
    "SecondaryHandSlot",
    "RangedSlot",
]

DEFAULT_ITEM_ILVL_CACHE_PATH = pathlib.Path(__file__).with_name("item_ilvl_cache.json")
DEFAULT_REPORT_OUTPUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "reports"
RETRYABLE_HTTP_CODES = {408, 425, 429, 500, 502, 503, 504}
GS_SCALE = 1.8618

GS_FORMULA_A = {
    4: {"A": 91.45, "B": 0.65},
    3: {"A": 81.375, "B": 0.8125},
    2: {"A": 73.0, "B": 1.0},
}

GS_FORMULA_B = {
    4: {"A": 26.0, "B": 1.2},
    3: {"A": 0.75, "B": 1.8},
    2: {"A": 8.0, "B": 2.0},
    1: {"A": 0.0, "B": 2.25},
}

GS_SLOT_CONFIG = {
    "HeadSlot": {"slotMod": 1.0, "enchantable": True},
    "NeckSlot": {"slotMod": 0.5625, "enchantable": False},
    "ShoulderSlot": {"slotMod": 0.75, "enchantable": True},
    "BackSlot": {"slotMod": 0.5625, "enchantable": True},
    "ChestSlot": {"slotMod": 1.0, "enchantable": True},
    "WristSlot": {"slotMod": 0.5625, "enchantable": True},
    "HandsSlot": {"slotMod": 0.75, "enchantable": True},
    "WaistSlot": {"slotMod": 0.75, "enchantable": False},
    "LegsSlot": {"slotMod": 1.0, "enchantable": True},
    "FeetSlot": {"slotMod": 0.75, "enchantable": True},
    "Finger0Slot": {"slotMod": 0.5625, "enchantable": False},
    "Finger1Slot": {"slotMod": 0.5625, "enchantable": False},
    "Trinket0Slot": {"slotMod": 0.5625, "enchantable": False},
    "Trinket1Slot": {"slotMod": 0.5625, "enchantable": False},
    "MainHandSlot": {"slotMod": 1.0, "enchantable": True},
    "SecondaryHandSlot": {"slotMod": 1.0, "enchantable": False},
    "RangedSlot": {"slotMod": 0.3164, "enchantable": False},
}

RAID_ACHIEVEMENT_CATEGORIES = {
    "icc10": 15041,
    "icc25": 15042,
    "toc10": 15001,
    "toc25": 15002,
}

RS_CATEGORY_BY_SIZE = {
    "rs10": 14922,
    "rs25": 14923,
}

RS_KEYWORDS = ["ruby sanctum", "halion", "twilight destroyer"]
RAID_FLAG_KEYS = ["icc10", "icc25", "toc10", "toc25", "rs10", "rs25"]

SLOT_ALIASES = {
    "head": "HeadSlot",
    "headslot": "HeadSlot",
    "invtype_head": "HeadSlot",
    "neck": "NeckSlot",
    "neckslot": "NeckSlot",
    "invtype_neck": "NeckSlot",
    "shoulder": "ShoulderSlot",
    "shoulderslot": "ShoulderSlot",
    "invtype_shoulder": "ShoulderSlot",
    "back": "BackSlot",
    "cloak": "BackSlot",
    "backslot": "BackSlot",
    "invtype_cloak": "BackSlot",
    "chest": "ChestSlot",
    "chestslot": "ChestSlot",
    "invtype_chest": "ChestSlot",
    "robe": "ChestSlot",
    "invtype_robe": "ChestSlot",
    "wrist": "WristSlot",
    "wristslot": "WristSlot",
    "invtype_wrists": "WristSlot",
    "hands": "HandsSlot",
    "handslot": "HandsSlot",
    "invtype_hands": "HandsSlot",
    "waist": "WaistSlot",
    "waistslot": "WaistSlot",
    "invtype_waist": "WaistSlot",
    "legs": "LegsSlot",
    "legsslot": "LegsSlot",
    "invtype_legs": "LegsSlot",
    "feet": "FeetSlot",
    "feetslot": "FeetSlot",
    "invtype_feet": "FeetSlot",
    "finger0slot": "Finger0Slot",
    "finger1slot": "Finger1Slot",
    "invtype_finger": "Finger0Slot",
    "trinket0slot": "Trinket0Slot",
    "trinket1slot": "Trinket1Slot",
    "invtype_trinket": "Trinket0Slot",
    "mainhand": "MainHandSlot",
    "mainhandslot": "MainHandSlot",
    "invtype_weapon": "MainHandSlot",
    "invtype_2hweapon": "MainHandSlot",
    "secondaryhand": "SecondaryHandSlot",
    "offhand": "SecondaryHandSlot",
    "offhandslot": "SecondaryHandSlot",
    "invtype_shield": "SecondaryHandSlot",
    "invtype_holdable": "SecondaryHandSlot",
    "ranged": "RangedSlot",
    "rangedslot": "RangedSlot",
    "relic": "RangedSlot",
    "invtype_ranged": "RangedSlot",
    "invtype_rangedright": "RangedSlot",
    "invtype_relic": "RangedSlot",
    "invtype_thrown": "RangedSlot",
}


class RequestRateLimiter:
    def __init__(self, min_delay_seconds: float) -> None:
        self.min_delay_seconds = max(0.0, float(min_delay_seconds))
        self._last_request_started = 0.0

    def before_request(self) -> None:
        if self.min_delay_seconds <= 0:
            return
        now = time.monotonic()
        if self._last_request_started > 0:
            elapsed = now - self._last_request_started
            if elapsed < self.min_delay_seconds:
                time.sleep(self.min_delay_seconds - elapsed)
        self._last_request_started = time.monotonic()


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


def parse_field_bool(block: str, key: str) -> Optional[bool]:
    match = re.search(rf'\["{re.escape(key)}"\]\s*=\s*(true|false|nil)', block)
    if not match:
        return None
    token = match.group(1)
    if token == "true":
        return True
    if token == "false":
        return False
    return None


class LuaTableParser:
    def __init__(self, text: str) -> None:
        self.text = text
        self.length = len(text)
        self.index = 0

    def parse(self) -> Any:
        self._skip_ws()
        value = self._parse_value()
        self._skip_ws()
        return value

    def _skip_ws(self) -> None:
        while self.index < self.length and self.text[self.index].isspace():
            self.index += 1

    def _peek(self) -> str:
        if self.index >= self.length:
            return ""
        return self.text[self.index]

    def _consume(self, token: str) -> None:
        if self._peek() != token:
            raise ValueError(f"expected {token!r} at index {self.index}")
        self.index += 1

    def _parse_value(self) -> Any:
        self._skip_ws()
        ch = self._peek()
        if ch == "{":
            return self._parse_table()
        if ch == '"':
            return self._parse_string()
        if ch in "-0123456789":
            return self._parse_number()
        if ch.isalpha() or ch == "_":
            identifier = self._parse_identifier()
            if identifier == "true":
                return True
            if identifier == "false":
                return False
            if identifier == "nil":
                return None
            return identifier
        raise ValueError(f"unexpected character {ch!r} at index {self.index}")

    def _parse_identifier(self) -> str:
        start = self.index
        while self.index < self.length and (self.text[self.index].isalnum() or self.text[self.index] == "_"):
            self.index += 1
        if self.index == start:
            raise ValueError(f"expected identifier at index {self.index}")
        return self.text[start:self.index]

    def _parse_string(self) -> str:
        self._consume('"')
        out: List[str] = []
        while self.index < self.length:
            ch = self.text[self.index]
            self.index += 1
            if ch == '"':
                return "".join(out)
            if ch == "\\":
                if self.index >= self.length:
                    break
                esc = self.text[self.index]
                self.index += 1
                if esc == "n":
                    out.append("\n")
                else:
                    out.append(esc)
            else:
                out.append(ch)
        raise ValueError("unterminated string")

    def _parse_number(self) -> Any:
        start = self.index
        while self.index < self.length and self.text[self.index] in "+-0123456789.eE":
            self.index += 1
        token = self.text[start:self.index]
        if any(ch in token for ch in ".eE"):
            return float(token)
        return int(token)

    def _parse_table(self) -> Any:
        self._consume("{")
        self._skip_ws()
        array_items: List[Any] = []
        mapping: Dict[Any, Any] = {}

        while True:
            self._skip_ws()
            ch = self._peek()
            if ch == "}":
                self.index += 1
                break

            key: Any = None
            has_key = False
            start_index = self.index

            if ch == "[":
                self.index += 1
                key = self._parse_value()
                self._skip_ws()
                self._consume("]")
                self._skip_ws()
                self._consume("=")
                has_key = True
            elif ch.isalpha() or ch == "_":
                identifier = self._parse_identifier()
                self._skip_ws()
                if self._peek() == "=":
                    self.index += 1
                    key = identifier
                    has_key = True
                else:
                    self.index = start_index

            value = self._parse_value()
            if has_key:
                mapping[key] = value
            else:
                array_items.append(value)

            self._skip_ws()
            if self._peek() in {",", ";"}:
                self.index += 1

        if mapping and not array_items:
            numeric_keys = [key for key in mapping.keys() if isinstance(key, int) and key > 0]
            if len(numeric_keys) == len(mapping):
                numeric_keys.sort()
                if numeric_keys == list(range(1, len(numeric_keys) + 1)):
                    return [mapping[index] for index in numeric_keys]
            return mapping

        if array_items and not mapping:
            return array_items

        if mapping:
            for offset, item in enumerate(array_items, start=1):
                mapping[offset] = item
            return mapping

        return []


def parse_lua_table(table_text: str) -> Any:
    return LuaTableParser(table_text).parse()


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


def parse_named_subtables(table_text: str) -> List[tuple[str, str]]:
    body = table_text[1:-1]
    out: List[tuple[str, str]] = []
    index = 0

    while index < len(body):
        match = re.search(r'\["([^"]+)"\]\s*=\s*{', body[index:])
        if not match:
            break

        key = match.group(1)
        brace_start = index + match.end() - 1
        depth = 0
        end = brace_start

        while end < len(body):
            ch = body[end]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    out.append((key, body[brace_start : end + 1]))
                    index = end + 1
                    break
            end += 1

        if depth != 0:
            break

    return out


def parse_result_updated_at_map(saved_variables_path: pathlib.Path) -> Dict[str, int]:
    try:
        text = saved_variables_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return {}

    results_block = find_table_block(text, '["results"] = {')
    if not results_block:
        return {}

    out: Dict[str, int] = {}
    for key, block in parse_named_subtables(results_block):
        updated_at = parse_field_int(block, "updatedAt") or parse_field_int(block, "fetchedAt") or 0
        if updated_at > 0:
            out[key.lower()] = updated_at

    return out


def parse_results_missing_achievement_requests(saved_variables_path: pathlib.Path) -> List[Dict[str, Any]]:
    try:
        text = saved_variables_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []

    results_block = find_table_block(text, '["results"] = {')
    if not results_block:
        return []

    out: List[Dict[str, Any]] = []
    for key, block in parse_named_subtables(results_block):
        normalized_key = str(key).lower()
        name = parse_field_str(block, "name")
        realm = parse_field_str(block, "realm")
        if not name or not realm:
            split = normalized_key.rsplit("-", 1)
            if len(split) == 2:
                if not name:
                    name = split[0]
                if not realm:
                    realm = split[1]

        if not name or not realm:
            continue

        achievement_points = parse_field_int(block, "achievementPoints")
        raid_block = find_table_block(block, '["raidAchievements"] = {') or ""
        raid_complete = True
        for raid_key in RAID_FLAG_KEYS:
            if parse_field_bool(raid_block, raid_key) is None:
                raid_complete = False
                break

        if achievement_points is not None and raid_complete:
            continue

        out.append(
            {
                "id": None,
                "name": name,
                "realm": realm,
                "key": normalized_key,
                "status": "ready",
            }
        )

    return out


def parse_report_queue(saved_variables_path: pathlib.Path) -> List[Dict[str, Any]]:
    try:
        text = saved_variables_path.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return []

    queue_block = find_table_block(text, '["reportFileQueue"] = {')
    if not queue_block:
        return []

    items_block = find_table_block(queue_block, '["items"] = {')
    if not items_block:
        return []

    out: List[Dict[str, Any]] = []
    for entry in split_top_level_tables(items_block):
        queue_id = parse_field_int(entry, "id")
        created_at = parse_field_int(entry, "createdAt") or int(time.time())
        file_name = parse_field_str(entry, "fileName") or f"raidinspector-report-{created_at}.json"
        label = parse_field_str(entry, "label") or file_name
        report_block = find_table_block(entry, '["report"] = {')
        if not report_block:
            continue

        try:
            report = parse_lua_table(report_block)
        except Exception:
            continue

        if not isinstance(report, dict):
            continue

        report.setdefault("createdAt", created_at)
        report.setdefault("fileName", file_name)
        report.setdefault("reportLabel", label)
        out.append(
            {
                "id": queue_id,
                "createdAt": created_at,
                "fileName": file_name,
                "label": label,
                "report": report,
            }
        )

    return out


def write_report_file(output_dir: pathlib.Path, item: Dict[str, Any]) -> pathlib.Path:
    created_at = as_int(item.get("createdAt")) or int(time.time())
    file_name = str(item.get("fileName") or f"raidinspector-report-{created_at}.json")
    report = item.get("report") if isinstance(item.get("report"), dict) else {}
    report.setdefault("createdAt", created_at)
    report.setdefault("fileName", file_name)
    report.setdefault("reportLabel", str(item.get("label") or file_name))

    output_path = output_dir / file_name
    atomic_write_text(output_path, json.dumps(report, indent=2, sort_keys=True, ensure_ascii=False), encoding="utf-8")
    return output_path


def load_report_file(path: pathlib.Path) -> Optional[Dict[str, Any]]:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    return payload if isinstance(payload, dict) else None


def count_report_players(report: Dict[str, Any]) -> int:
    order = report.get("order")
    if isinstance(order, list):
        return len(order)
    players = report.get("players")
    if isinstance(players, dict):
        return len(players)
    return 0


def build_report_catalog(output_dir: pathlib.Path) -> List[Dict[str, Any]]:
    if not output_dir.exists():
        return []

    items: List[Dict[str, Any]] = []
    for path in sorted(output_dir.glob("*.json")):
        report = load_report_file(path)
        if not isinstance(report, dict):
            continue

        created_at = as_int(report.get("createdAt")) or int(path.stat().st_mtime)
        items.append(
            {
                "fileName": path.name,
                "label": str(report.get("reportLabel") or path.stem),
                "createdAt": created_at,
                "playerCount": count_report_players(report),
                "report": report,
            }
        )

    items.sort(key=lambda item: (-(as_int(item.get("createdAt")) or 0), str(item.get("fileName") or "")))
    return items


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


def make_armory_summary_page_url(name: str, realm: str) -> str:
    q_name = urllib.parse.quote(name, safe="")
    q_realm = urllib.parse.quote(realm, safe="")
    return f"https://armory.warmane.com/character/{q_name}/{q_realm}/summary"


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


def is_retryable_exception(exc: Exception) -> bool:
    if isinstance(exc, urllib.error.HTTPError):
        return exc.code in RETRYABLE_HTTP_CODES
    if isinstance(exc, urllib.error.URLError):
        return True
    if isinstance(exc, TimeoutError):
        return True
    return False


def run_with_retries(
    operation_name: str,
    fn,
    retries: int,
    retry_backoff: float,
    verbose: bool,
) -> Any:
    attempt = 0
    max_retries = max(0, int(retries))
    backoff = max(0.0, float(retry_backoff))

    while True:
        try:
            return fn()
        except Exception as exc:
            if attempt >= max_retries or not is_retryable_exception(exc):
                raise

            wait_seconds = backoff * (2 ** attempt)
            if verbose:
                print(
                    f"  Retry {attempt + 1}/{max_retries} for {operation_name} in {wait_seconds:.1f}s ({exc})"
                )
            if wait_seconds > 0:
                time.sleep(wait_seconds)
            attempt += 1


def http_get_json(url: str, timeout: float, rate_limiter: Optional[RequestRateLimiter] = None) -> Any:
    if rate_limiter:
        rate_limiter.before_request()
    request = urllib.request.Request(url, headers={"User-Agent": "RaidInspectorBridge/0.1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        payload = response.read().decode(charset, errors="replace")
    return json.loads(payload)


def http_get_json_flexible(url: str, timeout: float, rate_limiter: Optional[RequestRateLimiter] = None) -> Any:
    if rate_limiter:
        rate_limiter.before_request()
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


def http_get_text(url: str, timeout: float, rate_limiter: Optional[RequestRateLimiter] = None) -> str:
    if rate_limiter:
        rate_limiter.before_request()
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        return response.read().decode(charset, errors="replace")


def http_post_form_json(
    url: str,
    form_data: Dict[str, Any],
    timeout: float,
    rate_limiter: Optional[RequestRateLimiter] = None,
) -> Any:
    if rate_limiter:
        rate_limiter.before_request()

    encoded = urllib.parse.urlencode(form_data).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=encoded,
        method="POST",
        headers={
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64)",
            "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
            "Accept": "application/json,text/plain,*/*",
            "X-Requested-With": "XMLHttpRequest",
            "Origin": "https://armory.warmane.com",
            "Referer": url,
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        charset = response.headers.get_content_charset() or "utf-8"
        payload = response.read().decode(charset, errors="replace")
    payload = payload.strip()
    if not payload:
        return {}
    try:
        return json.loads(payload)
    except Exception:
        # Some anti-bot or fallback paths can return raw HTML text.
        return {"content": payload}


def estimate_gearscorelite_item(item: Dict[str, Any]) -> Optional[int]:
    ilvl = as_int(item.get("ilvl"))
    slot = str(item.get("slot") or "")
    if ilvl is None or ilvl <= 0 or slot not in GS_SLOT_CONFIG:
        return None

    rarity = as_int(item.get("rarity") or item.get("quality"))
    if rarity is None:
        rarity = 4

    quality_scale = 1.0
    if rarity == 5:
        quality_scale = 1.3
        rarity = 4
    elif rarity in (0, 1):
        quality_scale = 0.005
        rarity = 2
    elif rarity == 7:
        rarity = 3
        ilvl = int(187.05)

    table = GS_FORMULA_A if ilvl > 120 else GS_FORMULA_B
    formula = table.get(rarity)
    if not formula:
        return None

    slot_mod = GS_SLOT_CONFIG[slot]["slotMod"]
    score = int(((ilvl - formula["A"]) / formula["B"]) * slot_mod * GS_SCALE * quality_scale)
    if score < 0:
        score = 0

    if GS_SLOT_CONFIG[slot]["enchantable"] and as_int(item.get("enchantId")) is None:
        percent = 1 + ((-2 * slot_mod) / 100.0)
        score = int(score * percent)

    return max(0, score)


def estimate_gearscorelite_from_items(items: List[Dict[str, Any]], class_name: Any) -> Optional[int]:
    if not items:
        return None

    total = 0.0
    count = 0
    is_hunter = "hunter" in str(class_name or "").strip().lower()

    for item in items:
        base = estimate_gearscorelite_item(item)
        if base is None:
            continue

        slot = str(item.get("slot") or "")
        score = float(base)
        if is_hunter and slot == "MainHandSlot":
            score *= 0.3164
        if is_hunter and slot == "RangedSlot":
            score *= 5.3224

        total += score
        count += 1

    if count == 0:
        return None
    return int(round(total))


def make_achievements_page_url(name: str, realm: str) -> str:
    q_name = urllib.parse.quote(name, safe="")
    q_realm = urllib.parse.quote(realm, safe="")
    return f"https://armory.warmane.com/character/{q_name}/{q_realm}/achievements"


def fetch_achievement_category_content(
    name: str,
    realm: str,
    category: int,
    timeout: float,
    retries: int,
    retry_backoff: float,
    rate_limiter: Optional[RequestRateLimiter],
    verbose: bool,
) -> str:
    url = make_achievements_page_url(name, realm)
    payload = run_with_retries(
        f"achievements {name}-{realm} category {category}",
        lambda: http_post_form_json(
            url,
            {"category": str(category)},
            timeout=timeout,
            rate_limiter=rate_limiter,
        ),
        retries=retries,
        retry_backoff=retry_backoff,
        verbose=verbose,
    )

    if isinstance(payload, dict):
        for candidate in ["content", "html", "data", "result"]:
            content = payload.get(candidate)
            if isinstance(content, str):
                return content
            if isinstance(content, (dict, list)):
                try:
                    return json.dumps(content)
                except Exception:
                    return str(content)
    if isinstance(payload, list):
        try:
            return json.dumps(payload)
        except Exception:
            return str(payload)
    return ""


def has_achievement_entries(content: str) -> bool:
    if not content:
        return False
    patterns = [
        r"class\s*=\s*['\"][^'\"]*achievement[^'\"]*['\"]",
        r"/achievement/\d+",
        r"data-achievement",
        r'\"achievement\"\s*:\s*\{',
        r'\"achievement_id\"\s*:\s*\d+',
    ]
    for pattern in patterns:
        if re.search(pattern, content, flags=re.I):
            return True
    return False


def fetch_achievement_points_from_page(
    name: str,
    realm: str,
    timeout: float,
    retries: int,
    retry_backoff: float,
    rate_limiter: Optional[RequestRateLimiter],
    verbose: bool,
) -> Optional[int]:
    url = make_achievements_page_url(name, realm)
    page = run_with_retries(
        f"achievements page {name}-{realm}",
        lambda: http_get_text(url, timeout=timeout, rate_limiter=rate_limiter),
        retries=retries,
        retry_backoff=retry_backoff,
        verbose=verbose,
    )

    patterns = [
        r"achievement\s*points[^0-9]{0,40}(\d{2,6})",
        r'\"achievementPoints\"\s*:\s*(\d{2,6})',
        r'\"achievement_points\"\s*:\s*(\d{2,6})',
    ]
    for pattern in patterns:
        m = re.search(pattern, page, flags=re.I)
        if m:
            return as_int(m.group(1))
    return None


def fetch_raid_achievement_flags(
    name: str,
    realm: str,
    timeout: float,
    retries: int,
    retry_backoff: float,
    rate_limiter: Optional[RequestRateLimiter],
    verbose: bool,
) -> Dict[str, Any]:
    flags: Dict[str, Any] = {
        "icc10": None,
        "icc25": None,
        "toc10": None,
        "toc25": None,
        "rs10": None,
        "rs25": None,
        "source": "warmane-achievements",
    }

    for key, category in RAID_ACHIEVEMENT_CATEGORIES.items():
        try:
            content = fetch_achievement_category_content(
                name,
                realm,
                category,
                timeout,
                retries,
                retry_backoff,
                rate_limiter,
                verbose,
            )
            flags[key] = has_achievement_entries(content)
        except Exception as exc:
            if verbose:
                print(f"  Achievement lookup failed for {key}: {exc}")

    for key, category in RS_CATEGORY_BY_SIZE.items():
        try:
            content = fetch_achievement_category_content(
                name,
                realm,
                category,
                timeout,
                retries,
                retry_backoff,
                rate_limiter,
                verbose,
            )
            lowered = content.lower()
            flags[key] = any(token in lowered for token in RS_KEYWORDS)
        except Exception as exc:
            if verbose:
                print(f"  Achievement lookup failed for {key}: {exc}")

    return flags


def load_item_ilvl_cache(path: pathlib.Path) -> Dict[str, int]:
    if not path.exists():
        return {}
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            out: Dict[str, int] = {}
            for k, v in payload.items():
                vi = as_int(v)
                if vi is not None:
                    out[str(k)] = vi
            return out
    except Exception:
        return {}
    return {}


def atomic_write_text(path: pathlib.Path, text: str, encoding: str = "utf-8") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding=encoding) as handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp_path, path)
    except Exception:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass
        raise


def save_item_ilvl_cache(path: pathlib.Path, cache: Dict[str, int]) -> None:
    atomic_write_text(path, json.dumps(cache, indent=2, sort_keys=True), encoding="utf-8")


def make_cot_item_url(item_id: int) -> str:
    return f"https://wotlk.cavernoftime.com/item={item_id}"


def parse_item_level_from_cot_html(html_text: str) -> Optional[int]:
    m = re.search(r"Item\s+Level\s*(\d+)", html_text, flags=re.I)
    if m:
        return as_int(m.group(1))
    return None


def fetch_item_ilvl_from_cot(
    item_id: int,
    timeout: float,
    retries: int,
    retry_backoff: float,
    rate_limiter: Optional[RequestRateLimiter],
    verbose: bool,
) -> Optional[int]:
    html_text = run_with_retries(
        f"item ilvl {item_id}",
        lambda: http_get_text(make_cot_item_url(item_id), timeout=timeout, rate_limiter=rate_limiter),
        retries=retries,
        retry_backoff=retry_backoff,
        verbose=verbose,
    )
    return parse_item_level_from_cot_html(html_text)


def enrich_items_with_ilvl_from_cache_and_cot(
    items: List[Dict[str, Any]],
    cache: Dict[str, int],
    timeout: float,
    retries: int,
    retry_backoff: float,
    rate_limiter: Optional[RequestRateLimiter],
    verbose: bool,
) -> None:
    for item in items:
        if as_int(item.get("ilvl")) is not None:
            continue

        item_id = as_int(item.get("itemId"))
        if item_id is None:
            continue

        cache_key = str(item_id)
        cached = as_int(cache.get(cache_key))
        if cached and cached > 0:
            item["ilvl"] = cached
            continue

        try:
            ilvl = fetch_item_ilvl_from_cot(
                item_id,
                timeout=timeout,
                retries=retries,
                retry_backoff=retry_backoff,
                rate_limiter=rate_limiter,
                verbose=verbose,
            )
            if ilvl and ilvl > 0:
                item["ilvl"] = ilvl
                cache[cache_key] = ilvl
                if verbose:
                    print(f"  Item ilvl enriched: {item_id} -> {ilvl}")
            else:
                cache[cache_key] = -1
        except Exception as exc:
            if verbose:
                print(f"  Item ilvl lookup failed for {item_id}: {exc}")


def parse_armory_rel_equipment(html_text: str) -> List[Dict[str, Any]]:
    rel_matches = re.findall(r'rel="([^"]*item=[^"]*)"', html_text, flags=re.I)
    out: List[Dict[str, Any]] = []

    for rel in rel_matches:
        decoded = html.unescape(rel)
        pairs = urllib.parse.parse_qs(decoded, keep_blank_values=True)

        item_id = as_int((pairs.get("item") or [None])[0])
        ench_id = as_int((pairs.get("ench") or [None])[0])
        gems_raw = (pairs.get("gems") or [""])[0]

        gems_all: List[int] = []
        gems_filled: List[int] = []
        if isinstance(gems_raw, str) and gems_raw != "":
            for token in gems_raw.split(":"):
                gid = as_int(token)
                if gid is None:
                    continue
                gems_all.append(gid)
                if gid > 0:
                    gems_filled.append(gid)

        socket_count = 0
        if gems_all:
            last_non_zero = -1
            for i, gid in enumerate(gems_all):
                if gid > 0:
                    last_non_zero = i
            if last_non_zero >= 0:
                socket_count = last_non_zero + 1

        if not item_id:
            continue

        out.append(
            {
                "itemId": item_id,
                "enchantId": ench_id if ench_id and ench_id > 0 else None,
                "gems": gems_filled,
                "socketCount": socket_count,
            }
        )

    return out


def merge_armory_rel_details_into_items(items: List[Dict[str, Any]], rel_items: List[Dict[str, Any]]) -> None:
    if not items or not rel_items:
        for idx, item in enumerate(items):
            if not item.get("slot") and idx < len(DEFAULT_SLOT_ORDER):
                item["slot"] = DEFAULT_SLOT_ORDER[idx]
        return

    by_item_id: Dict[int, List[Dict[str, Any]]] = {}
    for rel in rel_items:
        iid = as_int(rel.get("itemId"))
        if not iid:
            continue
        by_item_id.setdefault(iid, []).append(rel)

    used_rel_indices = set()

    for idx, item in enumerate(items):
        if not item.get("slot") and idx < len(DEFAULT_SLOT_ORDER):
            item["slot"] = DEFAULT_SLOT_ORDER[idx]

        candidate: Optional[Dict[str, Any]] = None
        if idx < len(rel_items):
            rel = rel_items[idx]
            rid = as_int(rel.get("itemId"))
            iid = as_int(item.get("itemId"))
            if rid and iid and rid == iid and idx not in used_rel_indices:
                candidate = rel
                used_rel_indices.add(idx)

        if candidate is None:
            iid = as_int(item.get("itemId"))
            if iid and iid in by_item_id and by_item_id[iid]:
                candidate = by_item_id[iid].pop(0)

        if candidate is None:
            continue

        ench = as_int(candidate.get("enchantId"))
        if ench and not as_int(item.get("enchantId")):
            item["enchantId"] = ench

        socket_count = as_int(candidate.get("socketCount")) or 0
        if socket_count > 0 and (as_int(item.get("socketCount")) or 0) == 0:
            item["socketCount"] = socket_count

        rel_gems = candidate.get("gems") or []
        if rel_gems and not item.get("gems"):
            item["gems"] = [int(g) for g in rel_gems if as_int(g) and as_int(g) > 0]


def build_items_from_armory_rel(rel_items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    items: List[Dict[str, Any]] = []
    for idx, rel in enumerate(rel_items):
        item_id = as_int(rel.get("itemId"))
        if not item_id:
            continue

        item: Dict[str, Any] = {"itemId": item_id}
        if idx < len(DEFAULT_SLOT_ORDER):
            item["slot"] = DEFAULT_SLOT_ORDER[idx]

        ench = as_int(rel.get("enchantId"))
        if ench and ench > 0:
            item["enchantId"] = ench

        socket_count = as_int(rel.get("socketCount")) or 0
        if socket_count > 0:
            item["socketCount"] = socket_count

        gems = rel.get("gems") or []
        if gems:
            item["gems"] = [int(g) for g in gems if as_int(g) and as_int(g) > 0]

        items.append(item)

    return items


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


def extract_achievement_points(summary: Dict[str, Any]) -> Optional[int]:
    direct = find_first_value(
        summary,
        [
            "achievementpoints",
            "achievementPoints",
            "achievement_points",
            "achievementsPoints",
            "totalAchievementPoints",
        ],
    )
    direct_int = as_int(direct)
    if direct_int is not None:
        return direct_int

    achievements_root = find_first_value(summary, ["achievements", "achievement"])
    if isinstance(achievements_root, (dict, list)):
        nested = find_first_value(
            achievements_root,
            ["achievementPoints", "achievement_points", "totalPoints", "points", "total"],
        )
        nested_int = as_int(nested)
        if nested_int is not None:
            return nested_int

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


def canonicalize_slot(slot: Any) -> Optional[str]:
    if slot is None:
        return None
    raw = str(slot).strip()
    if raw == "":
        return None
    if raw in GS_SLOT_CONFIG:
        return raw
    norm = raw.lower().replace("_", "")
    return SLOT_ALIASES.get(norm, raw)


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
    quality = as_int(raw_item.get("quality") or raw_item.get("rarity") or raw_item.get("itemQuality"))
    enchant_id = as_int(
        raw_item.get("enchant")
        or raw_item.get("enchantId")
        or raw_item.get("permanentEnchant")
    )
    slot = canonicalize_slot(
        slot_hint
        or raw_item.get("slot")
        or raw_item.get("slotName")
        or raw_item.get("inventoryType")
    )
    gems = extract_gems(raw_item)
    socket_count = as_int(raw_item.get("socketCount") or raw_item.get("socketsCount"))

    if socket_count is None:
        sockets_raw = raw_item.get("sockets")
        if isinstance(sockets_raw, list):
            socket_count = len(sockets_raw)
        elif isinstance(sockets_raw, dict):
            socket_count = len(sockets_raw)

    if not any([item_id, item_name, item_level, enchant_id, gems, socket_count]):
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
    if quality is not None and quality >= 0:
        out["quality"] = int(quality)
    if enchant_id:
        out["enchantId"] = enchant_id
    if socket_count and socket_count > 0:
        out["socketCount"] = int(socket_count)
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


def estimate_gearscore_from_items(items: List[Dict[str, Any]], class_name: Any = None) -> Optional[int]:
    gsl_estimate = estimate_gearscorelite_from_items(items, class_name)
    if gsl_estimate is not None:
        return gsl_estimate

    ilvls: List[int] = []
    for item in items:
        ilvl = as_int(item.get("ilvl"))
        if ilvl and ilvl > 0:
            ilvls.append(ilvl)

    if not ilvls:
        return None

    avg_ilvl = sum(ilvls) / float(len(ilvls))
    # Pragmatic fallback approximation for Wrath-like gearscore scale.
    return int(round(avg_ilvl * 20.0))


def estimate_gearscore_with_source(items: List[Dict[str, Any]], class_name: Any = None) -> Tuple[Optional[int], str]:
    gsl_estimate = estimate_gearscorelite_from_items(items, class_name)
    if gsl_estimate is not None:
        return gsl_estimate, "estimated-gearscorelite"

    ilvl_estimate = estimate_gearscore_from_items(items, class_name)
    if ilvl_estimate is not None:
        return ilvl_estimate, "estimated-ilvl"

    return None, "none"


def normalize_slot_name(slot: Any) -> str:
    return str(slot or "").strip().lower().replace("_", "")


ENCHANTABLE_SLOT_NAMES = {
    "head",
    "headslot",
    "shoulder",
    "shoulders",
    "shoulderslot",
    "back",
    "cloak",
    "backslot",
    "chest",
    "chestslot",
    "wrist",
    "wristslot",
    "hands",
    "hand",
    "handslot",
    "gloves",
    "legs",
    "legsslot",
    "feet",
    "footslot",
    "boots",
    "mainhand",
    "mainhandslot",
    "offhand",
    "offhandslot",
    "onehand",
    "twohand",
    "weapon",
    "ranged",
    "rangedslot",
    "relic",
}


def analyze_item_issues(items: List[Dict[str, Any]]) -> Dict[str, int]:
    missing_enchant = 0
    missing_gems = 0
    items_without_slot = 0
    items_with_sockets = 0
    total_sockets = 0
    filled_sockets = 0

    for item in items:
        slot_raw = item.get("slot")
        slot_name = normalize_slot_name(slot_raw)
        socket_count = as_int(item.get("socketCount")) or 0
        gem_count = len(item.get("gems", []) or [])

        if not slot_name:
            items_without_slot += 1
        else:
            if slot_name in ENCHANTABLE_SLOT_NAMES and as_int(item.get("enchantId")) is None:
                missing_enchant += 1

        if socket_count > 0:
            items_with_sockets += 1
            total_sockets += socket_count
            filled_sockets += min(socket_count, gem_count)
            if gem_count < socket_count:
                missing_gems += (socket_count - gem_count)

    return {
        "missingEnchant": missing_enchant,
        "missingGems": missing_gems,
        "itemsWithoutSlot": items_without_slot,
        "itemsAnalyzed": len(items),
        "itemsWithSockets": items_with_sockets,
        "totalSockets": total_sockets,
        "filledSockets": filled_sockets,
    }


def make_result(
    name: str,
    realm: str,
    now: int,
    summary: Optional[Dict[str, Any]],
    armory_rel_items: Optional[List[Dict[str, Any]]],
    source: str,
    include_raw: bool,
    raid_achievements: Optional[Dict[str, Any]] = None,
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
            "issuesCount": 0,
            "issueSummary": {
                "missingEnchant": 0,
                "missingGems": 0,
                "itemsWithoutSlot": 0,
                "itemsAnalyzed": 0,
                "itemsWithSockets": 0,
                "totalSockets": 0,
                "filledSockets": 0,
            },
            "items": [],
            "enchants": {},
            "gems": {},
            "raidAchievements": {
                "icc10": None,
                "icc25": None,
                "toc10": None,
                "toc25": None,
                "rs10": None,
                "rs25": None,
            },
        }

    items = extract_items(summary)
    if not items and armory_rel_items:
        # Some Warmane summary payloads omit equipment while armory HTML still has rel item data.
        items = build_items_from_armory_rel(armory_rel_items)
    merge_armory_rel_details_into_items(items, armory_rel_items or [])
    maps = items_to_maps(items)

    gear_score = find_first_value(summary, ["gearScore", "gearscore", "gs"])
    level = find_first_value(summary, ["level", "playerLevel"])
    class_name = find_first_value(summary, ["class", "playerClass"])
    spec = find_first_value(summary, ["spec", "specialization"])
    guild = find_first_value(summary, ["guild", "guildName"])
    achievement_points = extract_achievement_points(summary)

    estimated_gearscore, estimated_source = estimate_gearscore_with_source(items, class_name)
    issue_summary = analyze_item_issues(items)

    final_gearscore = as_int(gear_score)
    gearscore_source = "none"
    if final_gearscore is not None:
        gearscore_source = "warmane-summary"
    elif estimated_gearscore is not None:
        final_gearscore = estimated_gearscore
        gearscore_source = estimated_source

    result: Dict[str, Any] = {
        "name": name,
        "realm": realm,
        "source": source,
        "fetchedAt": now,
        "updatedAt": now,
        "gearScore": final_gearscore,
        "gearScoreSource": gearscore_source,
        "estimatedGearScore": estimated_gearscore,
        "level": as_int(level),
        "class": class_name,
        "spec": spec,
        "guild": guild,
        "issuesCount": issue_summary["missingEnchant"] + issue_summary["missingGems"],
        "issueSummary": issue_summary,
        "items": items,
        "enchants": maps["enchants"],
        "gems": maps["gems"],
        "achievementPoints": as_int(achievement_points),
        "raidAchievements": raid_achievements or {
            "icc10": None,
            "icc25": None,
            "toc10": None,
            "toc25": None,
            "rs10": None,
            "rs25": None,
        },
    }

    if include_raw:
        result["raw"] = summary

    return result


def write_bridge_file(
    output_path: pathlib.Path,
    results: Dict[str, Dict[str, Any]],
    generated_at: int,
    report_files: Optional[List[Dict[str, Any]]] = None,
    processed_report_queue_ids: Optional[List[int]] = None,
) -> None:
    payload = {
        "schemaVersion": 1,
        "generatedAt": generated_at,
        "results": results,
        "reportFiles": report_files or [],
        "processedReportQueueIds": processed_report_queue_ids or [],
    }
    atomic_write_text(output_path, "RaidInspectorBridgeInbox = " + to_lua(payload) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch queued requests from RaidInspector.lua and write bridge inbox")
    parser.add_argument("--raid-inspector-sv", required=True, help="Path to RaidInspector.lua saved variables")
    parser.add_argument("--bridge-output", required=True, help="Path to RaidInspectorBridge.lua output file")
    parser.add_argument(
        "--report-output-dir",
        default=str(DEFAULT_REPORT_OUTPUT_DIR),
        help="Directory where detailed report files are written",
    )
    parser.add_argument("--status-filter", choices=["queued", "all"], default="queued")
    parser.add_argument("--max", type=int, default=0, help="Maximum requests to fetch; 0 means all")
    parser.add_argument(
        "--cache-ttl-minutes",
        type=float,
        default=0.0,
        help="Skip fetch when existing addon result for key is newer than this many minutes (0 disables).",
    )
    parser.add_argument("--retries", type=int, default=2, help="Retry count for transient network failures")
    parser.add_argument("--retry-backoff", type=float, default=1.0, help="Base retry backoff seconds (exponential)")
    parser.add_argument("--request-delay", type=float, default=0.2, help="Minimum seconds between outbound HTTP requests")
    parser.add_argument("--timeout", type=float, default=15.0, help="HTTP timeout per request")
    parser.add_argument("--achievements-timeout", type=float, default=15.0, help="HTTP timeout for Warmane raid achievement checks")
    parser.add_argument("--armory-html-timeout", type=float, default=15.0, help="HTTP timeout for Warmane armory HTML enrichment")
    parser.add_argument(
        "--skip-armory-html",
        action="store_true",
        help="Skip armory HTML enrichment (slot/enchant/gems rel parsing).",
    )
    parser.add_argument(
        "--skip-item-ilvl",
        action="store_true",
        help="Skip item-level enrichment from Cavern item pages.",
    )
    parser.add_argument(
        "--skip-raid-achievements",
        action="store_true",
        help="Skip Warmane raid achievement presence checks (ICC/TOC/RS 10/25).",
    )
    parser.add_argument("--item-ilvl-timeout", type=float, default=15.0, help="HTTP timeout for item-level lookups")
    parser.add_argument(
        "--item-ilvl-cache",
        default=str(DEFAULT_ITEM_ILVL_CACHE_PATH),
        help="Path to JSON cache file for item level lookups",
    )
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
    report_output_dir = pathlib.Path(args.report_output_dir)

    requests = parse_requests(raid_sv_path)
    report_queue_items = parse_report_queue(raid_sv_path)

    # When status-filter=all, also enrich existing local results that still lack AP/raid achievements.
    if args.status_filter == "all":
        requests.extend(parse_results_missing_achievement_requests(raid_sv_path))

    requests = dedupe_requests(requests)

    if args.status_filter == "queued":
        requests = [r for r in requests if r.get("status") == "queued"]

    if args.max > 0:
        requests = requests[: args.max]

    skipped_by_ttl = 0
    if args.cache_ttl_minutes and args.cache_ttl_minutes > 0:
        ttl_seconds = int(max(0.0, args.cache_ttl_minutes) * 60)
        now_ts = int(time.time())
        cached_updated = parse_result_updated_at_map(raid_sv_path)
        ttl_filtered: List[Dict[str, Any]] = []

        for req in requests:
            key = str(req.get("key", "")).lower()
            updated_at = cached_updated.get(key, 0)
            if updated_at > 0 and (now_ts - updated_at) <= ttl_seconds:
                skipped_by_ttl += 1
                continue
            ttl_filtered.append(req)

        requests = ttl_filtered
        if args.verbose and skipped_by_ttl > 0:
            print(f"Skipped {skipped_by_ttl} request(s) due to cache TTL ({args.cache_ttl_minutes}m)")

    generated_at = int(time.time())
    results: Dict[str, Dict[str, Any]] = {}
    processed_report_queue_ids: List[int] = []

    for item in report_queue_items:
        try:
            write_report_file(report_output_dir, item)
            report_id = as_int(item.get("id"))
            if report_id is not None:
                processed_report_queue_ids.append(report_id)
        except Exception as exc:
            if args.verbose:
                print(f"Report write failed for {item.get('fileName')}: {exc}")

    report_files = build_report_catalog(report_output_dir)

    if not requests and not report_files and not report_queue_items:
        if skipped_by_ttl > 0:
            print("No matching requests found (all candidates skipped by cache TTL).")
        else:
            print("No matching requests found.")
        return 0

    item_ilvl_cache_path = pathlib.Path(args.item_ilvl_cache)
    item_ilvl_cache = load_item_ilvl_cache(item_ilvl_cache_path)
    cache_dirty = False
    rate_limiter = RequestRateLimiter(args.request_delay)

    for req in requests:
        name = str(req["name"])
        realm = str(req["realm"])
        key = str(req["key"]).lower()
        url = make_summary_url(name, realm)
        armory_rel_items: List[Dict[str, Any]] = []

        if not args.skip_armory_html:
            armory_url = make_armory_summary_page_url(name, realm)
            try:
                armory_html = run_with_retries(
                    f"armory html {name}-{realm}",
                    lambda: http_get_text(armory_url, timeout=args.armory_html_timeout, rate_limiter=rate_limiter),
                    retries=args.retries,
                    retry_backoff=args.retry_backoff,
                    verbose=args.verbose,
                )
                armory_rel_items = parse_armory_rel_equipment(armory_html)
                if args.verbose:
                    print(f"  Armory rel enrichment items: {len(armory_rel_items)}")
            except Exception as exc:
                if args.verbose:
                    print(f"  Armory rel enrichment failed: {exc}")

        if args.verbose:
            print(f"Fetching {name}-{realm} -> {url}")

        try:
            summary = run_with_retries(
                f"warmane summary {name}-{realm}",
                lambda: http_get_json(url, timeout=args.timeout, rate_limiter=rate_limiter),
                retries=args.retries,
                retry_backoff=args.retry_backoff,
                verbose=args.verbose,
            )
            if not isinstance(summary, dict):
                if args.verbose:
                    print("  Warmane summary schema warning: non-dict payload, wrapping for resilient parsing")
                summary = {"payload": summary}

            raid_achievements = None
            if not args.skip_raid_achievements:
                try:
                    raid_achievements = fetch_raid_achievement_flags(
                        name=name,
                        realm=realm,
                        timeout=args.achievements_timeout,
                        retries=args.retries,
                        retry_backoff=args.retry_backoff,
                        rate_limiter=rate_limiter,
                        verbose=args.verbose,
                    )
                except Exception as exc:
                    if args.verbose:
                        print(f"  Raid achievement lookup failed: {exc}")

            result = make_result(
                name=name,
                realm=realm,
                now=generated_at,
                summary=summary,
                armory_rel_items=armory_rel_items,
                source="warmane-api-bridge",
                include_raw=args.include_raw,
                raid_achievements=raid_achievements,
            )

            if as_int(result.get("achievementPoints")) is None:
                try:
                    ap_from_page = fetch_achievement_points_from_page(
                        name=name,
                        realm=realm,
                        timeout=args.achievements_timeout,
                        retries=args.retries,
                        retry_backoff=args.retry_backoff,
                        rate_limiter=rate_limiter,
                        verbose=args.verbose,
                    )
                    if ap_from_page is not None:
                        result["achievementPoints"] = int(ap_from_page)
                        if args.verbose:
                            print(f"  Achievement points enriched from page: {ap_from_page}")
                except Exception as exc:
                    if args.verbose:
                        print(f"  Achievement points lookup failed: {exc}")

            if not args.skip_item_ilvl:
                before_ilvls = sum(1 for it in result.get("items", []) if as_int(it.get("ilvl")) is not None)
                enrich_items_with_ilvl_from_cache_and_cot(
                    result.get("items", []),
                    item_ilvl_cache,
                    timeout=args.item_ilvl_timeout,
                    retries=args.retries,
                    retry_backoff=args.retry_backoff,
                    rate_limiter=rate_limiter,
                    verbose=args.verbose,
                )
                after_ilvls = sum(1 for it in result.get("items", []) if as_int(it.get("ilvl")) is not None)
                if after_ilvls > before_ilvls:
                    cache_dirty = True

                # Re-evaluate fallback score after ilvl enrichment.
                if result.get("gearScore") is None:
                    estimated_after, estimated_after_source = estimate_gearscore_with_source(
                        result.get("items", []),
                        result.get("class"),
                    )
                    result["estimatedGearScore"] = estimated_after
                    if estimated_after is not None:
                        result["gearScore"] = estimated_after
                        result["gearScoreSource"] = estimated_after_source

            if args.cot_url_template:
                should_try_cot = args.cot_overwrite_existing_score or (result.get("gearScore") is None)
                if should_try_cot:
                    cot_url = make_cot_url(args.cot_url_template, name, realm, key)
                    if args.verbose:
                        print(f"  Cavern score lookup -> {cot_url}")

                    try:
                        cot_payload = run_with_retries(
                            f"cavern score {name}-{realm}",
                            lambda: http_get_json_flexible(cot_url, timeout=args.cot_timeout, rate_limiter=rate_limiter),
                            retries=args.retries,
                            retry_backoff=args.retry_backoff,
                            verbose=args.verbose,
                        )
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
                armory_rel_items=None,
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
                armory_rel_items=None,
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
                armory_rel_items=None,
                source="warmane-api-bridge",
                include_raw=False,
                error=f"parse error: {exc}",
            )

        results[key] = result

    if cache_dirty:
        save_item_ilvl_cache(item_ilvl_cache_path, item_ilvl_cache)

    if args.dry_run:
        print(
            json.dumps(
                {
                    "generatedAt": generated_at,
                    "results": results,
                    "reportFiles": report_files,
                    "processedReportQueueIds": processed_report_queue_ids,
                },
                indent=2,
                ensure_ascii=False,
            )
        )
        return 0

    write_bridge_file(
        bridge_output_path,
        results,
        generated_at,
        report_files=report_files,
        processed_report_queue_ids=processed_report_queue_ids,
    )
    print(
        f"Wrote {len(results)} result(s) and cataloged {len(report_files)} report file(s) to: {bridge_output_path}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
