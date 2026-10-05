import os
import shutil
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from komawari.api import create_app

SAMPLE = Path(__file__).parent.parent / "timetable.yaml"


@pytest.fixture
def config_path(tmp_path):
    path = tmp_path / "timetable.yaml"
    shutil.copy(SAMPLE, path)
    return path


@pytest.fixture
def client(config_path):
    return TestClient(create_app(config_path), raise_server_exceptions=False)


def test_week_returns_days_with_status(client):
    data = client.get("/week", params={"date": "2026-10-21"}).json()
    assert data["week_start"] == "2026-10-19"
    assert [p["number"] for p in data["periods"]] == [1, 2, 3, 4, 5]
    assert data["summary"] == ["水曜が月曜授業"]
    assert [d["date"] for d in data["days"]] == [f"2026-10-{n}" for n in range(19, 24)]

    wednesday = data["days"][2]
    assert (wednesday["status"], wednesday["effective_weekday"]) == ("swapped", 0)
    assert wednesday["classes"] == [
        {
            "name": "Java演習",
            "period": 2,
            "start": "10:30",
            "end": "12:00",
            "room": "情報1号館",
            "status": "swapped",
            "original_room": None,
        }
    ]


def test_week_reports_holiday_and_off(client):
    data = client.get("/week", params={"date": "2026-11-02"}).json()
    tuesday, wednesday = data["days"][1], data["days"][2]
    assert (tuesday["status"], tuesday["off_reason"], tuesday["holiday"]) == (
        "off", "holiday", "文化の日",
    )
    assert (wednesday["status"], wednesday["off_reason"]) == ("off", "exception")
    assert [c["status"] for c in wednesday["classes"]] == ["off"]


def test_week_defaults_to_today(client):
    data = client.get("/week").json()
    assert data["today"] >= data["week_start"]
    assert len(data["days"]) >= 5


def test_week_rejects_bad_date(client):
    assert client.get("/week", params={"date": "10/21"}).status_code == 422


def test_ics_endpoint(client):
    res = client.get("/timetable.ics")
    assert res.status_code == 200
    assert res.headers["content-type"] == "text/calendar; charset=utf-8"
    assert res.text.startswith("BEGIN:VCALENDAR\r\n")
    assert "SUMMARY:Java演習（振替）" in res.text


def test_yaml_is_reloaded_when_file_changes(client, config_path):
    assert client.get("/week", params={"date": "2026-10-28"}).json()["summary"] == []

    text = config_path.read_text(encoding="utf-8")
    config_path.write_text(text + "  - {date: 2026-10-28, off: true}\n", encoding="utf-8")
    _touch_later(config_path)
    assert client.get("/week", params={"date": "2026-10-28"}).json()["summary"] == ["水曜が休講"]


def test_broken_yaml_is_reported_then_recovers(client, config_path):
    good = config_path.read_text(encoding="utf-8")
    assert client.get("/week").status_code == 200

    config_path.write_text(good + "  - {date: 2026-10-28, class: 存在しない, room: X}\n", encoding="utf-8")
    _touch_later(config_path)
    res = client.get("/week")
    assert res.status_code == 500
    assert "存在しない" in res.json()["detail"]

    config_path.write_text(good, encoding="utf-8")
    _touch_later(config_path, 2)
    assert client.get("/week").status_code == 200


def test_index_and_static_are_served(client):
    assert "text/html" in client.get("/").headers["content-type"]
    assert client.get("/static/app.js").status_code == 200
    assert client.get("/static/style.css").status_code == 200


def _touch_later(path, seconds=1):
    """同じ時刻内の書き込みでも更新と判定されるよう、mtime を確実に進める。"""
    stat = path.stat()
    os.utime(path, (stat.st_atime, stat.st_mtime + seconds))
