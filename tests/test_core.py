from datetime import date, time

from komawari.core import expand_day, expand_term, week_summary, week_view


def names(day):
    return [(s.name, s.status) for s in day.classes]


def test_normal_day_resolves_period_to_time(make_cfg):
    day = expand_day(make_cfg(), date(2026, 10, 5))  # 月
    assert day.status == "normal"
    (s,) = day.classes
    assert (s.name, s.period, s.start, s.end, s.room, s.status) == (
        "Java演習", 2, time(10, 30), time(12, 0), "情報1号館", "normal",
    )


def test_direct_start_end_has_no_period(make_cfg):
    (s,) = expand_day(make_cfg(), date(2026, 10, 9)).classes  # 金
    assert (s.name, s.period, s.start, s.end) == ("ゼミ", None, time(18, 10), time(19, 40))


def test_swap_uses_other_weekday(make_cfg):
    cfg = make_cfg([{"date": "2026-10-21", "as_weekday": 0}])
    day = expand_day(cfg, date(2026, 10, 21))  # 水曜を月曜授業に
    assert day.status == "swapped"
    assert day.effective_weekday == 0
    assert names(day) == [("Java演習", "swapped")]


def test_off_day_keeps_cancelled_classes(make_cfg):
    cfg = make_cfg([{"date": "2026-11-04", "off": True}])
    day = expand_day(cfg, date(2026, 11, 4))  # 水
    assert (day.status, day.off_reason) == ("off", "exception")
    assert names(day) == [("機械学習", "off")]
    assert day.active == ()


def test_holiday_is_off_automatically(make_cfg):
    day = expand_day(make_cfg(), date(2026, 10, 12))  # 月・スポーツの日
    assert (day.status, day.off_reason, day.holiday) == ("off", "holiday", "スポーツの日")
    assert names(day) == [("Java演習", "off")]


def test_holiday_overridden_with_off_false(make_cfg):
    cfg = make_cfg([{"date": "2026-11-23", "off": False}])
    day = expand_day(cfg, date(2026, 11, 23))  # 月・勤労感謝の日
    assert (day.status, day.off_reason, day.holiday) == ("normal", None, "勤労感謝の日")
    assert names(day) == [("Java演習", "normal")]


def test_holiday_overridden_with_swap(make_cfg):
    cfg = make_cfg([{"date": "2026-11-03", "as_weekday": 2}])
    day = expand_day(cfg, date(2026, 11, 3))  # 火・文化の日を水曜授業に
    assert day.status == "swapped"
    assert names(day) == [("機械学習", "swapped")]


def test_extra_class_is_added(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-11-14", "extra": {"name": "機械学習", "period": 4, "room": "A101"}},
            {"date": "2026-11-14", "extra": {"name": "特別講義", "start": "18:10", "end": "19:40"}},
        ]
    )
    day = expand_day(cfg, date(2026, 11, 14))  # 土
    assert day.status == "normal"
    assert names(day) == [("機械学習", "extra"), ("特別講義", "extra")]
    assert day.classes[0].start == time(14, 45)


def test_extra_on_off_day_still_happens(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-11-04", "off": True},
            {"date": "2026-11-04", "extra": {"name": "集中講義", "period": 1}},
        ]
    )
    day = expand_day(cfg, date(2026, 11, 4))
    assert day.status == "off"
    assert names(day) == [("集中講義", "extra"), ("機械学習", "off")]
    assert [s.name for s in day.active] == ["集中講義"]


def test_room_change(make_cfg):
    cfg = make_cfg([{"date": "2026-12-02", "class": "機械学習", "room": "B202"}])
    (s,) = expand_day(cfg, date(2026, 12, 2)).classes
    assert (s.status, s.room, s.original_room) == ("room_changed", "B202", "A101")
    # 他の週には影響しない
    (other,) = expand_day(cfg, date(2026, 12, 9)).classes
    assert (other.status, other.room) == ("normal", "A101")


def test_room_change_narrowed_by_period(make_cfg):
    classes = [
        {"name": "実験", "weekday": 3, "period": 3, "room": "E1"},
        {"name": "実験", "weekday": 3, "period": 4, "room": "E1"},
    ]
    cfg = make_cfg(
        [{"date": "2026-10-08", "class": "実験", "period": 4, "room": "E2"}], classes=classes
    )
    third, fourth = expand_day(cfg, date(2026, 10, 8)).classes
    assert (third.status, third.room) == ("normal", "E1")
    assert (fourth.status, fourth.room) == ("room_changed", "E2")


