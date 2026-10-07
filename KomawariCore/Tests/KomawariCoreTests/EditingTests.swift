import Testing

@testable import KomawariCore

@Suite struct EditingTests {
    /// 木曜の3・4限に同名の「実験」がある時間割。
    func lab() -> Timetable {
        makeTimetable(courses: [
            Course(name: "実験", weekday: 3, slot: .period(3), room: "E1"),
            Course(name: "実験", weekday: 3, slot: .period(4), room: "E1"),
            Course(name: "英語", weekday: 3, slot: .period(1)),
        ])
    }

    let day = date("2026-10-08")

    func states(_ timetable: Timetable) throws -> [String] {
        try Schedule(timetable).day(day).classes.map { "\($0.period ?? 0):\($0.status.rawValue):\($0.room ?? "-")" }
    }

    @Test func wholeDayOffCoversEveryPeriodWithOneEntry() throws {
        var timetable = lab()
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off, wholeDay: true)
        #expect(timetable.exceptions == [.classChange(date: day, className: "実験", period: nil, .off)])
        #expect(try states(timetable) == ["1:normal:-", "3:off:E1", "4:off:E1"])
        #expect(timetable.classState(on: day, name: "実験", period: 4) == .off)
        #expect(timetable.hasWholeDayChange(on: day, name: "実験"))
    }

    @Test func narrowingOnePeriodKeepsTheOthers() throws {
        var timetable = lab()
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off, wholeDay: true)
        // 3限だけ教室変更にすると、4限の休講は残る
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .room("E9"), wholeDay: false)
        #expect(try states(timetable) == ["1:normal:-", "3:room_changed:E9", "4:off:E1"])
        #expect(timetable.classState(on: day, name: "実験", period: 3) == .room("E9"))
        #expect(timetable.classState(on: day, name: "実験", period: 4) == .off)
        #expect(!timetable.hasWholeDayChange(on: day, name: "実験"))

        // 全コマを通常どおりに戻すと何も残らない
        timetable.setClass(on: day, name: "実験", period: 4, siblingPeriods: [3, 4], to: .normal, wholeDay: true)
        #expect(timetable.exceptions.isEmpty)
    }

    @Test func changeDoesNotTouchOtherDaysOrClasses() throws {
        var timetable = lab()
        let nextWeek = date("2026-10-15")
        timetable.setClass(on: nextWeek, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off, wholeDay: true)
        timetable.setClass(on: day, name: "英語", period: 1, siblingPeriods: [1], to: .room("B2"), wholeDay: true)
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .normal, wholeDay: true)
        #expect(timetable.exceptions == [
            .classChange(date: nextWeek, className: "実験", period: nil, .off),
            .classChange(date: day, className: "英語", period: nil, .room("B2")),
        ])
    }

    @Test func dayStateReplacesPreviousOne() throws {
        var timetable = lab()
        #expect(timetable.dayState(on: day) == .normal)
        timetable.setDay(on: day, to: .off)
        #expect(timetable.dayState(on: day) == .off)
        timetable.setDay(on: day, to: .swap(asWeekday: 0))
        #expect(timetable.exceptions == [.swap(date: day, asWeekday: 0)])
        #expect(try Schedule(timetable).day(day).status == .swapped)
        timetable.setDay(on: day, to: .normal)
        #expect(timetable.exceptions.isEmpty)

        let holiday = date("2026-11-23")
        timetable.setDay(on: holiday, to: .hold)
        #expect(timetable.dayState(on: holiday) == .hold)
        #expect(try Schedule(timetable).day(holiday).offReason == nil)
    }

    @Test func extraCanBeAddedAndRemoved() throws {
        var timetable = lab()
        let extra = ExtraClass(name: "英語", slot: .period(2), room: "C1")
        timetable.addExtra(on: day, extra)
        #expect(try states(timetable) == ["1:normal:-", "2:extra:C1", "3:normal:E1", "4:normal:E1"])
        let removed = timetable.removeExtra(on: day, name: "英語", slot: .period(2))
        let removedAgain = timetable.removeExtra(on: day, name: "英語", slot: .period(2))
        #expect(removed)
        #expect(!removedAgain)
        #expect(timetable.exceptions.isEmpty)
        #expect(timetable.courseNames == ["実験", "英語"])
    }

    @Test func swappingAwayADayWithClassChangesIsRejected() throws {
        var timetable = lab()
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off, wholeDay: true)
        timetable.setDay(on: day, to: .swap(asWeekday: 0))
        #expect(throws: TimetableError.noSuchClass(date: day, name: "実験", period: nil)) {
            try Schedule(timetable)
        }
    }
}
