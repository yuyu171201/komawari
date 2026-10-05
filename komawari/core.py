"""時間割の展開ロジック。

繰り返しルールは使わず、日付ごとに「その日は何曜日の授業か」を決めて展開する。
週ビュー・CLI・.ics 生成はすべてここの関数を使う。
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass
from datetime import date, time, timedelta

import jpholiday

from .config import Config

WEEKDAYS_JA = "月火水木金土日"

# 授業・日の状態
NORMAL = "normal"
SWAPPED = "swapped"
OFF = "off"
EXTRA = "extra"
ROOM_CHANGED = "room_changed"

# 日が休みになった理由
REASON_EXCEPTION = "exception"
REASON_HOLIDAY = "holiday"
REASON_OUT_OF_TERM = "out_of_term"


@dataclass(frozen=True)
class Session:
    """ある日付に展開された授業1コマ。"""

    date: date
    name: str
    start: time
    end: time
    period: int | None
    room: str | None
    status: str  # normal / swapped / off / extra / room_changed
    original_room: str | None = None  # 教室変更前の教室


@dataclass(frozen=True)
class Day:
    date: date
    effective_weekday: int  # 振替を反映した「何曜日の授業か」
    status: str  # normal / swapped / off
    off_reason: str | None  # status が off のときの理由
    holiday: str | None  # 祝日名（授業がある場合も入る）
    classes: tuple[Session, ...]  # 休講になった授業も status=off で含む

    @property
    def active(self) -> tuple[Session, ...]:
        """実際に行われる授業。"""
        return tuple(s for s in self.classes if s.status != OFF)


def expand_day(cfg: Config, d: date) -> Day:
    """日付 d の授業を、例外と祝日を反映して展開する。"""
    exc = cfg.exceptions.get(d)
    holiday = jpholiday.is_holiday_name(d)
    in_term = cfg.term_start <= d <= cfg.term_end
    swapped = exc is not None and exc.as_weekday is not None
    weekday = exc.as_weekday if swapped else d.weekday()

    off_reason = None
    if not in_term:
        off_reason = REASON_OUT_OF_TERM
    elif exc is not None and exc.off:
        off_reason = REASON_EXCEPTION
    elif holiday and not (swapped or (exc is not None and exc.off is False)):
        # 祝日は休み。ただし例外で振替や off: false が明示されていれば授業を行う
        off_reason = REASON_HOLIDAY

    sessions = []
    if in_term:
        for c in cfg.classes:
            if c.weekday != weekday or not c.runs_on(d):
                continue
            status = SWAPPED if swapped else NORMAL
            room, original_room = c.room, None
            for ch in exc.changes if exc else ():
                if ch.name != c.name or (ch.period is not None and ch.period != c.period):
                    continue
                if ch.off:
                    status = OFF
                elif ch.room != c.room:
                    room, original_room = ch.room, c.room
                    if status != OFF:
                        status = ROOM_CHANGED
            if off_reason:
                status = OFF
            sessions.append(Session(d, c.name, c.start, c.end, c.period, room, status, original_room))

    # 補講は日付を明示した追加なので、休みの日や学期外でもそのまま載せる
    for c in exc.extras if exc else ():
        sessions.append(Session(d, c.name, c.start, c.end, c.period, c.room, EXTRA))

    sessions.sort(key=lambda s: (s.start, s.end, s.name))
    day_status = OFF if off_reason else SWAPPED if swapped else NORMAL
    return Day(d, weekday, day_status, off_reason, holiday, tuple(sessions))


def monday_of(d: date) -> date:
    return d - timedelta(days=d.weekday())


def week_view(cfg: Config, d: date) -> list[Day]:
    """d を含む週の日ごとの授業を返す。月〜金は必ず含み、土日は授業がある場合だけ含む。"""
    monday = monday_of(d)
    days = [expand_day(cfg, monday + timedelta(days=i)) for i in range(7)]
    saturday, sunday = days[5], days[6]
    result = days[:5]
    if saturday.classes or sunday.classes:
        result.append(saturday)
    if sunday.classes:
        result.append(sunday)
    return result


def expand_term(cfg: Config) -> Iterator[Day]:
    """学期の全日付（学期外に補講があればその日まで）を走査して展開する。"""
    extra_dates = [d for d, e in cfg.exceptions.items() if e.extras]
    start = min([cfg.term_start, *extra_dates])
    end = max([cfg.term_end, *extra_dates])
    for i in range((end - start).days + 1):
        yield expand_day(cfg, start + timedelta(days=i))


def week_summary(days: list[Day]) -> list[str]:
    """週の変更点を短い文のリストにする（例: 「水曜が月曜授業」）。変更がなければ空。"""
    weekdays = [d for d in days if d.date.weekday() < 5]
    out_of_term = [d.off_reason == REASON_OUT_OF_TERM for d in weekdays]

    items = []
    if all(out_of_term):
        items.append("学期外")
    elif out_of_term[0]:
        first = next(d for d in weekdays if d.off_reason != REASON_OUT_OF_TERM)
        items.append(f"{_short_date(first.date)}から授業開始")
    elif out_of_term[-1]:
        last = next(d for d in reversed(weekdays) if d.off_reason != REASON_OUT_OF_TERM)
        items.append(f"{_short_date(last.date)}で授業終了")

    for day in days:
        wd = WEEKDAYS_JA[day.date.weekday()] + "曜"
        if day.status == SWAPPED:
            items.append(f"{wd}が{WEEKDAYS_JA[day.effective_weekday]}曜授業")
        elif day.off_reason == REASON_EXCEPTION:
            items.append(f"{wd}が休講")
        elif day.off_reason == REASON_HOLIDAY:
            items.append(f"{wd}が祝日（{day.holiday}）")
        elif day.holiday and day.off_reason is None:
            items.append(f"{wd}が祝日（{day.holiday}）だが授業あり")

        for s in day.classes:
            if s.status == EXTRA:
                items.append(f"{wd}に補講「{s.name}」")
            elif s.status == ROOM_CHANGED:
                items.append(f"{wd}の{s.name}が{s.room}に教室変更")
            elif s.status == OFF and day.status != OFF:
                items.append(f"{wd}の{s.name}が休講")
    # 同じ授業が1日に複数コマあると同じ文が並ぶので、1つにまとめる
    return list(dict.fromkeys(items))


def _short_date(d: date) -> str:
    return f"{d.month}/{d.day}({WEEKDAYS_JA[d.weekday()]})"