def test_room_change_on_swapped_day(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-10-21", "as_weekday": 0},
            {"date": "2026-10-21", "class": "Java演習", "room": "C303"},
        ]
    )
    day = expand_day(cfg, date(2026, 10, 21))
    assert day.status == "swapped"
    assert [(s.status, s.room) for s in day.classes] == [("room_changed", "C303")]


def test_single_class_off(make_cfg):
    cfg = make_cfg([{"date": "2026-12-02", "class": "機械学習", "off": True}])
    day = expand_day(cfg, date(2026, 12, 2))
    assert day.status == "normal"
    assert names(day) == [("機械学習", "off")]


def test_term_edges(make_cfg):
    cfg = make_cfg()
    assert names(expand_day(cfg, date(2026, 10, 5))) == [("Java演習", "normal")]  # 初日（月）
    assert names(expand_day(cfg, date(2027, 1, 29))) == [("ゼミ", "normal")]  # 最終日（金）

    before = expand_day(cfg, date(2026, 9, 28))  # 初日の前の月曜
    after = expand_day(cfg, date(2027, 2, 3))  # 最終日の後の水曜
    for day in (before, after):
        assert (day.status, day.off_reason, day.classes) == ("off", "out_of_term", ())


def test_week_view_is_monday_to_friday(make_cfg):
    days = week_view(make_cfg(), date(2026, 10, 7))  # 水曜を渡しても月曜始まり
    assert [d.date for d in days] == [date(2026, 10, 5 + i) for i in range(5)]


def test_week_view_includes_weekend_only_with_classes(make_cfg):
    cfg = make_cfg([{"date": "2026-11-14", "extra": {"name": "機械学習", "period": 4}}])
    days = week_view(cfg, date(2026, 11, 9))
    assert [d.date.weekday() for d in days] == [0, 1, 2, 3, 4, 5]


def test_week_view_works_for_any_week(make_cfg):
    days = week_view(make_cfg(), date(2027, 1, 18))
    assert [names(d) for d in days] == [
        [("Java演習", "normal")],
        [],
        [("機械学習", "normal")],
        [],
        [("ゼミ", "normal")],
    ]


def test_expand_term_covers_whole_term(make_cfg):
    cfg = make_cfg()
    days = list(expand_term(cfg))
    assert (days[0].date, days[-1].date) == (date(2026, 10, 5), date(2027, 1, 29))
    assert len(days) == 117


def test_expand_term_reaches_extra_outside_term(make_cfg):
    cfg = make_cfg([{"date": "2027-02-03", "extra": {"name": "機械学習", "period": 3}}])
    days = list(expand_term(cfg))
    assert days[-1].date == date(2027, 2, 3)
    assert names(days[-1]) == [("機械学習", "extra")]
    assert days[-2].classes == ()  # 学期外の通常授業は出ない


def test_summary(make_cfg):
    cfg = make_cfg(
        [
            {"date": "2026-10-21", "as_weekday": 0},
            {"date": "2026-11-04", "off": True},
            {"date": "2026-11-14", "extra": {"name": "機械学習", "period": 4}},
            {"date": "2026-11-23", "off": False},
            {"date": "2026-12-02", "class": "機械学習", "room": "B202"},
            {"date": "2026-12-09", "class": "機械学習", "off": True},
        ]
    )

    def summary(d):
        return week_summary(week_view(cfg, d))

    assert summary(date(2026, 10, 5)) == []
    assert summary(date(2026, 10, 12)) == ["月曜が祝日（スポーツの日）"]
    assert summary(date(2026, 10, 19)) == ["水曜が月曜授業"]
    assert summary(date(2026, 11, 2)) == ["火曜が祝日（文化の日）", "水曜が休講"]
    assert summary(date(2026, 11, 9)) == ["土曜に補講「機械学習」"]
    assert summary(date(2026, 11, 23)) == ["月曜が祝日（勤労感謝の日）だが授業あり"]
    assert summary(date(2026, 11, 30)) == ["水曜の機械学習がB202に教室変更"]
    assert summary(date(2026, 12, 7)) == ["水曜の機械学習が休講"]
    assert summary(date(2026, 9, 28)) == ["学期外"]


