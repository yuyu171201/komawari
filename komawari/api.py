"""FastAPI: 週ビュー用 JSON と購読用 .ics、Web UI の配信。"""

from __future__ import annotations

import os
from datetime import date
from pathlib import Path

from fastapi import FastAPI, Query, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from .config import Config, ConfigError, load_config
from .core import Day, Session, monday_of, week_summary, week_view
from .ics import build_ics

STATIC_DIR = Path(__file__).parent / "static"


class ConfigStore:
    """YAML を読み込んで保持し、ファイルが更新されていたら読み直す。"""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._mtime: int | None = None
        self._cfg: Config | None = None

    def get(self) -> Config:
        mtime = self.path.stat().st_mtime_ns
        if self._cfg is None or mtime != self._mtime:
            self._cfg = load_config(self.path)
            self._mtime = mtime
        return self._cfg


def create_app(config_path: str | Path) -> FastAPI:
    app = FastAPI(title="Komawari")
    store = ConfigStore(config_path)

    @app.exception_handler(ConfigError)
    @app.exception_handler(OSError)
    async def config_error(request: Request, exc: Exception) -> JSONResponse:
        return JSONResponse(status_code=500, content={"detail": f"{store.path.name}: {exc}"})

    @app.get("/week")
    def week(day: date | None = Query(None, alias="date", description="この日を含む週")) -> dict:
        cfg = store.get()
        today = date.today()
        days = week_view(cfg, day or today)
        return {
            "week_start": monday_of(day or today).isoformat(),
            "today": today.isoformat(),
            "term": {"start": cfg.term_start.isoformat(), "end": cfg.term_end.isoformat()},
            "periods": [
                {"number": p.number, "start": f"{p.start:%H:%M}", "end": f"{p.end:%H:%M}"}
                for p in sorted(cfg.periods.values(), key=lambda p: p.start)
            ],
            "summary": week_summary(days),
            "days": [_day_json(d) for d in days],
        }

    @app.get("/timetable.ics")
    def timetable_ics() -> Response:
        return Response(build_ics(store.get()), media_type="text/calendar; charset=utf-8")

    @app.get("/", include_in_schema=False)
    def index() -> FileResponse:
        return FileResponse(STATIC_DIR / "index.html")

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    return app


def _day_json(day: Day) -> dict:
    return {
        "date": day.date.isoformat(),
        "weekday": day.date.weekday(),
        "effective_weekday": day.effective_weekday,
        "status": day.status,
        "off_reason": day.off_reason,
        "holiday": day.holiday,
        "classes": [_session_json(s) for s in day.classes],
    }


def _session_json(s: Session) -> dict:
    return {
        "name": s.name,
        "period": s.period,
        "start": f"{s.start:%H:%M}",
        "end": f"{s.end:%H:%M}",
        "room": s.room,
        "status": s.status,
        "original_room": s.original_room,
    }


# `uvicorn komawari.api:app` で直接起動する場合用
app = create_app(os.environ.get("KOMAWARI_CONFIG", "timetable.yaml"))
