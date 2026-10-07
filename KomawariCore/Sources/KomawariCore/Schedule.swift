/// 時間割データの内容が不正。
public enum TimetableError: Error, Hashable, Sendable, CustomStringConvertible {
    case termReversed
    case termRangeReversed(term: String)
    case invalidPeriodTimes(period: Int)
    case duplicatePeriod(Int)
    case unknownPeriod(Int, at: String)
    case unknownTerm(String, course: String)
    case invalidWeekday(Int, at: String)
    case invalidTimes(at: String)
    case duplicateSwap(CalendarDate)
    case duplicateDayOff(CalendarDate)
    case offAndSwap(CalendarDate)
    case noSuchClass(date: CalendarDate, name: String, period: Int?)
    case invalidMakeup(CalendarDate)

    public var description: String {
        switch self {
        case .termReversed:
            return "term: start が end より後になっています"
        case .termRangeReversed(let term):
            return "terms.\(term): start が end より後になっています"
        case .invalidPeriodTimes(let period):
            return "periods.\(period): start が end 以降になっています"
        case .duplicatePeriod(let period):
            return "periods.\(period): コマ番号が重複しています"
        case .unknownPeriod(let period, let place):
            return "\(place): コマ番号 \(period) は `periods` にありません"
        case .unknownTerm(let term, let course):
            return "\(course): ターム \(term) は `terms` にありません"
        case .invalidWeekday(let weekday, let place):
            return "\(place): 曜日は 0（月）〜 6（日）の整数にしてください: \(weekday)"
        case .invalidTimes(let place):
            return "\(place): start が end 以降になっています"
        case .duplicateSwap(let date):
            return "\(date) の `as_weekday` が重複しています"
        case .duplicateDayOff(let date):
            return "\(date) の `off` が重複しています"
        case .offAndSwap(let date):
            return "\(date) に `off: true` と `as_weekday` の両方があります"
        case .noSuchClass(let date, let name, let period):
            let target = period.map { "\(name)（\($0)コマ）" } ?? name
            return "\(date) に「\(target)」の授業はありません"
        case .invalidMakeup(let date):
            return "\(date) の補講のコマを1つ以上、重複なく選んでください"
        }
    }
}

/// 授業・日の状態。
public enum Status: String, Hashable, Sendable, Codable {
    case normal
    case swapped
    case off
    case extra
    case roomChanged = "room_changed"
}

/// 日が休みになった理由。
public enum OffReason: String, Hashable, Sendable, Codable {
    case exception
    case holiday
    case outOfTerm = "out_of_term"
}

/// ある日付に展開された授業1コマ。
public struct Session: Hashable, Sendable {
    public let date: CalendarDate
    public let name: String
    public let start: ClockTime
    public let end: ClockTime
    public let period: Int?
    public let room: String?
    public let status: Status
    /// 教室変更前の教室。
    public let originalRoom: String?
    /// 休講の代わりの日。
    public var makeupDate: CalendarDate? = nil
    /// 休講の代わりの日が未定。
    public var makeupPending = false
}

/// 1日分の展開結果。
public struct DayPlan: Hashable, Sendable {
    public let date: CalendarDate
    /// 振替を反映した「何曜日の授業か」。
    public let effectiveWeekday: Int
    /// normal / swapped / off のいずれか。
    public let status: Status
    public let offReason: OffReason?
    /// 祝日名（授業がある場合も入る）。
    public let holiday: String?
    /// 休講になった授業も `status == .off` で含む。
    public let classes: [Session]

    /// 実際に行われる授業。
    public var active: [Session] { classes.filter { $0.status != .off } }
}

/// 検証済みの時間割。日付ごとに「その日は何曜日の授業か」を決めて展開する。
public struct Schedule: Sendable {
    public static let weekdayNames = ["月", "火", "水", "木", "金", "土", "日"]

