import pytest

from komawari.config import ConfigError, entry_id, load_config
from komawari.editor import MARKER, edit_exceptions

BASE = """\
# 先頭のコメント
term: {start: 2026-10-05, end: 2027-01-29}
periods:
  1: {start: "08:45", end: "10:15"}
  3: {start: "13:00", end: "14:30"}
classes:
  - {name: Java演習, weekday: 0, period: 1, room: 情報1号館}
  - {name: 機械学習, weekday: 2, period: 3, room: A101}
"""

EXCEPTIONS = """\
exceptions:
  # 振替
  - {date: 2026-10-21, as_weekday: 0}   # この水曜は月曜授業

  # 書き方の例
  # - {date: 2026-12-02, class: 機械学習, room: B202}
"""


@pytest.fixture
def path(tmp_path):
    p = tmp_path / "timetable.yaml"
    p.write_text(BASE + "\n" + EXCEPTIONS, encoding="utf-8")
    return p


def ids(path):
    return {entry_id(e) for exc in load_config(path).exceptions.values() for e in exc.entries}


def test_add_appends_one_line_and_keeps_everything_else(path):
    before = path.read_text(encoding="utf-8")
    (added,) = edit_exceptions(path, add=[{"date": "2026-12-02", "class": "機械学習", "off": True}])
    assert added == {"date": "2026-12-02", "class": "機械学習", "off": True}

    after = path.read_text(encoding="utf-8")
    assert after == before + f"\n  {MARKER}\n  - {{date: 2026-12-02, class: 機械学習, off: true}}\n"
    assert load_config(path).exceptions[added_date(added)].changes[0].off is True


def added_date(entry):
    from datetime import date

    return date.fromisoformat(entry["date"])


def test_second_add_goes_under_the_same_marker(path):
    edit_exceptions(path, add=[{"date": "2026-12-02", "class": "機械学習", "room": "B202"}])
    edit_exceptions(path, add=[{"date": "2026-11-14", "extra": {"name": "機械学習", "period": 3}}])
    lines = path.read_text(encoding="utf-8").splitlines()
    assert lines.count(f"  {MARKER}") == 1
    assert lines[-2:] == [
        "  - {date: 2026-12-02, class: 機械学習, room: B202}",
        "  - {date: 2026-11-14, extra: {name: 機械学習, period: 3}}",
    ]


def test_remove_deletes_only_that_line(path):
    before = path.read_text(encoding="utf-8")
    (added,) = edit_exceptions(path, add=[{"date": "2026-11-04", "off": True}])
    edit_exceptions(path, remove=[entry_id(added)])
    assert path.read_text(encoding="utf-8") == before + f"\n  {MARKER}\n"

    # 手で書いた行（行末コメント付き）も削除できる
    swap = entry_id({"date": "2026-10-21", "as_weekday": 0})
    edit_exceptions(path, remove=[swap])
    text = path.read_text(encoding="utf-8")
    assert "as_weekday" not in text
    assert "# 振替" in text and "# 書き方の例" in text


def test_replace_is_applied_together(path):
    (old,) = edit_exceptions(path, add=[{"date": "2026-12-02", "class": "機械学習", "room": "B202"}])
    edit_exceptions(
        path,
        add=[{"date": "2026-12-02", "class": "機械学習", "off": True}],
        remove=[entry_id(old)],
    )
    assert ids(path) == {
        entry_id({"date": "2026-10-21", "as_weekday": 0}),
        entry_id({"date": "2026-12-02", "class": "機械学習", "off": True}),
    }


@pytest.mark.parametrize(
    "entry",
    [
        {"date": "2026-10-21", "as_weekday": 1},  # 振替が重複
        {"date": "2026-10-21", "off": True},  # 振替と休講が両立しない
        {"date": "2026-12-03", "class": "機械学習", "off": True},  # その日に無い授業
        {"date": "2026-12-02", "class": "機械学習"},  # 中身がない
        {"date": "2026-12-02", "extra": {"name": "X", "period": 9}},  # 無いコマ
    ],
)
def test_invalid_edit_leaves_file_untouched(path, entry):
    before = path.read_text(encoding="utf-8")
    with pytest.raises(ConfigError):
        edit_exceptions(path, add=[entry])
    assert path.read_text(encoding="utf-8") == before


def test_failed_add_does_not_apply_the_removal(path):
    before = path.read_text(encoding="utf-8")
    swap = entry_id({"date": "2026-10-21", "as_weekday": 0})
    with pytest.raises(ConfigError):
        edit_exceptions(path, add=[{"date": "2026-12-02", "class": "無い授業", "off": True}], remove=[swap])
    assert path.read_text(encoding="utf-8") == before


def test_remove_unknown_id(path):
    with pytest.raises(LookupError):
        edit_exceptions(path, remove=["0123456789ab"])


def test_multiline_entry_cannot_be_removed(path):
    path.write_text(
        BASE + "exceptions:\n  - date: 2026-11-04\n    off: true\n", encoding="utf-8"
    )
    with pytest.raises(ConfigError):
        edit_exceptions(path, remove=[entry_id({"date": "2026-11-04", "off": True})])


def test_creates_section_when_missing(path):
    path.write_text(BASE, encoding="utf-8")
    edit_exceptions(path, add=[{"date": "2026-11-04", "off": True}])
    assert path.read_text(encoding="utf-8") == (
        BASE + f"\nexceptions:\n  {MARKER}\n  - {{date: 2026-11-04, off: true}}\n"
    )


def test_inserts_before_a_following_section(path):
    path.write_text(EXCEPTIONS + "\n# 授業\n" + BASE, encoding="utf-8")
    edit_exceptions(path, add=[{"date": "2026-11-04", "off": True}])
    text = path.read_text(encoding="utf-8")
    assert text == (
        EXCEPTIONS + f"\n  {MARKER}\n  - {{date: 2026-11-04, off: true}}\n" + "\n# 授業\n" + BASE
    )


def test_awkward_text_round_trips(path):
    extra = {"name": "線形代数: 演習, #2 {再}", "start": "18:10", "end": "19:40", "room": "off"}
    (added,) = edit_exceptions(path, add=[{"date": "2026-11-14", "extra": extra}])
    assert added["extra"] == extra
    (course,) = load_config(path).exceptions[added_date(added)].extras
    assert (course.name, course.room, f"{course.start:%H:%M}") == (extra["name"], "off", "18:10")
    edit_exceptions(path, remove=[entry_id(added)])
    assert entry_id(added) not in ids(path)
