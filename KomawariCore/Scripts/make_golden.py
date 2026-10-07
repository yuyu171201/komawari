"""Swift 版の照合用データを Python 版から書き出す。

リポジトリのルートで実行する:

    uv run python KomawariCore/Scripts/make_golden.py

Tests/KomawariCoreTests/Golden/ に、時間割（JSON）と Python 版の展開結果、
jpholiday の祝日一覧を書き出す。Swift のテストがこれと同じ結果になるかを確かめる。
"""

from __future__ import annotations

import datetime as dt
import json
from pathlib import Path

import jpholiday
import yaml

from komawari.config import _Loader, parse_config
from komawari.export import timetable_json
from komawari.core import expand_term, monday_of, week_summary, week_view

ROOT = Path(__file__).resolve().parents[2]
OUT = Path(__file__).resolve().parents[1] / "Tests" / "KomawariCoreTests" / "Golden"
HOLIDAY_YEARS = range(2020, 2061)

# 例外の全種類・ターム別授業・学期外の補講・土曜授業・同名2コマをまとめて通す時間割
SYNTHETIC = """
term: {start: 2026-04-08, end: 2026-08-04}
terms:
  1: {start: 2026-04-08, end: 2026-06-08}
  2: {start: 2026-06-09, end: 2026-08-04}
periods:
  1: {start: "08:45", end: "10:15"}
  2: {start: "10:30", end: "12:00"}
  3: {start: "12:50", end: "14:20"}
  4: {start: "14:35", end: "16:05"}
classes:
  - {name: 線形代数, weekday: 0, period: 1, room: A1, term: 1}
  - {name: 線形代数, weekday: 0, period: 2, room: A1, term: 1}
  - {name: 統計学, weekday: 0, period: 1, room: B2, term: 2}
  - {name: 英語, weekday: 1, period: 3, room: C3}
  - {name: 実験, weekday: 2, period: 3, term: 1}
  - {name: 実験, weekday: 2, period: 4, term: 1}
  - {name: ゼミ, weekday: 3, start: "18:10", end: "19:40", room: 研究室}
  - {name: 体育, weekday: 5, period: 1, room: 体育館, term: 2}
  - {name: アルゴリズム, weekday: 4, period: 2, room: D4}
  - {name: あいうえお, weekday: 4, period: 2}
exceptions:
  - {date: 2026-05-01, as_weekday: 2}
  - {date: 2026-05-07, as_weekday: 1}
  - {date: 2026-05-07, class: 英語, room: Z9}
  - {date: 2026-04-29, off: false}
  - {date: 2026-07-20, as_weekday: 0}
  - {date: 2026-06-15, off: true}
  - {date: 2026-06-15, extra: {name: 集中講義, period: 2, room: E5}}
  - {date: 2026-04-13, class: 線形代数, period: 2, room: A9}
  - {date: 2026-04-20, class: 線形代数, off: true}
  - {date: 2026-04-27, class: 線形代数, room: A1}
  - {date: 2026-05-11, class: 線形代数, room: A7}
  - {date: 2026-05-11, class: 線形代数, period: 1, off: true}
  - {date: 2026-06-20, extra: {name: 英語, start: "9:00", end: "10:30"}}
  - {date: 2026-06-21, extra: {name: 英語, period: 1}}
  - {date: 2026-08-10, extra: {name: 再試験, period: 3, room: C3}}
  - {date: 2026-03-30, extra: {name: ガイダンス, start: "13:00", end: "14:00"}}
  - {date: 2026-07-18, off: true}
  - {date: 2026-05-13, class: 実験, off: true, makeup: {date: 2026-05-16, periods: [1, 2]}}
  - {date: 2026-05-20, class: 実験, period: 3, off: true, makeup: pending}
  - {date: 2026-05-12, class: 英語, off: true, makeup: {date: 2026-08-12, periods: [4], room: Z1}}
  - {date: 2026-06-16, class: 英語, off: true, makeup: {date: 2026-06-15, periods: [2]}}
"""


def day_json(day) -> dict:
    return {
        "date": day.date.isoformat(),
        "effective_weekday": day.effective_weekday,
        "status": day.status,
        "off_reason": day.off_reason,
        "holiday": day.holiday,
        "classes": [
            {
                "name": s.name,
                "period": s.period,
                "start": f"{s.start:%H:%M}",
                "end": f"{s.end:%H:%M}",
                "room": s.room,
                "status": s.status,
                "original_room": s.original_room,
                "makeup_date": s.makeup_date.isoformat() if s.makeup_date else None,
                "makeup_pending": s.makeup_pending,
            }
            for s in day.classes
        ],
    }


def case(name: str, text: str) -> dict:
    raw = yaml.load(text, Loader=_Loader)
    cfg = parse_config(raw)
    days = list(expand_term(cfg))

    weeks = []
    monday = monday_of(days[0].date) - dt.timedelta(days=7)
    while monday <= days[-1].date + dt.timedelta(days=7):
        view = week_view(cfg, monday)
        weeks.append(
            {
                "monday": monday.isoformat(),
                "dates": [d.date.isoformat() for d in view],
                "summary": week_summary(view),
            }
        )
        monday += dt.timedelta(days=7)

    return {
        "name": name,
        "timetable": timetable_json(raw),
        "days": [day_json(d) for d in days],
        "weeks": weeks,
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    cases = [
        case("fixture", (ROOT / "tests/fixtures/timetable.yaml").read_text(encoding="utf-8")),
        case("example", (ROOT / "timetable.example.yaml").read_text(encoding="utf-8")),
        case("synthetic", SYNTHETIC),
    ]
    holidays = {
        d.isoformat(): name for year in HOLIDAY_YEARS for d, name in jpholiday.year_holidays(year)
    }
    dump = lambda data: json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True) + "\n"
    (OUT / "cases.json").write_text(dump(cases), encoding="utf-8")
    (OUT / "holidays.json").write_text(
        dump({"from": HOLIDAY_YEARS[0], "to": HOLIDAY_YEARS[-1], "holidays": holidays}),
        encoding="utf-8",
    )
    for c in cases:
        print(f"{c['name']}: {len(c['days'])} 日, {len(c['weeks'])} 週")
    print(f"祝日: {len(holidays)} 件 ({HOLIDAY_YEARS[0]}〜{HOLIDAY_YEARS[-1]})")


if __name__ == "__main__":
    main()
