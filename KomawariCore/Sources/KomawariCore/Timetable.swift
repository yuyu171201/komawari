/// コマ番号と時刻の対応。
public struct Period: Hashable, Sendable {
    public var number: Int
    public var start: ClockTime
    public var end: ClockTime

    public init(number: Int, start: ClockTime, end: ClockTime) {
        self.number = number
        self.start = start
        self.end = end
    }
}

/// 授業の時刻指定。コマ番号か、開始・終了時刻の直接指定のどちらか一方。
public enum Slot: Hashable, Sendable {
    case period(Int)
    case time(start: ClockTime, end: ClockTime)
}

/// 通常の時間割の授業1件。
public struct Course: Hashable, Sendable {
    public var name: String
    /// 0=月 ... 6=日。
    public var weekday: Int
    public var slot: Slot
    public var room: String?
    /// `Timetable.terms` のキー。nil は学期全体。
    public var term: String?

    public init(name: String, weekday: Int, slot: Slot, room: String? = nil, term: String? = nil) {
        self.name = name
        self.weekday = weekday
        self.slot = slot
        self.room = room
        self.term = term
    }
}

/// 補講として追加する授業1件。
public struct ExtraClass: Hashable, Sendable {
    public var name: String
    public var slot: Slot
    public var room: String?

    public init(name: String, slot: Slot, room: String? = nil) {
        self.name = name
        self.slot = slot
        self.room = room
    }
}

/// 特定の日の特定の授業に対する変更。
public enum ClassChange: Hashable, Sendable {
    case off
    case room(String)
}

/// 例外1件。
public enum ScheduleException: Hashable, Sendable {
    /// 振替: その日は `asWeekday` の曜日の授業として扱う。
    case swap(date: CalendarDate, asWeekday: Int)
    /// `off: true` は休講、`off: false` は祝日でも授業あり。
    case dayOff(date: CalendarDate, off: Bool)
    /// 補講。
    case extra(date: CalendarDate, ExtraClass)
    /// 教室変更、またはその授業だけ休講。`period` を省くと同名の全コマが対象。
    case classChange(date: CalendarDate, className: String, period: Int?, ClassChange)

    public var date: CalendarDate {
        switch self {
        case .swap(let date, _), .dayOff(let date, _), .extra(let date, _), .classChange(let date, _, _, _):
            return date
        }
    }
}

/// 時間割データ全体。JSON の形は timetable.yaml と同じ。
public struct Timetable: Hashable, Sendable {
    public var term: DateRange
    /// ターム名（"3", "4" など）と開講期間。
    public var terms: [String: DateRange]
    public var periods: [Period]
    public var courses: [Course]
    public var exceptions: [ScheduleException]

    public init(
        term: DateRange,
        terms: [String: DateRange] = [:],
        periods: [Period],
        courses: [Course] = [],
        exceptions: [ScheduleException] = []
    ) {
        self.term = term
        self.terms = terms
        self.periods = periods
        self.courses = courses
        self.exceptions = exceptions
    }
}

// MARK: - JSON

private struct AnyKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

private typealias Fields = KeyedDecodingContainer<AnyKey>

private extension KeyedDecodingContainer where Key == AnyKey {
    func has(_ name: String) -> Bool { contains(AnyKey(name)) }

    func rejectUnknown(_ allowed: Set<String>) throws {
        let unknown = allKeys.map(\.stringValue).filter { !allowed.contains($0) }.sorted()
        if !unknown.isEmpty {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "使えないキーがあります: \(unknown.joined(separator: ", "))"))
        }
    }

    /// `period` か `start`/`end` のどちらか一方を読む。
    func slot() throws -> Slot {
        let hasPeriod = has("period")
        let hasTimes = has("start") || has("end")
        guard hasPeriod != hasTimes else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "`period` か `start`/`end` のどちらか一方を指定してください"))
        }
        if hasPeriod { return .period(try decode(Int.self, forKey: AnyKey("period"))) }
        return .time(
            start: try decode(ClockTime.self, forKey: AnyKey("start")),
            end: try decode(ClockTime.self, forKey: AnyKey("end")))
    }

    /// 文字列でも数値でも書けるキー（ターム名）を文字列として読む。
    func label(_ name: String) throws -> String? {
        let key = AnyKey(name)
        guard has(name), try !decodeNil(forKey: key) else { return nil }
        if let number = try? decode(Int.self, forKey: key) { return String(number) }
        return try decode(String.self, forKey: key)
    }
}

private extension KeyedEncodingContainer where Key == AnyKey {
    mutating func encode(slot: Slot) throws {
        switch slot {
        case .period(let number):
            try encode(number, forKey: AnyKey("period"))
        case .time(let start, let end):
            try encode(start, forKey: AnyKey("start"))
            try encode(end, forKey: AnyKey("end"))
        }
    }
}

