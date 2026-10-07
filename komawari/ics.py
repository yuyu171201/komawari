""".ics の生成。授業を1コマずつ個別イベントとして出力する。"""

from __future__ import annotations

import hashlib
from datetime import date, datetime, time, timezone

from .config import Config
from .core import EXTRA, ROOM_CHANGED, SWAPPED, WEEKDAYS_JA, Day, Session, expand_term

TZID = "Asia/Tokyo"
CALENDAR_NAME = "時間割"


def build_ics(cfg: Config, now: datetime | None = None) -> str:
    stamp = (now or datetime.now(timezone.utc)).astimezone(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    lines = [
        "BEGIN:VCALENDAR",
        "VERSION:2.0",
        "PRODID:-//Komawari//Timetable//JA",
        "CALSCALE:GREGORIAN",
        "METHOD:PUBLISH",
        f"X-WR-CALNAME:{_escape(CALENDAR_NAME)}",
        f"X-WR-TIMEZONE:{TZID}",
        "BEGIN:VTIMEZONE",
        f"TZID:{TZID}",
        "BEGIN:STANDARD",
        "DTSTART:19700101T000000",
        "TZOFFSETFROM:+0900",
        "TZOFFSETTO:+0900",
        "TZNAME:JST",
        "END:STANDARD",
        "END:VTIMEZONE",
    ]
    for day in expand_term(cfg):
        seen: set[str] = set()
        for s in day.active:
            lines += _event(day, s, stamp, seen)
    lines.append("END:VCALENDAR")
    return "".join(_fold(line) + "\r\n" for line in lines)


def _event(day: Day, s: Session, stamp: str, seen: set[str]) -> list[str]:
    swapped = day.status == SWAPPED and s.status != EXTRA
    summary = s.name
    notes = []
    if s.period is not None:
        notes.append(f"{s.period}コマ")
    if swapped:
        summary += "（振替）"
        notes.append(
            f"振替: {WEEKDAYS_JA[s.date.weekday()]}曜に{WEEKDAYS_JA[day.effective_weekday]}曜の授業"
        )
    if s.status == EXTRA:
        summary += "（補講）"
        notes.append("補講")
    if s.status == ROOM_CHANGED:
        notes.append(f"教室変更: {s.original_room or '未定'} → {s.room}")

    lines = [
        "BEGIN:VEVENT",
        f"UID:{_uid(s, seen)}",
        f"DTSTAMP:{stamp}",
        f"DTSTART;TZID={TZID}:{_local(s.date, s.start)}",
        f"DTEND;TZID={TZID}:{_local(s.date, s.end)}",
        f"SUMMARY:{_escape(summary)}",
    ]
    if s.room:
        lines.append(f"LOCATION:{_escape(s.room)}")
    if notes:
        lines.append(f"DESCRIPTION:{_escape(chr(10).join(notes))}")
    lines.append("END:VEVENT")
    return lines


def _uid(s: Session, seen: set[str]) -> str:
    """「日付＋授業名」で固定の UID。同じ日に同名の授業が複数あるときだけ開始時刻を足す。"""
    digest = hashlib.sha1(s.name.encode("utf-8")).hexdigest()[:12]
    key = f"{s.date:%Y%m%d}-{digest}"
    if key in seen:
        key += f"-{s.start:%H%M}"
    seen.add(key)
    return f"{key}@komawari"


def _local(d: date, t: time) -> str:
    return f"{d:%Y%m%d}T{t:%H%M%S}"


def _escape(text: str) -> str:
    return (
        text.replace("\\", "\\\\")
        .replace(";", "\\;")
        .replace(",", "\\,")
        .replace("\n", "\\n")
    )


def _fold(line: str) -> str:
    """75オクテットを超える行を、マルチバイト文字を割らずに折り返す。"""
    parts, current, size = [], "", 0
    for ch in line:
        n = len(ch.encode("utf-8"))
        if size + n > 75:
            parts.append(current)
            current, size = " ", 1
        current += ch
        size += n
    parts.append(current)
    return "\r\n".join(parts)
