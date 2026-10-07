import Foundation
import Testing

@testable import KomawariCore

@Suite struct EditingTests {
    /// 木曜の3・4コマに同名の「実験」がある時間割。
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
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        #expect(timetable.exceptions == [.classChange(date: day, className: "実験", period: nil, .off())])
        #expect(try states(timetable) == ["1:normal:-", "3:off:E1", "4:off:E1"])
        #expect(timetable.classState(on: day, name: "実験", period: 4) == .off())
        #expect(timetable.hasWholeDayChange(on: day, name: "実験"))
    }

    @Test func narrowingOnePeriodKeepsTheOthers() throws {
        var timetable = lab()
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        // 3コマだけ教室変更にすると、4コマの休講は残る
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .room("E9"), wholeDay: false)
        #expect(try states(timetable) == ["1:normal:-", "3:room_changed:E9", "4:off:E1"])
        #expect(timetable.classState(on: day, name: "実験", period: 3) == .room("E9"))
        #expect(timetable.classState(on: day, name: "実験", period: 4) == .off())
        #expect(!timetable.hasWholeDayChange(on: day, name: "実験"))

        // 全コマを通常どおりに戻すと何も残らない
        timetable.setClass(on: day, name: "実験", period: 4, siblingPeriods: [3, 4], to: .normal, wholeDay: true)
        #expect(timetable.exceptions.isEmpty)
    }

    @Test func changeDoesNotTouchOtherDaysOrClasses() throws {
        var timetable = lab()
        let nextWeek = date("2026-10-15")
        timetable.setClass(on: nextWeek, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        timetable.setClass(on: day, name: "英語", period: 1, siblingPeriods: [1], to: .room("B2"), wholeDay: true)
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .normal, wholeDay: true)
        #expect(timetable.exceptions == [
            .classChange(date: nextWeek, className: "実験", period: nil, .off()),
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
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        timetable.setDay(on: day, to: .swap(asWeekday: 0))
        #expect(throws: TimetableError.noSuchClass(date: day, name: "実験", period: nil)) {
            try Schedule(timetable)
        }
    }

    @Test func editingCoursesDropsChangesThatLostTheirClass() throws {
        var timetable = lab()
        let nextWeek = date("2026-10-15")
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        timetable.setClass(on: nextWeek, name: "実験", period: 4, siblingPeriods: [3, 4], to: .room("E9"), wholeDay: false)
        timetable.setClass(on: day, name: "英語", period: 1, siblingPeriods: [1], to: .room("B2"), wholeDay: true)
        timetable.setDay(on: date("2026-10-21"), to: .off)

        // 4コマの「実験」を消すと、4コマだけに付けた変更は消え、全コマ対象の変更は3コマに残る
        timetable.courses.removeAll { $0.name == "実験" && $0.slot == .period(4) }
        #expect(throws: TimetableError.self) { try Schedule(timetable) }
        timetable.removeOrphanedClassChanges()
        #expect(timetable.exceptions == [
            .classChange(date: day, className: "実験", period: nil, .off()),
            .classChange(date: day, className: "英語", period: nil, .room("B2")),
            .dayOff(date: date("2026-10-21"), off: true),
        ])
        _ = try Schedule(timetable)

        // 「英語」を金曜に移すと、木曜に付けていた変更は消える
        timetable.courses = timetable.courses.map {
            $0.name == "英語" ? Course(name: "英語", weekday: 4, slot: $0.slot) : $0
        }
        timetable.removeOrphanedClassChanges()
        #expect(timetable.exceptions.count == 2)
        _ = try Schedule(timetable)
    }

    @Test func orphanCheckFollowsSwapsAndTerms() throws {
        let terms = ["3": DateRange(start: date("2026-10-05"), end: date("2026-12-01"))]
        var timetable = makeTimetable(
            exceptions: [
                .swap(date: date("2026-10-16"), asWeekday: 0),
                .classChange(date: date("2026-10-16"), className: "A", period: 1, .off()),  // 金曜を月曜授業に
                .classChange(date: date("2026-11-30"), className: "A", period: nil, .room("X")),
            ],
            courses: [Course(name: "A", weekday: 0, slot: .period(1), term: "3")],
            terms: terms)
        timetable.removeOrphanedClassChanges()
        #expect(timetable.exceptions.count == 3)

        // タームを短くすると、開講期間から外れた日の変更は消える
        timetable.terms["3"] = DateRange(start: date("2026-10-05"), end: date("2026-11-01"))
        timetable.removeOrphanedClassChanges()
        #expect(timetable.exceptions.count == 2)
        _ = try Schedule(timetable)
    }

    @Test func cancelledClassCanCarryAMakeupDate() throws {
        var timetable = lab()
        let saturday = date("2026-10-24")
        let makeup = Makeup.scheduled(date: saturday, periods: [1, 2])
        timetable.setClass(
            on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(makeup: makeup), wholeDay: true)
        #expect(timetable.classState(on: day, name: "実験", period: 4) == .off(makeup: makeup))

        let schedule = try Schedule(timetable)
        #expect(schedule.day(day).classes.filter { $0.name == "実験" }.map(\.makeupDate) == [saturday, saturday])
        #expect(schedule.day(saturday).classes.map { "\($0.period ?? 0):\($0.status.rawValue):\($0.room ?? "-")" }
            == ["1:extra:E1", "2:extra:E1"])
        #expect(Schedule.summary(of: schedule.week(containing: day)) == ["木曜の実験が休講（補講 10/24(土)）"])

        // 未定にすると補講は消え、未定の印だけが残る
        timetable.setClass(
            on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(makeup: .pending), wholeDay: true)
        let pending = try Schedule(timetable)
        #expect(pending.day(saturday).classes.isEmpty)
        #expect(pending.day(day).classes.filter(\.makeupPending).count == 2)
        #expect(Schedule.summary(of: pending.week(containing: day)) == ["木曜の実験が休講（補講未定）"])

        // 通常どおりに戻すと何も残らない
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .normal, wholeDay: true)
        #expect(timetable.exceptions.isEmpty)
    }

    @Test func narrowingKeepsTheMakeupOnlyOnce() throws {
        var timetable = lab()
        let makeup = Makeup.scheduled(date: date("2026-10-24"), periods: [1, 2])
        timetable.setClass(
            on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(makeup: makeup), wholeDay: true)
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .normal, wholeDay: false)
        #expect(timetable.exceptions == [.classChange(date: day, className: "実験", period: 4, .off(makeup: makeup))])
        #expect(try Schedule(timetable).day(date("2026-10-24")).classes.count == 2)
    }

    @Test func makeupNeedsValidPeriods() {
        func error(_ periods: [Int]) -> TimetableError? {
            var timetable = lab()
            timetable.setClass(
                on: day, name: "実験", period: 3, siblingPeriods: [3, 4],
                to: .off(makeup: .scheduled(date: date("2026-10-24"), periods: periods)), wholeDay: true)
            do { _ = try Schedule(timetable); return nil } catch { return error as? TimetableError }
        }
        #expect(error([1]) == nil)
        #expect(error([]) == .invalidMakeup(day))
        #expect(error([1, 1]) == .invalidMakeup(day))
        #expect(error([9]) == .unknownPeriod(9, at: "exceptions[0]"))
    }

    @Test func makeupSurvivesJSON() throws {
        var timetable = lab()
        timetable.setClass(
            on: day, name: "実験", period: 3, siblingPeriods: [3, 4],
            to: .off(makeup: .scheduled(date: date("2026-10-24"), periods: [1], room: "Z9")), wholeDay: true)
        timetable.setClass(
            on: day, name: "英語", period: 1, siblingPeriods: [1], to: .off(makeup: .pending), wholeDay: true)
        let data = try JSONEncoder().encode(timetable)
        #expect(try JSONDecoder().decode(Timetable.self, from: data) == timetable)
    }

    @Test func coursesAreGroupedAsOneClass() {
        let groups = lab().courseGroups
        #expect(groups.map(\.name) == ["実験", "英語"])
        #expect(groups[0].slots == [
            CourseSlot(weekday: 3, slot: .period(3)), CourseSlot(weekday: 3, slot: .period(4)),
        ])
    }

    @Test func editingAGroupChangesEveryPeriodTogether() throws {
        var timetable = lab()
        let nextWeek = date("2026-10-15")
        timetable.setClass(on: day, name: "実験", period: 3, siblingPeriods: [3, 4], to: .off(), wholeDay: true)
        timetable.setClass(on: nextWeek, name: "実験", period: 4, siblingPeriods: [3, 4], to: .room("E9"), wholeDay: false)
        var group = timetable.courseGroups[0]
        let old = group

        // 名前と教室を変えると、3・4コマの両方が変わり、登録済みの変更も付いてくる
        group.name = "実験II"
        group.room = "E5"
        timetable.replaceGroup(old, with: group)
        #expect(timetable.courses.filter { $0.name == "実験II" }.map(\.room) == ["E5", "E5"])
        #expect(!timetable.courses.contains { $0.name == "実験" })
        #expect(timetable.exceptions == [
            .classChange(date: day, className: "実験II", period: nil, .off()),
            .classChange(date: nextWeek, className: "実験II", period: 4, .room("E9")),
        ])
        _ = try Schedule(timetable)

        // 別の曜日のコマを足して4コマを外すと、4コマだけに付けた変更は消える
        var moved = group
        moved.slots = [CourseSlot(weekday: 3, slot: .period(3)), CourseSlot(weekday: 0, slot: .period(1))]
        timetable.replaceGroup(group, with: moved)
        #expect(timetable.courseGroups.first { $0.name == "実験II" }?.slots.count == 2)
        #expect(timetable.exceptions == [.classChange(date: day, className: "実験II", period: nil, .off())])
        _ = try Schedule(timetable)

        // 削除と追加
        timetable.replaceGroup(moved, with: nil)
        #expect(timetable.courses.map(\.name) == ["英語"])
        #expect(timetable.exceptions.isEmpty)
        timetable.replaceGroup(nil, with: CourseGroup(name: "新規", slots: [CourseSlot(weekday: 1, slot: .period(2))]))
        #expect(timetable.courses.last == Course(name: "新規", weekday: 1, slot: .period(2)))
    }
}