    public let timetable: Timetable
    private let courses: [ResolvedCourse]
    private let rules: [CalendarDate: DayRules]
    /// 休講の代わりの日（`Makeup.scheduled`）から作った補講。日付ごと。
    private let makeups: [CalendarDate: [ResolvedCourse]]

    private struct ResolvedCourse: Sendable {
        var name: String
        var weekday: Int?
        var period: Int?
        var start: ClockTime
        var end: ClockTime
        var room: String?
        var span: DateRange?

        func runs(on date: CalendarDate) -> Bool { span?.contains(date) ?? true }
    }

    private struct Change: Sendable {
        var name: String
        var period: Int?
        var change: ClassChange

        func targets(_ course: ResolvedCourse) -> Bool {
            name == course.name && (period == nil || period == course.period)
        }
    }

    /// 同じ日付の例外をまとめたもの。
    private struct DayRules: Sendable {
        var off: Bool?
        var asWeekday: Int?
        var extras: [ResolvedCourse] = []
        var changes: [Change] = []
    }

    /// 時間割を検証して読み込む。不正なら `TimetableError` を投げる。
    public init(_ timetable: Timetable) throws {
        guard timetable.term.start <= timetable.term.end else { throw TimetableError.termReversed }
        for (name, range) in timetable.terms.sorted(by: { $0.key < $1.key }) where range.start > range.end {
            throw TimetableError.termRangeReversed(term: name)
        }

        var periods: [Int: Period] = [:]
        for period in timetable.periods {
            guard period.start < period.end else { throw TimetableError.invalidPeriodTimes(period: period.number) }
            guard periods.updateValue(period, forKey: period.number) == nil else {
                throw TimetableError.duplicatePeriod(period.number)
            }
        }

        func resolve(_ slot: Slot, at place: String) throws -> (Int?, ClockTime, ClockTime) {
            switch slot {
            case .period(let number):
                guard let period = periods[number] else { throw TimetableError.unknownPeriod(number, at: place) }
                return (number, period.start, period.end)
            case .time(let start, let end):
                guard start < end else { throw TimetableError.invalidTimes(at: place) }
                return (nil, start, end)
            }
        }

        var courses: [ResolvedCourse] = []
        for (index, course) in timetable.courses.enumerated() {
            let place = "classes[\(index)]"
            guard (0...6).contains(course.weekday) else {
                throw TimetableError.invalidWeekday(course.weekday, at: place)
            }
            let (period, start, end) = try resolve(course.slot, at: place)
            var span: DateRange?
            if let term = course.term {
                guard let range = timetable.terms[term] else {
                    throw TimetableError.unknownTerm(term, course: place)
                }
                span = range
            }
            courses.append(ResolvedCourse(
                name: course.name, weekday: course.weekday, period: period,
                start: start, end: end, room: course.room, span: span))
        }

        var rules: [CalendarDate: DayRules] = [:]
        var dateOrder: [CalendarDate] = []
        for (index, exception) in timetable.exceptions.enumerated() {
            let place = "exceptions[\(index)]"
            if rules[exception.date] == nil { dateOrder.append(exception.date) }
            var day = rules[exception.date] ?? DayRules()
            switch exception {
            case .swap(let date, let asWeekday):
                guard (0...6).contains(asWeekday) else { throw TimetableError.invalidWeekday(asWeekday, at: place) }
                guard day.asWeekday == nil else { throw TimetableError.duplicateSwap(date) }
                day.asWeekday = asWeekday
            case .dayOff(let date, let off):
                guard day.off == nil else { throw TimetableError.duplicateDayOff(date) }
                day.off = off
            case .extra(_, let extra):
                let (period, start, end) = try resolve(extra.slot, at: place)
                day.extras.append(ResolvedCourse(
                    name: extra.name, weekday: nil, period: period,
                    start: start, end: end, room: extra.room, span: nil))
            case .classChange(_, let name, let period, let change):
                if let period, periods[period] == nil { throw TimetableError.unknownPeriod(period, at: place) }
                if case .off(.scheduled(_, let numbers, _)) = change {
                    guard !numbers.isEmpty, Set(numbers).count == numbers.count else {
                        throw TimetableError.invalidMakeup(exception.date)
                    }
                    for number in numbers where periods[number] == nil {
                        throw TimetableError.unknownPeriod(number, at: place)
                    }
                }
                day.changes.append(Change(name: name, period: period, change: change))
            }
            if day.off == true, day.asWeekday != nil { throw TimetableError.offAndSwap(exception.date) }
            rules[exception.date] = day
        }

        // 教室変更などの対象が、その日に実際にある授業かを確かめる（授業名の打ち間違い対策）
        var makeups: [CalendarDate: [ResolvedCourse]] = [:]
        for date in dateOrder {
            guard let day = rules[date] else { continue }
            let weekday = day.asWeekday ?? date.weekday
            let inTerm = timetable.term.contains(date)
            for change in day.changes {
                let target = inTerm ? courses.first {
                    $0.weekday == weekday && $0.runs(on: date) && change.targets($0)
                } : nil
                guard let target else {
                    throw TimetableError.noSuchClass(date: date, name: change.name, period: change.period)
                }
                // 代わりの日が決まっていれば、その日の補講として載せる
                if case .off(.scheduled(let makeupDate, let numbers, let room)) = change.change {
                    for number in numbers {
                        guard let period = periods[number] else { continue }
                        makeups[makeupDate, default: []].append(ResolvedCourse(
                            name: change.name, weekday: nil, period: number,
                            start: period.start, end: period.end, room: room ?? target.room, span: nil))
                    }
                }
            }
        }

        self.timetable = timetable
        self.courses = courses
        self.rules = rules
        self.makeups = makeups
    }

