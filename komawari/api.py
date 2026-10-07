"""FastAPI: 週ビュー用 JSON と購読用 .ics、例外の編集、Web UI の配信。"""

from __future__ import annotations

import os
import threading
from datetime import date
from pathlib import Path
from typing import Any

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.responses import FileResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from .config import Config, ConfigError, entry_id, load_config
from .core import Day, Session, monday_of, week_summary, week_view
from .editor import edit_exceptions
from .ics import build_ics

STATIC_DIR = Path(__file__).parent / "static"


class ConfigStore:
    """YAML を読み込んで保持し、ファイルが更新されていたら読み直す。"""

    def __init__(self, path: str | Path):
        self.path = Path(path)
        self._mtime: int | None = None
        self._cfg: Config | None = None
        self._lock = threading.Lock()

    def get(self) -> Config:
        mtime = self.path.stat().st_mtime_ns
        if self._cfg is None or mtime != self._mtime:
            self._cfg = load_config(self.path)
            self._mtime = mtime
        return self._cfg

    def edit(self, *, add: list[dict] = (), remove: list[str] = ()) -> list[dict]:
        """例外を追加・削除して YAML に書き戻す。"""
        with self._lock:
            return edit_exceptions(self.path, add=add, remove=remove)


class ExceptionEdit(BaseModel):
    """追加する例外（YAML の1行と同じ形）と、削除する例外の id。"""

    add: list[dict[str, Any]] = []
    remove: list[str] = []


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
            "class_names": sorted({c.name for c in cfg.classes}),
            "summary": week_summary(days),
            "days": [_day_json(d, cfg) for d in days],
        }

    @app.post("/exceptions")
    def edit(body: ExceptionEdit, request: Request) -> dict:
        # 他サイトのページからフォーム送信で書き換えられないよう、JSON 以外は受け付けない
        if request.headers.get("content-type", "").split(";")[0].strip() != "application/json":
            raise HTTPException(415, "Content-Type は application/json にしてください")
        return {"added": [_entry_json(e) for e in _edit(add=body.add, remove=body.remove)]}

    @app.delete("/exceptions/{exception_id}", status_code=204)
    def delete(exception_id: str) -> None:
        _edit(remove=[exception_id])

    def _edit(**changes) -> list[dict]:
        try:
            return store.edit(**changes)
        except LookupError:
            raise HTTPException(404, "その変更は見つかりません（すでに削除されています）")
        except ConfigError as e:
            raise HTTPException(400, str(e))

    @app.get("/timetable.ics")
    def timetable_ics() -> Response:
        return Response(build_ics(store.get()), media_type="text/calendar; charset=utf-8")

    @app.get("/", include_in_schema=False)
    def index() -> FileResponse:
        return FileResponse(STATIC_DIR / "index.html")

    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    return app


def _entry_json(entry: dict) -> dict:
    return {"id": entry_id(entry), **entry}


def _day_json(day: Day, cfg: Config) -> dict:
    exc = cfg.exceptions.get(day.date)
    return {
        "date": day.date.isoformat(),
        "weekday": day.date.weekday(),
        "effective_weekday": day.effective_weekday,
        "status": day.status,
        "off_reason": day.off_reason,
        "holiday": day.holiday,
        "in_term": cfg.term_start <= day.date <= cfg.term_end,
        "exceptions": [_entry_json(e) for e in exc.entries] if exc else [],
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
        "makeup_date": s.makeup_date.isoformat() if s.makeup_date else None,
        "makeup_pending": s.makeup_pending,
    }


# `uvicorn komawari.api:app` で直接起動する場合用
app = create_app(os.environ.get("KOMAWARI_CONFIG", "timetable.yaml"))
