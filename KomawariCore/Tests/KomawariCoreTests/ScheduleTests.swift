import Foundation
import Testing

@testable import KomawariCore

func date(_ text: String) -> CalendarDate { CalendarDate(text)! }
func time(_ text: String) -> ClockTime { ClockTime(text)! }

/// テスト用の時間割。月2コマ Java演習、水3コマ 機械学習、金 18:10〜 ゼミ。
func makeTimetable(
    exceptions: [ScheduleException] = [],
    courses: [Course]? = nil,
    terms: [String: DateRange] = [:]
) -> Timetable {
    Timetable(
        term: DateRange(start: date("2026-10-05"), end: date("2027-01-29")),
        terms: terms,
        periods: [
            Period(number: 1, start: time("08:45"), end: time("10:15")),
            Period(number: 2, start: time("10:30"), end: time("12:00")),
            Period(number: 3, start: time("13:00"), end: time("14:30")),
            Period(number: 4, start: time("14:45"), end: time("16:15")),
        ],
        courses: courses ?? [
            Course(name: "Java演習", weekday: 0, slot: .period(2), room: "情報1号館"),
            Course(name: "機械学習", weekday: 2, slot: .period(3), room: "A101"),
            Course(name: "ゼミ", weekday: 4, slot: .time(start: time("18:10"), end: time("19:40"))),
        ],
        exceptions: exceptions)
}

func names(_ day: DayPlan) -> [String] { day.classes.map { "\($0.name):\($0.status.rawValue)" } }

@Suite struct CalendarDateTests {
    @Test func weekdayAndArithmetic() {
        #expect(date("2026-10-05").weekday == 0)  // 月
        #expect(date("2026-10-11").weekday == 6)  // 日
        #expect(date("1969-12-31").weekday == 2)  // 水（1970年より前）
        #expect(date("2026-12-31").adding(days: 1) == date("2027-01-01"))
        #expect(date("2028-02-28").adding(days: 1) == date("2028-02-29"))
        #expect(date("2026-10-08").monday == date("2026-10-05"))
        #expect(date("2026-10-05") < date("2026-10-06"))
    }

    @Test func ordinalRoundTrips() {
        for ordinal in stride(from: -40_000, through: 60_000, by: 37) {
            #expect(CalendarDate(ordinal: ordinal).ordinal == ordinal)
        }
    }

    @Test func rejectsInvalidText() {
        #expect(CalendarDate("2026-02-30") == nil)
        #expect(CalendarDate("2026/10/05") == nil)
        #expect(CalendarDate("2026-1-5") == nil)
        #expect(CalendarDate("2027-02-29") == nil)
        #expect(ClockTime("24:00") == nil)
        #expect(ClockTime("10:60") == nil)
        #expect(ClockTime("9:00")?.description == "09:00")
    }
}

@Suite struct ScheduleTests {
    @Test func normalDayResolvesPeriod() throws {
        let day = try Schedule(makeTimetable()).day(date("2026-10-05"))
        #expect(day.status == .normal)
        let session = try #require(day.classes.first)
        #expect(session.name == "Java演習")
        #expect(session.period == 2)
        #expect(session.start == time("10:30"))
        #expect(session.room == "情報1号館")
    }

    @Test func swapUsesOtherWeekday() throws {
        let schedule = try Schedule(makeTimetable(exceptions: [.swap(date: date("2026-10-21"), asWeekday: 0)]))
        let day = schedule.day(date("2026-10-21"))
        #expect(day.status == .swapped)
        #expect(day.effectiveWeekday == 0)
        #expect(names(day) == ["Java演習:swapped"])
    }

    @Test func offDayKeepsCancelledClasses() throws {
        let schedule = try Schedule(makeTimetable(exceptions: [.dayOff(date: date("2026-11-04"), off: true)]))
        let day = schedule.day(date("2026-11-04"))
        #expect(day.status == .off)
        #expect(day.offReason == .exception)
        #expect(names(day) == ["機械学習:off"])
        #expect(day.active.isEmpty)
    }

    @Test func holidayIsOffUnlessOverridden() throws {
        let plain = try Schedule(makeTimetable()).day(date("2026-10-12"))
        #expect(plain.offReason == .holiday)
        #expect(plain.holiday == "スポーツの日")
        #expect(names(plain) == ["Java演習:off"])

        let held = try Schedule(makeTimetable(exceptions: [.dayOff(date: date("2026-11-23"), off: false)]))
            .day(date("2026-11-23"))
        #expect(held.status == .normal)
        #expect(held.holiday == "勤労感謝の日")
        #expect(names(held) == ["Java演習:normal"])

        let swapped = try Schedule(makeTimetable(exceptions: [.swap(date: date("2026-11-03"), asWeekday: 2)]))
            .day(date("2026-11-03"))
        #expect(names(swapped) == ["機械学習:swapped"])
    }