    /// 日付 `date` の授業を、例外と祝日を反映して展開する。
    public func day(_ date: CalendarDate) -> DayPlan {
        let rule = rules[date]
        let holiday = JapaneseHolidays.name(on: date)
        let inTerm = timetable.term.contains(date)
        let swapped = rule?.asWeekday != nil
        let weekday = rule?.asWeekday ?? date.weekday

        var offReason: OffReason?
        if !inTerm {
            offReason = .outOfTerm
        } else if rule?.off == true {
            offReason = .exception
        } else if holiday != nil, !(swapped || rule?.off == false) {
            // 祝日は休み。ただし例外で振替や off: false が明示されていれば授業を行う
            offReason = .holiday
        }

        var sessions: [Session] = []
        if inTerm {
            for course in courses where course.weekday == weekday && course.runs(on: date) {
                var status: Status = swapped ? .swapped : .normal
                var room = course.room
                var originalRoom: String?
                var makeupDate: CalendarDate?
                var makeupPending = false
                for change in rule?.changes ?? [] where change.targets(course) {
                    switch change.change {
                    case .off(let makeup):
                        status = .off
                        makeupPending = makeup == .pending
                        if case .scheduled(let date, _, _) = makeup { makeupDate = date } else { makeupDate = nil }
                    case .room(let newRoom):
                        guard newRoom != course.room else { continue }
                        room = newRoom
                        originalRoom = course.room
                        if status != .off { status = .roomChanged }
                    }
                }
                if offReason != nil { status = .off }
                sessions.append(Session(
                    date: date, name: course.name, start: course.start, end: course.end,
                    period: course.period, room: room, status: status, originalRoom: originalRoom,
                    makeupDate: makeupDate, makeupPending: makeupPending))
            }
        }

        // 補講は日付を明示した追加なので、休みの日や学期外でもそのまま載せる
        for extra in (rule?.extras ?? []) + (makeups[date] ?? []) {
            sessions.append(Session(
                date: date, name: extra.name, start: extra.start, end: extra.end,
                period: extra.period, room: extra.room, status: .extra, originalRoom: nil))
        }

        // 開始・終了・授業名の順。同じなら登録順を保つ
        let ordered = sessions.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.start != y.start { return x.start < y.start }
            if x.end != y.end { return x.end < y.end }
            if x.name != y.name { return x.name.unicodeScalars.lexicographicallyPrecedes(y.name.unicodeScalars) }
            return a.offset < b.offset
        }.map(\.element)

