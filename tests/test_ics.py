from datetime import datetime, timezone

from komawari.ics import build_ics

NOW = datetime(2026, 10, 1, tzinfo=timezone.utc)


def events(text):
    """.ics を {プロパティ名: 値} の辞書のリストにする（折り返しは戻す）。"""
    assert text.endswith("\r\n")
    lines = text.replace("\r\n ", "").split("\r\n")
    result, current = [], None
    for line in lines:
        if line == "BEGIN:VEVENT":
            current = {}
        elif line == "END:VEVENT":
            result.append(current)
            current = None
        elif current is not None:
            key, _, value = line.partition(":")
            current[key] = value
    return result


def on(evs, yyyymmdd):
    return [e for e in evs if e["DTSTART;TZID=Asia/Tokyo"].startswith(yyyymmdd)]


def test_one_event_per_session_with_tokyo_time(make_cfg):
    text = build_ics(make_cfg(), NOW)
    assert "TZID:Asia/Tokyo" in text
    assert "RRULE" not in text
    (e,) = on(events(text), "20261005")
    assert e["SUMMARY"] == "Java演習"
    assert e["DTSTART;TZID=Asia/Tokyo"] == "20261005T103000"
    assert e["DTEND;TZID=Asia/Tokyo"] == "20261005T120000"
    assert e["LOCATION"] == "情報1号館"
    assert e["DTSTAMP"] == "20261001T000000Z"


def test_uid_is_stable_and_unique(make_cfg):
    first = events(build_ics(make_cfg(), NOW))
    second = events(build_ics(make_cfg(), datetime(2026, 12, 1, tzinfo=timezone.utc)))
    uids = [e["UID"] for e in first]
    assert uids == [e["UID"] for e in second]
    assert len(set(uids)) == len(uids)
    assert all(u.isascii() and u.endswith("@komawari") for u in uids)


def test_same_name_twice_a_day_gets_distinct_uids(make_cfg):
    classes = [
        {"name": "実験", "weekday": 3, "period": 3},
        {"name": "実験", "weekday": 3, "period": 4},
    ]
    evs = on(events(build_ics(make_cfg(classes=classes), NOW)), "20261008")
    assert len({e["UID"] for e in evs}) == 2


def test_swapped_class_is_marked(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-10-21", "as_weekday": 0},
            {"date": "2026-10-21", "class": "Java演習", "room": "C303"},
        ]
    )
    (e,) = on(events(build_ics(cfg, NOW)), "20261021")
    assert e["SUMMARY"] == "Java演習（振替）"
    assert e["LOCATION"] == "C303"
    assert "教室変更: 情報1号館 → C303" in e["DESCRIPTION"]


def test_off_days_and_holidays_have_no_events(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-11-04", "off": True},
            {"date": "2026-12-02", "class": "機械学習", "off": True},
        ]
    )
    evs = events(build_ics(cfg, NOW))
    assert on(evs, "20261104") == []  # 休講
    assert on(evs, "20261202") == []  # その授業だけ休講
    assert on(evs, "20261012") == []  # 祝日（スポーツの日）
    assert on(evs, "20261111") != []


def test_extra_class_is_exported(make_cfg):
    cfg = make_cfg([{"date": "2026-11-14", "extra": {"name": "機械学習", "period": 4}}])
    (e,) = on(events(build_ics(cfg, NOW)), "20261114")
    assert e["SUMMARY"] == "機械学習（補講）"
    assert e["DTSTART;TZID=Asia/Tokyo"] == "20261114T144500"


def test_text_is_escaped_and_folded(make_cfg):
    classes = [{"name": "線形代数, 演習; " + "長い名前" * 20, "weekday": 0, "period": 1}]
    text = build_ics(make_cfg(classes=classes), NOW)
    assert all(len(line.encode("utf-8")) <= 75 for line in text.split("\r\n"))
    (e,) = on(events(text), "20261005")
    assert e["SUMMARY"].startswith("線形代数\\, 演習\\; 長い名前")
