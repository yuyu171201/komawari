"""timetable.yaml の読み込みと検証。"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import date, datetime, time
from pathlib import Path
from typing import Any

import yaml


class ConfigError(ValueError):
    """timetable.yaml の内容が不正。"""


@dataclass(frozen=True)
class Period:
    number: int
    start: time
    end: time


@dataclass(frozen=True)
class Course:
    """授業1件。通常授業は weekday を持ち、補講は持たない。"""

    name: str
    start: time
    end: time
    weekday: int | None = None
    period: int | None = None
    room: str | None = None


@dataclass(frozen=True)
class ClassChange:
    """特定の日の特定の授業に対する変更（教室変更・その授業だけ休講）。"""

    name: str
    period: int | None = None
    room: str | None = None
    off: bool = False


@dataclass
class DayException:
    """同じ日付の例外行をまとめたもの。"""

    date: date
    off: bool | None = None  # True=休講 / False=祝日でも授業あり / None=指定なし
    as_weekday: int | None = None
    extras: list[Course] = field(default_factory=list)
    changes: list[ClassChange] = field(default_factory=list)


@dataclass
class Config:
    term_start: date
    term_end: date
    periods: dict[int, Period]
    classes: list[Course]
    exceptions: dict[date, DayException]


class _Loader(yaml.SafeLoader):
    """真偽値を true / false だけに絞ったローダー。

    PyYAML (YAML 1.1) は on / off / yes / no も真偽値として読むため、
    そのままだと例外の `off` キーが False になってしまう。
    """


_BOOL_TAG = "tag:yaml.org,2002:bool"
_Loader.yaml_implicit_resolvers = {
    first: [(tag, pattern) for tag, pattern in resolvers if tag != _BOOL_TAG]
    for first, resolvers in yaml.SafeLoader.yaml_implicit_resolvers.items()
}
_Loader.add_implicit_resolver(_BOOL_TAG, re.compile(r"^(?:true|True|TRUE|false|False|FALSE)$"), list("tTfF"))


def load_config(path: str | Path) -> Config:
    return parse_text(Path(path).read_text(encoding="utf-8"))


def parse_text(text: str) -> Config:
    try:
        raw = yaml.load(text, Loader=_Loader)
    except yaml.YAMLError as e:
        raise ConfigError(f"YAML として読めません: {e}") from e
    return parse_config(raw)


def parse_config(raw: Any) -> Config:
    if not isinstance(raw, dict):
        raise ConfigError("トップレベルはマッピングにしてください")

    term = _mapping(raw.get("term"), "term")
    term_start = _parse_date(_require(term, "start", "term"), "term.start")
    term_end = _parse_date(_require(term, "end", "term"), "term.end")
    if term_start > term_end:
        raise ConfigError("term: start が end より後になっています")

    periods = _parse_periods(raw.get("periods") or {})

    classes = []
    for i, c in enumerate(_sequence(raw.get("classes"), "classes")):
        classes.append(_parse_course(c, periods, f"classes[{i}]", regular=True))

    exceptions: dict[date, DayException] = {}
    for i, e in enumerate(_sequence(raw.get("exceptions"), "exceptions")):
        _parse_exception(e, periods, exceptions, f"exceptions[{i}]")

    cfg = Config(term_start, term_end, periods, classes, exceptions)
    _check_changes(cfg)
    return cfg


def _parse_periods(raw: Any) -> dict[int, Period]:
    periods = {}
    for number, span in _mapping(raw, "periods").items():
        where = f"periods.{number}"
        if not isinstance(number, int) or isinstance(number, bool):
            raise ConfigError(f"{where}: コマ番号は整数にしてください")
        span = _mapping(span, where)
        start = _parse_time(_require(span, "start", where), f"{where}.start")
        end = _parse_time(_require(span, "end", where), f"{where}.end")
        if start >= end:
            raise ConfigError(f"{where}: start が end 以降になっています")
        periods[number] = Period(number, start, end)
    return periods


def _parse_course(raw: Any, periods: dict[int, Period], where: str, *, regular: bool) -> Course:
    raw = _mapping(raw, where)
    allowed = {"name", "period", "start", "end", "room"} | ({"weekday"} if regular else set())
    _reject_unknown(raw, allowed, where)

    name = str(_require(raw, "name", where))
    weekday = _parse_weekday(_require(raw, "weekday", where), f"{where}.weekday") if regular else None
    room = None if raw.get("room") is None else str(raw["room"])

    has_period = "period" in raw
    has_times = "start" in raw or "end" in raw
    if has_period == has_times:
        raise ConfigError(f"{where}: `period` か `start`/`end` のどちらか一方を指定してください")
    if has_period:
        period = _parse_period_ref(raw["period"], periods, where)
        return Course(name, periods[period].start, periods[period].end, weekday, period, room)

    start = _parse_time(_require(raw, "start", where), f"{where}.start")
    end = _parse_time(_require(raw, "end", where), f"{where}.end")
    if start >= end:
        raise ConfigError(f"{where}: start が end 以降になっています")
    return Course(name, start, end, weekday, None, room)


def _parse_exception(
    raw: Any, periods: dict[int, Period], exceptions: dict[date, DayException], where: str
) -> None:
    raw = _mapping(raw, where)
    d = _parse_date(_require(raw, "date", where), f"{where}.date")
    exc = exceptions.setdefault(d, DayException(d))
    keys = set(raw) - {"date"}

    if "extra" in keys:
        _reject_unknown(raw, {"date", "extra"}, where)
        exc.extras.append(_parse_course(raw["extra"], periods, f"{where}.extra", regular=False))
    elif "class" in keys:
        _reject_unknown(raw, {"date", "class", "period", "room", "off"}, where)
        period = None
        if "period" in raw:
            period = _parse_period_ref(raw["period"], periods, where)
        off = _parse_bool(raw.get("off", False), f"{where}.off")
        room = None if raw.get("room") is None else str(raw["room"])
        if off == (room is not None):
            raise ConfigError(f"{where}: `class` には `room` か `off: true` のどちらか一方を指定してください")
        exc.changes.append(ClassChange(str(raw["class"]), period, room, off))
    elif "as_weekday" in keys:
        _reject_unknown(raw, {"date", "as_weekday"}, where)
        if exc.as_weekday is not None:
            raise ConfigError(f"{where}: {d} の `as_weekday` が重複しています")
        exc.as_weekday = _parse_weekday(raw["as_weekday"], f"{where}.as_weekday")
    elif "off" in keys:
        _reject_unknown(raw, {"date", "off"}, where)
        if exc.off is not None:
            raise ConfigError(f"{where}: {d} の `off` が重複しています")
        exc.off = _parse_bool(raw["off"], f"{where}.off")
    else:
        raise ConfigError(
            f"{where}: `as_weekday` / `off` / `extra` / `class` のいずれかを指定してください"
        )

    if exc.off and exc.as_weekday is not None:
        raise ConfigError(f"{where}: {d} に `off: true` と `as_weekday` の両方があります")


def _check_changes(cfg: Config) -> None:
    """教室変更などの対象が、その日に実際にある授業かを確かめる（授業名の打ち間違い対策）。"""
    for d, exc in cfg.exceptions.items():
        if not exc.changes:
            continue
        weekday = d.weekday() if exc.as_weekday is None else exc.as_weekday
        in_term = cfg.term_start <= d <= cfg.term_end
        for ch in exc.changes:
            hit = in_term and any(
                c.weekday == weekday
                and c.name == ch.name
                and (ch.period is None or c.period == ch.period)
                for c in cfg.classes
            )
            if not hit:
                target = ch.name if ch.period is None else f"{ch.name}（{ch.period}限）"
                raise ConfigError(f"exceptions: {d} に「{target}」の授業はありません")


def _require(mapping: dict, key: str, where: str) -> Any:
    if key not in mapping:
        raise ConfigError(f"{where}: `{key}` がありません")
    return mapping[key]


def _mapping(value: Any, where: str) -> dict:
    if not isinstance(value, dict):
        raise ConfigError(f"{where}: マッピングにしてください")
    return value


def _sequence(value: Any, where: str) -> list:
    if value is None:
        return []
    if not isinstance(value, list):
        raise ConfigError(f"{where}: リストにしてください")
    return value


def _reject_unknown(raw: dict, allowed: set[str], where: str) -> None:
    unknown = sorted(str(k) for k in set(raw) - allowed)
    if unknown:
        raise ConfigError(f"{where}: 使えないキーがあります: {', '.join(unknown)}")


def _parse_date(value: Any, where: str) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return date.fromisoformat(value)
        except ValueError:
            pass
    raise ConfigError(f"{where}: 日付は YYYY-MM-DD で書いてください: {value!r}")


def _parse_time(value: Any, where: str) -> time:
    # YAML 1.1 は引用符なしの 10:30 を60進数の整数 (630) として読む
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value < 24 * 60:
        return time(*divmod(value, 60))
    if isinstance(value, str):
        try:
            return datetime.strptime(value.strip(), "%H:%M").time()
        except ValueError:
            pass
    raise ConfigError(f"{where}: 時刻は HH:MM で書いてください: {value!r}")


def _parse_weekday(value: Any, where: str) -> int:
    if isinstance(value, int) and not isinstance(value, bool) and 0 <= value <= 6:
        return value
    raise ConfigError(f"{where}: 曜日は 0（月）〜 6（日）の整数にしてください: {value!r}")


def _parse_bool(value: Any, where: str) -> bool:
    if isinstance(value, bool):
        return value
    raise ConfigError(f"{where}: true か false にしてください: {value!r}")


def _parse_period_ref(value: Any, periods: dict[int, Period], where: str) -> int:
    if isinstance(value, bool) or value not in periods:
        raise ConfigError(f"{where}: コマ番号 {value!r} は `periods` にありません")
    return value