        return DayPlan(
            date: date, effectiveWeekday: weekday,
            status: offReason != nil ? .off : swapped ? .swapped : .normal,
            offReason: offReason, holiday: holiday, classes: ordered)
    }

    /// `date` を含む週の日ごとの授業を返す。月〜金は必ず含み、土日は授業がある場合だけ含む。
    public func week(containing date: CalendarDate) -> [DayPlan] {
        let monday = date.monday
        let days = (0..<7).map { day(monday.adding(days: $0)) }
        var result = Array(days[..<5])
        if !days[5].classes.isEmpty || !days[6].classes.isEmpty { result.append(days[5]) }
        if !days[6].classes.isEmpty { result.append(days[6]) }
        return result
    }

    /// 学期の全日付（学期外に補講があればその日まで）を走査して展開する。
    public func term() -> [DayPlan] {
        let extraDates = rules.filter { !$0.value.extras.isEmpty }.map(\.key) + makeups.keys
        let start = ([timetable.term.start] + extraDates).min()!
        let end = ([timetable.term.end] + extraDates).max()!
        return (start.ordinal...end.ordinal).map { day(CalendarDate(ordinal: $0)) }
    }

    /// 週の変更点を短い文のリストにする（例: 「水曜が月曜授業」）。変更がなければ空。
    public static func summary(of days: [DayPlan]) -> [String] {
        let weekdays = days.filter { $0.date.weekday < 5 }
        let outOfTerm = weekdays.map { $0.offReason == .outOfTerm }

        var items: [String] = []
        if !outOfTerm.isEmpty {
            if outOfTerm.allSatisfy({ $0 }) {
                items.append("学期外")
            } else if outOfTerm.first == true, let first = weekdays.first(where: { $0.offReason != .outOfTerm }) {
                items.append("\(shortDate(first.date))から授業開始")
            } else if outOfTerm.last == true, let last = weekdays.last(where: { $0.offReason != .outOfTerm }) {
                items.append("\(shortDate(last.date))で授業終了")
            }
        }

        for day in days {
            let weekday = weekdayNames[day.date.weekday] + "曜"
            if day.status == .swapped {
                items.append("\(weekday)が\(weekdayNames[day.effectiveWeekday])曜授業")
            } else if day.offReason == .exception {
                items.append("\(weekday)が休講")
            } else if day.offReason == .holiday, let holiday = day.holiday {
                items.append("\(weekday)が祝日（\(holiday)）")
            } else if day.offReason == nil, let holiday = day.holiday {
                items.append("\(weekday)が祝日（\(holiday)）だが授業あり")
            }

            for session in day.classes {
                switch session.status {
                case .extra:
                    items.append("\(weekday)に補講「\(session.name)」")
                case .roomChanged:
                    items.append("\(weekday)の\(session.name)が\(session.room ?? "")に教室変更")
                case .off where day.status != .off:
                    if let makeup = session.makeupDate {
                        items.append("\(weekday)の\(session.name)が休講（補講 \(shortDate(makeup))）")
                    } else if session.makeupPending {
                        items.append("\(weekday)の\(session.name)が休講（補講未定）")
                    } else {
                        items.append("\(weekday)の\(session.name)が休講")
                    }
                default:
                    break
                }
            }
        }

        // 同じ授業が1日に複数コマあると同じ文が並ぶので、1つにまとめる
        var seen = Set<String>()
        return items.filter { seen.insert($0).inserted }
    }

    private static func shortDate(_ date: CalendarDate) -> String {
        "\(date.month)/\(date.day)(\(weekdayNames[date.weekday]))"
    }
}
