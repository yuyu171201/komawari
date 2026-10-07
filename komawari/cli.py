"""コマンドライン: 今週の予定の表示、.ics の書き出し、サーバーの起動。"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import date
from pathlib import Path

from .config import Config, ConfigError, load_config
from .core import (
    EXTRA,
    OFF,
    REASON_EXCEPTION,
    REASON_HOLIDAY,
    REASON_OUT_OF_TERM,
    ROOM_CHANGED,
    SWAPPED,
    WEEKDAYS_JA,
    Day,
    Session,
    monday_of,
    week_summary,
    week_view,
)
from .export import export_json
from .ics import build_ics

DEFAULT_CONFIG = "timetable.yaml"
CONFIG_ENV = "KOMAWARI_CONFIG"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="komawari", description="大学の時間割を管理する")
    parser.add_argument(
        "-c",
        "--config",
        default=os.environ.get(CONFIG_ENV, DEFAULT_CONFIG),
        help=f"時間割のYAML（既定: ${CONFIG_ENV} または {DEFAULT_CONFIG}）",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    week = sub.add_parser("week", help="週の予定をターミナルに表示する")
    week.add_argument(
        "-d", "--date", type=date.fromisoformat, help="この日を含む週を表示する（既定: 今日）"
    )

    ics = sub.add_parser("ics", help=".ics をファイルに出力する")
    ics.add_argument("-o", "--output", default="timetable.ics", help="出力先（- で標準出力）")

    export = sub.add_parser("json", help="iPhone アプリ用の JSON をファイルに出力する")
    export.add_argument("-o", "--output", default="timetable.json", help="出力先（- で標準出力）")

    serve = sub.add_parser("serve", help="週ビューと .ics を配信するサーバーを起動する")
    serve.add_argument("--host", default="127.0.0.1")
    serve.add_argument("--port", type=int, default=8000)

    args = parser.parse_args(argv)

    if args.command == "serve":
        import uvicorn

        from .api import create_app

        uvicorn.run(create_app(args.config), host=args.host, port=args.port)
        return 0

    try:
        cfg = load_config(args.config)
    except (ConfigError, OSError) as e:
        print(f"komawari: {args.config}: {e}", file=sys.stderr)
        return 1

    if args.command == "json":
        try:
            text = json.dumps(export_json(args.config), ensure_ascii=False, indent=2) + "\n"
        except (ConfigError, OSError) as e:
            print(f"komawari: {args.config}: {e}", file=sys.stderr)
            return 1
        if args.output == "-":
            sys.stdout.write(text)
        else:
            Path(args.output).write_text(text, encoding="utf-8")
            print(f"{args.output} に書き出しました")
        return 0

    if args.command == "week":
        print(format_week(cfg, args.date or date.today(), today=date.today()))
    elif args.command == "ics":
        text = build_ics(cfg)
        if args.output == "-":
            sys.stdout.write(text)
        else:
            # .ics の改行は CRLF 固定なので、改行変換をさせない
            Path(args.output).write_text(text, encoding="utf-8", newline="")
            print(f"{args.output} に書き出しました")
    return 0


def format_week(cfg: Config, d: date, today: date) -> str:
    days = week_view(cfg, d)
    first, last = days[0].date, days[-1].date
    offset = (monday_of(d) - monday_of(today)).days // 7
    prefix = {0: "今週は", 1: "来週は", -1: "先週は"}.get(offset, "この週は")
    summary = "、".join(week_summary(days)) or "通常どおり"

    lines = [f"{first:%Y-%m-%d} 〜 {last:%m-%d}", f"{prefix}{summary}", ""]
    for day in days:
        mark = "  ← 今日" if day.date == today else ""
        lines.append(f"{_day_heading(day)}{mark}")
        if not day.classes:
            lines.append("  授業なし")
        for s in day.classes:
            lines.append(f"  {_session_line(s)}")
    return "\n".join(lines)


def _day_heading(day: Day) -> str:
    d = day.date
    heading = f"{d.month}/{d.day}({WEEKDAYS_JA[d.weekday()]})"
    if day.status == SWAPPED:
        heading += f" → {WEEKDAYS_JA[day.effective_weekday]}曜授業"
    elif day.off_reason == REASON_EXCEPTION:
        heading += " 休講"
    elif day.off_reason == REASON_HOLIDAY:
        heading += f" 祝日（{day.holiday}）"
    elif day.off_reason == REASON_OUT_OF_TERM:
        heading += " 学期外"
    elif day.holiday:
        heading += f" 祝日（{day.holiday}）授業あり"
    return heading


def _session_line(s: Session) -> str:
    slot = f"{s.period}コマ" if s.period is not None else "     "
    line = f"{slot} {s.start:%H:%M}-{s.end:%H:%M}  {s.name}"
    if s.room:
        line += f"  @{s.room}"
    if s.status == ROOM_CHANGED:
        line += f"  [教室変更 ← {s.original_room or '未定'}]"
    elif s.status == SWAPPED:
        line += "  [振替]"
    elif s.status == EXTRA:
        line += "  [補講]"
    elif s.status == OFF:
        line += "  [休講]"
        if s.makeup_date:
            line += f"  補講 {s.makeup_date.month}/{s.makeup_date.day}"
        elif s.makeup_pending:
            line += "  補講未定"
    return line


if __name__ == "__main__":
    sys.exit(main())
