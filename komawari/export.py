"""timetable.yaml を、Swift 版（KomawariCore の Timetable）が読める JSON にする。"""

from __future__ import annotations

import datetime as dt
from pathlib import Path

import yaml

from .config import ConfigError, _Loader, _parse_time, parse_config


def export_json(path: str | Path) -> dict:
    """YAML を検証したうえで、JSON にできる辞書として返す。"""
    try:
        raw = yaml.load(Path(path).read_text(encoding="utf-8"), Loader=_Loader)
    except yaml.YAMLError as e:
        raise ConfigError(f"YAML として読めません: {e}") from e
    parse_config(raw)
    return timetable_json(raw)


def timetable_json(raw: dict) -> dict:
    """YAML を読んだままの辞書（検証済み）を、日付・時刻を文字列にそろえた形にする。"""
    return {
        "term": _span(raw["term"]),
        "terms": {str(k): _span(v) for k, v in (raw.get("terms") or {}).items()},
        "periods": {
            str(k): {"start": _hhmm(v["start"]), "end": _hhmm(v["end"])}
            for k, v in (raw.get("periods") or {}).items()
        },
        "classes": [_course(c) for c in raw.get("classes") or []],
        "exceptions": [_exception(e) for e in raw.get("exceptions") or []],
    }


def _iso(value) -> str:
    return value.isoformat() if isinstance(value, dt.date) else str(value)


def _hhmm(value) -> str:
    return f"{_parse_time(value, 'time'):%H:%M}"


def _span(raw: dict) -> dict:
    return {"start": _iso(raw["start"]), "end": _iso(raw["end"])}


def _course(raw: dict) -> dict:
    out = {"name": str(raw["name"])}
    if "weekday" in raw:
        out["weekday"] = raw["weekday"]
    if "period" in raw:
        out["period"] = raw["period"]
    else:
        out |= {"start": _hhmm(raw["start"]), "end": _hhmm(raw["end"])}
    if raw.get("room") is not None:
        out["room"] = str(raw["room"])
    if raw.get("term") is not None:
        out["term"] = str(raw["term"])
    return out


def _exception(raw: dict) -> dict:
    out = {"date": _iso(raw["date"])}
    for key, value in raw.items():
        if key == "extra":
            out["extra"] = _course(value)
        elif key == "makeup" and isinstance(value, dict):
            out["makeup"] = {"date": _iso(value["date"]), "periods": list(value["periods"])}
            if value.get("room") is not None:
                out["makeup"]["room"] = str(value["room"])
        elif key != "date":
            out[key] = str(value) if key in ("class", "room") else value
    return out
