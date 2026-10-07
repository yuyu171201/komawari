import Foundation
import Testing

@testable import KomawariCore

// Python 版（Scripts/make_golden.py）が書き出した結果と、Swift 版の結果を突き合わせる

struct GoldenSession: Decodable, Equatable {
    var name: String
    var period: Int?
    var start: String
    var end: String
    var room: String?
    var status: String
    var original_room: String?
}

struct GoldenDay: Decodable, Equatable {
    var date: String
    var effective_weekday: Int
    var status: String
    var off_reason: String?
    var holiday: String?
    var classes: [GoldenSession]

    init(_ day: DayPlan) {
        date = day.date.description
        effective_weekday = day.effectiveWeekday
        status = day.status.rawValue
        off_reason = day.offReason?.rawValue
        holiday = day.holiday
        classes = day.classes.map {
            GoldenSession(
                name: $0.name, period: $0.period, start: $0.start.description, end: $0.end.description,
                room: $0.room, status: $0.status.rawValue, original_room: $0.originalRoom)
        }
    }
}

struct GoldenWeek: Decodable {
    var monday: CalendarDate
    var dates: [String]
    var summary: [String]
}

struct GoldenCase: Decodable {
    var name: String
    var timetable: Timetable
    var days: [GoldenDay]
    var weeks: [GoldenWeek]
}

struct GoldenHolidays: Decodable {
    var from: Int
    var to: Int
    var holidays: [String: String]
}

func golden<T: Decodable>(_ file: String, as type: T.Type) throws -> T {
    let url = try #require(Bundle.module.url(forResource: file, withExtension: "json", subdirectory: "Golden"))
    return try JSONDecoder().decode(type, from: Data(contentsOf: url))
}

@Suite struct GoldenTests {
    static let caseNames = ["fixture", "example", "synthetic"]

    @Test(arguments: caseNames)
    func everyDayOfTheTermMatchesPython(name: String) throws {
        let cases = try golden("cases", as: [GoldenCase].self)
        let expected = try #require(cases.first { $0.name == name })
        let actual = try Schedule(expected.timetable).term().map(GoldenDay.init)

        #expect(actual.count == expected.days.count)
        for (mine, theirs) in zip(actual, expected.days) {
            #expect(mine == theirs, "\(name) \(theirs.date)")
        }
    }

    @Test(arguments: caseNames)
    func everyWeekMatchesPython(name: String) throws {
        let cases = try golden("cases", as: [GoldenCase].self)
        let expected = try #require(cases.first { $0.name == name })
        let schedule = try Schedule(expected.timetable)

        #expect(expected.weeks.count > 15)
        for week in expected.weeks {
            let days = schedule.week(containing: week.monday)
            #expect(days.map(\.date.description) == week.dates, "\(name) \(week.monday)")
            #expect(Schedule.summary(of: days) == week.summary, "\(name) \(week.monday)")
        }
    }

    @Test func holidaysMatchJpholiday() throws {
        let expected = try golden("holidays", as: GoldenHolidays.self)
        let first = try #require(CalendarDate(year: expected.from, month: 1, day: 1))
        let last = try #require(CalendarDate(year: expected.to, month: 12, day: 31))

        var actual: [String: String] = [:]
        for ordinal in first.ordinal...last.ordinal {
            let date = CalendarDate(ordinal: ordinal)
            if let name = JapaneseHolidays.name(on: date) { actual[date.description] = name }
        }
        #expect(expected.holidays.count > 700)
        #expect(actual == expected.holidays)
    }

    @Test(arguments: caseNames)
    func timetableSurvivesJSONRoundTrip(name: String) throws {
        let cases = try golden("cases", as: [GoldenCase].self)
        let timetable = try #require(cases.first { $0.name == name }).timetable
        let data = try JSONEncoder().encode(timetable)
        #expect(try JSONDecoder().decode(Timetable.self, from: data) == timetable)
    }
}