extension Course: Codable {
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyKey.self)
        try fields.rejectUnknown(["name", "weekday", "period", "start", "end", "room", "term"])
        name = try fields.decode(String.self, forKey: AnyKey("name"))
        weekday = try fields.decode(Int.self, forKey: AnyKey("weekday"))
        slot = try fields.slot()
        room = try fields.decodeIfPresent(String.self, forKey: AnyKey("room"))
        term = try fields.label("term")
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: AnyKey.self)
        try fields.encode(name, forKey: AnyKey("name"))
        try fields.encode(weekday, forKey: AnyKey("weekday"))
        try fields.encode(slot: slot)
        try fields.encodeIfPresent(room, forKey: AnyKey("room"))
        try fields.encodeIfPresent(term, forKey: AnyKey("term"))
    }
}

extension ExtraClass: Codable {
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyKey.self)
        try fields.rejectUnknown(["name", "period", "start", "end", "room"])
        name = try fields.decode(String.self, forKey: AnyKey("name"))
        slot = try fields.slot()
        room = try fields.decodeIfPresent(String.self, forKey: AnyKey("room"))
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: AnyKey.self)
        try fields.encode(name, forKey: AnyKey("name"))
        try fields.encode(slot: slot)
        try fields.encodeIfPresent(room, forKey: AnyKey("room"))
    }
}

extension ScheduleException: Codable {
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyKey.self)
        let date = try fields.decode(CalendarDate.self, forKey: AnyKey("date"))

        if fields.has("extra") {
            try fields.rejectUnknown(["date", "extra"])
            self = .extra(date: date, try fields.decode(ExtraClass.self, forKey: AnyKey("extra")))
        } else if fields.has("class") {
            try fields.rejectUnknown(["date", "class", "period", "room", "off"])
            let name = try fields.decode(String.self, forKey: AnyKey("class"))
            let period = try fields.decodeIfPresent(Int.self, forKey: AnyKey("period"))
            let off = try fields.decodeIfPresent(Bool.self, forKey: AnyKey("off")) ?? false
            let room = try fields.decodeIfPresent(String.self, forKey: AnyKey("room"))
            guard off != (room != nil) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: fields.codingPath,
                    debugDescription: "`class` には `room` か `off: true` のどちらか一方を指定してください"))
            }
            self = .classChange(date: date, className: name, period: period, room.map(ClassChange.room) ?? .off)
        } else if fields.has("as_weekday") {
            try fields.rejectUnknown(["date", "as_weekday"])
            self = .swap(date: date, asWeekday: try fields.decode(Int.self, forKey: AnyKey("as_weekday")))
        } else if fields.has("off") {
            try fields.rejectUnknown(["date", "off"])
            self = .dayOff(date: date, off: try fields.decode(Bool.self, forKey: AnyKey("off")))
        } else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: fields.codingPath,
                debugDescription: "`as_weekday` / `off` / `extra` / `class` のいずれかを指定してください"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: AnyKey.self)
        try fields.encode(date, forKey: AnyKey("date"))
        switch self {
        case .swap(_, let asWeekday):
            try fields.encode(asWeekday, forKey: AnyKey("as_weekday"))
        case .dayOff(_, let off):
            try fields.encode(off, forKey: AnyKey("off"))
        case .extra(_, let extra):
            try fields.encode(extra, forKey: AnyKey("extra"))
        case .classChange(_, let name, let period, let change):
            try fields.encode(name, forKey: AnyKey("class"))
            try fields.encodeIfPresent(period, forKey: AnyKey("period"))
            switch change {
            case .off: try fields.encode(true, forKey: AnyKey("off"))
            case .room(let room): try fields.encode(room, forKey: AnyKey("room"))
            }
        }
    }
}

extension Timetable: Codable {
    private struct Span: Codable {
        var start: ClockTime
        var end: ClockTime
    }

    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: AnyKey.self)
        try fields.rejectUnknown(["term", "terms", "periods", "classes", "exceptions"])
        term = try fields.decode(DateRange.self, forKey: AnyKey("term"))
        terms = try fields.decodeIfPresent([String: DateRange].self, forKey: AnyKey("terms")) ?? [:]

        let spans = try fields.decodeIfPresent([String: Span].self, forKey: AnyKey("periods")) ?? [:]
        periods = try spans.map { key, span in
            guard let number = Int(key) else {
                throw DecodingError.dataCorrupted(.init(
                    codingPath: fields.codingPath + [AnyKey("periods")],
                    debugDescription: "コマ番号は整数にしてください: \(key)"))
            }
            return Period(number: number, start: span.start, end: span.end)
        }.sorted { $0.number < $1.number }

        courses = try fields.decodeIfPresent([Course].self, forKey: AnyKey("classes")) ?? []
        exceptions = try fields.decodeIfPresent([ScheduleException].self, forKey: AnyKey("exceptions")) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: AnyKey.self)
        try fields.encode(term, forKey: AnyKey("term"))
        if !terms.isEmpty { try fields.encode(terms, forKey: AnyKey("terms")) }
        let spans = Dictionary(
            periods.map { (String($0.number), Span(start: $0.start, end: $0.end)) },
            uniquingKeysWith: { _, last in last })
        try fields.encode(spans, forKey: AnyKey("periods"))
        try fields.encode(courses, forKey: AnyKey("classes"))
        try fields.encode(exceptions, forKey: AnyKey("exceptions"))
    }
}