    @Test func extraClassIsAddedEvenOnOffDay() throws {
        let schedule = try Schedule(makeTimetable(exceptions: [
            .dayOff(date: date("2026-11-04"), off: true),
            .extra(date: date("2026-11-04"), ExtraClass(name: "集中講義", slot: .period(1))),
        ]))
        let day = schedule.day(date("2026-11-04"))
        #expect(names(day) == ["集中講義:extra", "機械学習:off"])
        #expect(day.active.map(\.name) == ["集中講義"])
    }

    @Test func roomChangeAndSingleClassOff() throws {
        let schedule = try Schedule(makeTimetable(exceptions: [
            .classChange(date: date("2026-12-02"), className: "機械学習", period: nil, .room("B202")),
            .classChange(date: date("2026-12-09"), className: "機械学習", period: 3, .off()),
        ]))
        let changed = try #require(schedule.day(date("2026-12-02")).classes.first)
        #expect(changed.status == .roomChanged)
        #expect(changed.room == "B202")
        #expect(changed.originalRoom == "A101")

        let cancelled = schedule.day(date("2026-12-09"))
        #expect(cancelled.status == .normal)
        #expect(names(cancelled) == ["機械学習:off"])
        #expect(names(schedule.day(date("2026-12-16"))) == ["機械学習:normal"])
    }

    @Test func termEdges() throws {
        let schedule = try Schedule(makeTimetable())
        #expect(names(schedule.day(date("2026-10-05"))) == ["Java演習:normal"])
        #expect(names(schedule.day(date("2027-01-29"))) == ["ゼミ:normal"])
        for outside in ["2026-09-28", "2027-02-03"] {
            let day = schedule.day(date(outside))
            #expect(day.offReason == .outOfTerm)
            #expect(day.classes.isEmpty)
        }
        let term = schedule.term()
        #expect(term.count == 117)
        #expect(term.first?.date == date("2026-10-05"))
        #expect(term.last?.date == date("2027-01-29"))
    }

    @Test func classRunsOnlyInItsTerm() throws {
        let terms = [
            "3": DateRange(start: date("2026-10-05"), end: date("2026-12-01")),
            "4": DateRange(start: date("2026-12-02"), end: date("2027-01-29")),
        ]
        let courses = [
            Course(name: "線形代数", weekday: 2, slot: .period(1), term: "3"),
            Course(name: "統計学", weekday: 2, slot: .period(1), term: "4"),
            Course(name: "プログラミング", weekday: 2, slot: .period(4)),
        ]
        let schedule = try Schedule(makeTimetable(
            exceptions: [.swap(date: date("2026-12-04"), asWeekday: 2)], courses: courses, terms: terms))
        #expect(names(schedule.day(date("2026-11-25"))) == ["線形代数:normal", "プログラミング:normal"])
        #expect(names(schedule.day(date("2026-12-02"))) == ["統計学:normal", "プログラミング:normal"])
        #expect(names(schedule.day(date("2026-12-04"))) == ["統計学:swapped", "プログラミング:swapped"])
    }

    @Test func weekIncludesWeekendOnlyWithClasses() throws {
        let schedule = try Schedule(makeTimetable(exceptions: [
            .extra(date: date("2026-11-14"), ExtraClass(name: "機械学習", slot: .period(4))),
        ]))
        #expect(schedule.week(containing: date("2026-10-07")).map(\.date.weekday) == [0, 1, 2, 3, 4])
        let week = schedule.week(containing: date("2026-11-09"))
        #expect(week.map(\.date.weekday) == [0, 1, 2, 3, 4, 5])
        #expect(Schedule.summary(of: week) == ["土曜に補講「機械学習」"])
    }
}

@Suite struct ValidationTests {
    func error(_ timetable: Timetable) -> TimetableError? {
        do {
            _ = try Schedule(timetable)
            return nil
        } catch {
            return error as? TimetableError
        }
    }