def test_summary_at_partial_term_edges(make_cfg):
    cfg = make_cfg(term={"start": "2026-10-07", "end": "2027-01-27"})
    assert week_summary(week_view(cfg, date(2026, 10, 5))) == ["10/7(水)から授業開始"]
    assert week_summary(week_view(cfg, date(2027, 1, 25))) == ["1/27(水)で授業終了"]


TERMS = {
    3: {"start": "2026-10-05", "end": "2026-12-01"},
    4: {"start": "2026-12-02", "end": "2027-01-29"},
}


def test_class_runs_only_in_its_term(make_cfg):
    classes = [
        {"name": "線形代数", "weekday": 2, "period": 1, "term": 3},
        {"name": "統計学", "weekday": 2, "period": 1, "term": 4},
        {"name": "プログラミング", "weekday": 2, "period": 4},  # term なし = 学期全体
    ]
    cfg = make_cfg(terms=TERMS, classes=classes)
    assert names(expand_day(cfg, date(2026, 11, 25))) == [
        ("線形代数", "normal"), ("プログラミング", "normal"),
    ]
    assert names(expand_day(cfg, date(2026, 12, 2))) == [
        ("統計学", "normal"), ("プログラミング", "normal"),
    ]


def test_swap_uses_classes_of_the_term_on_that_date(make_cfg):
    classes = [
        {"name": "線形代数", "weekday": 2, "period": 1, "term": 3},
        {"name": "統計学", "weekday": 2, "period": 1, "term": 4},
    ]
    cfg = make_cfg([{"date": "2026-12-04", "as_weekday": 2}], terms=TERMS, classes=classes)
    assert names(expand_day(cfg, date(2026, 12, 4))) == [("統計学", "swapped")]


def test_summary_mentions_a_multi_period_class_once(make_cfg):
    classes = [
        {"name": "実験", "weekday": 3, "period": 3},
        {"name": "実験", "weekday": 3, "period": 4},
    ]
    cfg = make_cfg([{"date": "2026-10-08", "class": "実験", "off": True}], classes=classes)
    assert week_summary(week_view(cfg, date(2026, 10, 8))) == ["木曜の実験が休講"]


def test_cancelled_class_with_makeup_date(make_cfg):
    classes = [
        {"name": "実験", "weekday": 3, "period": 3, "room": "E1"},
        {"name": "実験", "weekday": 3, "period": 4, "room": "E1"},
    ]
    makeup = {"date": "2026-10-24", "periods": [1, 2]}
    cfg = make_cfg(
        [{"date": "2026-10-08", "class": "実験", "off": True, "makeup": makeup}], classes=classes
    )
    cancelled = expand_day(cfg, date(2026, 10, 8))
    assert [(s.status, s.makeup_date) for s in cancelled.classes] == [("off", date(2026, 10, 24))] * 2

    held = expand_day(cfg, date(2026, 10, 24))  # 土曜。教室は元の授業のもの
    assert [(s.name, s.period, s.room, s.status) for s in held.classes] == [
        ("実験", 1, "E1", "extra"), ("実験", 2, "E1", "extra"),
    ]
    assert week_summary(week_view(cfg, date(2026, 10, 8))) == ["木曜の実験が休講（補講 10/24(土)）"]
    assert week_summary(week_view(cfg, date(2026, 10, 24))) == ["土曜に補講「実験」"]


def test_makeup_room_and_pending(make_cfg):
    cfg = make_cfg(
        [
            {
                "date": "2026-10-07", "class": "機械学習", "off": True,
                "makeup": {"date": "2027-02-03", "periods": [1], "room": "Z9"},
            },
            {"date": "2026-10-14", "class": "機械学習", "off": True, "makeup": "pending"},
        ]
    )
    (held,) = expand_day(cfg, date(2027, 2, 3)).classes  # 学期外でも補講は載る
    assert (held.room, held.status) == ("Z9", "extra")
    assert list(expand_term(cfg))[-1].date == date(2027, 2, 3)

    (pending,) = expand_day(cfg, date(2026, 10, 14)).classes
    assert (pending.status, pending.makeup_pending, pending.makeup_date) == ("off", True, None)
    assert "水曜の機械学習が休講（補講未定）" in week_summary(week_view(cfg, date(2026, 10, 14)))
