from datetime import date, time
from pathlib import Path

import pytest

from komawari.config import ConfigError, load_config, parse_text

SAMPLE = Path(__file__).parent / "fixtures" / "timetable.yaml"


def test_sample_file_loads():
    cfg = load_config(SAMPLE)
    assert (cfg.term_start, cfg.term_end) == (date(2026, 10, 5), date(2027, 1, 29))
    assert cfg.periods[1].start == time(8, 45)
    assert cfg.exceptions[date(2026, 10, 21)].as_weekday == 0
    assert cfg.exceptions[date(2026, 11, 23)].off is False


def test_unquoted_times_are_accepted():
    # 引用符なしの 10:30 は YAML 1.1 では整数 630 になる
    cfg = parse_text(
        """
        term: {start: 2026-10-05, end: 2027-01-29}
        periods:
          1: {start: 08:45, end: 10:15}
          2: {start: 10:30, end: 12:00}
        classes:
          - {name: 演習, weekday: 0, start: 9:00, end: 10:30}
        """
    )
    assert (cfg.periods[1].start, cfg.periods[1].end) == (time(8, 45), time(10, 15))
    assert (cfg.periods[2].start, cfg.periods[2].end) == (time(10, 30), time(12, 0))
    assert (cfg.classes[0].start, cfg.classes[0].end) == (time(9, 0), time(10, 30))


def test_off_key_is_not_read_as_boolean():
    # YAML 1.1 では off / on / yes / no も真偽値になるが、キーや授業名として使えるようにする
    cfg = parse_text(
        """
        term: {start: 2026-10-05, end: 2027-01-29}
        periods: {1: {start: "08:45", end: "10:15"}}
        classes:
          - {name: on, weekday: 0, period: 1}
        exceptions:
          - {date: 2026-11-04, off: true}
          - {date: 2026-11-23, off: false}
        """
    )
    assert cfg.classes[0].name == "on"
    assert cfg.exceptions[date(2026, 11, 4)].off is True
    assert cfg.exceptions[date(2026, 11, 23)].off is False


def test_broken_yaml_is_a_config_error():
    with pytest.raises(ConfigError):
        parse_text("term: {start: 2026-10-05")


def test_same_date_lines_are_merged(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-10-21", "as_weekday": 0},
            {"date": "2026-10-21", "class": "Java演習", "room": "C303"},
            {"date": "2026-10-21", "extra": {"name": "補習", "period": 5}},
        ]
    )
    exc = cfg.exceptions[date(2026, 10, 21)]
    assert exc.as_weekday == 0
    assert [c.room for c in exc.changes] == ["C303"]
    assert [c.name for c in exc.extras] == ["補習"]


@pytest.mark.parametrize(
    "classes",
    [
        [{"name": "X", "weekday": 0}],  # 時刻指定なし
        [{"name": "X", "weekday": 0, "period": 1, "start": "09:00", "end": "10:00"}],  # 両方
        [{"name": "X", "weekday": 0, "start": "09:00"}],  # end なし
        [{"name": "X", "weekday": 0, "start": "10:00", "end": "09:00"}],  # 逆転
        [{"name": "X", "weekday": 0, "period": 9}],  # 存在しないコマ
        [{"name": "X", "weekday": 7, "period": 1}],  # 曜日の範囲外
        [{"name": "X", "period": 1}],  # 曜日なし
        [{"name": "X", "weekday": 0, "period": 1, "teacher": "Y"}],  # 知らないキー
        [{"name": "X", "weekday": 0, "period": 1, "term": 3}],  # 定義されていないターム
    ],
)
def test_invalid_classes(make_cfg, classes):
    with pytest.raises(ConfigError):
        make_cfg(classes=classes)


@pytest.mark.parametrize(
    "exceptions",
    [
        [{"date": "2026-10-21"}],  # 種類なし
        [{"date": "2026-10-21", "as_weekday": 0, "off": True}],  # 1行に2種類
        [{"date": "2026-10-21", "as_weekday": 0}, {"date": "2026-10-21", "as_weekday": 1}],
        [{"date": "2026-10-21", "as_weekday": 0}, {"date": "2026-10-21", "off": True}],
        [{"date": "2026-10-21", "off": True}, {"date": "2026-10-21", "off": False}],
        [{"date": "2026-10-21", "off": "yes"}],
        [{"date": "2026/10/21", "off": True}],
        [{"date": "2026-10-21", "class": "機械学習"}],  # room も off もない
        [{"date": "2026-10-21", "class": "機械学習", "room": "B", "off": True}],
        [{"date": "2026-10-21", "class": "機械学習", "romm": "B"}],  # 打ち間違い
        [{"date": "2026-10-21", "class": "機会学習", "room": "B"}],  # 存在しない授業名
        [{"date": "2026-10-20", "class": "機械学習", "room": "B"}],  # その日に無い授業
        [{"date": "2026-10-21", "class": "機械学習", "period": 4, "room": "B"}],  # コマ違い
        [{"date": "2027-02-03", "class": "機械学習", "room": "B"}],  # 学期外
        [{"date": "2026-10-21", "extra": {"name": "X", "weekday": 0, "period": 1}}],
        [{"date": "2026-10-21", "extra": {"name": "X", "period": 1, "term": 3}}],
    ],
)
def test_invalid_exceptions(make_cfg, exceptions):
    with pytest.raises(ConfigError):
        make_cfg(exceptions)


def test_term_must_not_be_reversed(make_cfg):
    with pytest.raises(ConfigError):
        make_cfg(term={"start": "2027-01-29", "end": "2026-10-05"})


def test_class_change_must_target_a_class_running_in_that_term(make_cfg):
    terms = {3: {"start": "2026-10-05", "end": "2026-12-01"}}
    classes = [{"name": "線形代数", "weekday": 2, "period": 1, "term": 3}]
    make_cfg([{"date": "2026-11-25", "class": "線形代数", "room": "B"}], terms=terms, classes=classes)
    with pytest.raises(ConfigError):
        make_cfg(
            [{"date": "2026-12-02", "class": "線形代数", "room": "B"}], terms=terms, classes=classes
        )


def test_terms_must_not_be_reversed(make_cfg):
    with pytest.raises(ConfigError):
        make_cfg(terms={3: {"start": "2026-12-01", "end": "2026-10-05"}})