    @Test func rejectsBrokenCourses() {
        #expect(error(makeTimetable(courses: [Course(name: "X", weekday: 0, slot: .period(9))]))
            == .unknownPeriod(9, at: "classes[0]"))
        #expect(error(makeTimetable(courses: [Course(name: "X", weekday: 7, slot: .period(1))]))
            == .invalidWeekday(7, at: "classes[0]"))
        #expect(error(makeTimetable(courses: [Course(name: "X", weekday: 0, slot: .period(1), term: "3")]))
            == .unknownTerm("3", course: "classes[0]"))
        #expect(error(makeTimetable(courses: [
            Course(name: "X", weekday: 0, slot: .time(start: time("10:00"), end: time("09:00"))),
        ])) == .invalidTimes(at: "classes[0]"))
    }

    @Test func rejectsConflictingExceptions() {
        let day = date("2026-10-21")
        #expect(error(makeTimetable(exceptions: [.swap(date: day, asWeekday: 0), .swap(date: day, asWeekday: 1)]))
            == .duplicateSwap(day))
        #expect(error(makeTimetable(exceptions: [.swap(date: day, asWeekday: 0), .dayOff(date: day, off: true)]))
            == .offAndSwap(day))
        #expect(error(makeTimetable(exceptions: [.dayOff(date: day, off: true), .dayOff(date: day, off: false)]))
            == .duplicateDayOff(day))
        // 振替と「祝日でも授業あり」は両立する
        #expect(error(makeTimetable(exceptions: [.swap(date: day, asWeekday: 0), .dayOff(date: day, off: false)])) == nil)
    }

    @Test func rejectsChangesForClassesNotHeldThatDay() {
        func change(_ day: String, _ name: String, period: Int? = nil) -> TimetableError? {
            error(makeTimetable(exceptions: [
                .classChange(date: date(day), className: name, period: period, .room("B")),
            ]))
        }
        #expect(change("2026-10-21", "機械学習") == nil)
        #expect(change("2026-10-21", "機会学習") == .noSuchClass(date: date("2026-10-21"), name: "機会学習", period: nil))
        #expect(change("2026-10-20", "機械学習") != nil)  // 火曜には無い
        #expect(change("2026-10-21", "機械学習", period: 4) != nil)  // コマ違い
        #expect(change("2027-02-03", "機械学習") != nil)  // 学期外
        #expect(change("2026-10-21", "機械学習", period: 9) == .unknownPeriod(9, at: "exceptions[0]"))
    }

    @Test func rejectsReversedRanges() {
        var timetable = makeTimetable()
        timetable.term = DateRange(start: date("2027-01-29"), end: date("2026-10-05"))
        #expect(error(timetable) == .termReversed)
        #expect(error(makeTimetable(terms: ["3": DateRange(start: date("2026-12-01"), end: date("2026-10-05"))]))
            == .termRangeReversed(term: "3"))
    }
}

@Suite struct JSONTests {
    func decode(_ json: String) throws -> Timetable {
        try JSONDecoder().decode(Timetable.self, from: Data(json.utf8))
    }

    let head = #""term": {"start": "2026-10-05", "end": "2027-01-29"}, "periods": {"1": {"start": "08:45", "end": "10:15"}}"#

    @Test func readsTheYAMLShape() throws {
        let timetable = try decode("""
            {\(head), "terms": {"3": {"start": "2026-10-05", "end": "2026-12-01"}},
             "classes": [{"name": "A", "weekday": 0, "period": 1, "room": "R", "term": 3},
                         {"name": "B", "weekday": 4, "start": "18:10", "end": "19:40"}],
             "exceptions": [{"date": "2026-10-21", "as_weekday": 0},
                            {"date": "2026-11-04", "off": true},
                            {"date": "2026-11-14", "extra": {"name": "A", "period": 1}},
                            {"date": "2026-10-12", "class": "A", "period": 1, "room": "B202"},
                            {"date": "2026-10-19", "class": "A", "off": true}]}
            """)
        #expect(timetable.courses[0] == Course(name: "A", weekday: 0, slot: .period(1), room: "R", term: "3"))
        #expect(timetable.courses[1].slot == .time(start: time("18:10"), end: time("19:40")))
        #expect(timetable.exceptions == [
            .swap(date: date("2026-10-21"), asWeekday: 0),
            .dayOff(date: date("2026-11-04"), off: true),
            .extra(date: date("2026-11-14"), ExtraClass(name: "A", slot: .period(1))),
            .classChange(date: date("2026-10-12"), className: "A", period: 1, .room("B202")),
            .classChange(date: date("2026-10-19"), className: "A", period: nil, .off()),
        ])
    }

    @Test(arguments: [
        #""classes": [{"name": "A", "weekday": 0}]"#,  // 時刻指定なし
        #""classes": [{"name": "A", "weekday": 0, "period": 1, "start": "09:00", "end": "10:00"}]"#,
        #""classes": [{"name": "A", "weekday": 0, "period": 1, "teacher": "T"}]"#,  // 知らないキー
        #""classes": [{"name": "A", "period": 1}]"#,  // 曜日なし
        #""exceptions": [{"date": "2026-10-21"}]"#,  // 種類なし
        #""exceptions": [{"date": "2026-10-21", "as_weekday": 0, "off": true}]"#,
        #""exceptions": [{"date": "2026/10/21", "off": true}]"#,
        #""exceptions": [{"date": "2026-10-21", "class": "A"}]"#,
        #""exceptions": [{"date": "2026-10-21", "class": "A", "room": "B", "off": true}]"#,
        #""exceptions": [{"date": "2026-10-21", "extra": {"name": "A", "weekday": 0, "period": 1}}]"#,
    ])
    func rejectsMalformedJSON(body: String) {
        #expect(throws: DecodingError.self) { try decode("{\(head), \(body)}") }
    }
}
