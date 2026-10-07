/// タイムゾーンを持たない暦上の日付。JSON では "YYYY-MM-DD"。
public struct CalendarDate: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// 実在しない日付（2/30 など）は nil。
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1 else { return nil }
        let candidate = CalendarDate(ordinal: Self.ordinal(year: year, month: month, day: day))
        guard candidate.month == month, candidate.day == day else { return nil }
        self = candidate
    }

    /// "YYYY-MM-DD" を読む。
    public init?(_ text: String) {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// 1970-01-01 を 0 とする通算日から作る。
    public init(ordinal: Int) {
        // Howard Hinnant の civil_from_days
        let z = ordinal + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        day = doy - (153 * mp + 2) / 5 + 1
        month = mp < 10 ? mp + 3 : mp - 9
        year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    }

    /// 1970-01-01 を 0 とする通算日。
    public var ordinal: Int { Self.ordinal(year: year, month: month, day: day) }

    /// 0=月 ... 6=日。
    public var weekday: Int { ((ordinal % 7) + 7 + 3) % 7 }

    public func adding(days: Int) -> CalendarDate { CalendarDate(ordinal: ordinal + days) }

    /// その週の月曜日。
    public var monday: CalendarDate { adding(days: -weekday) }

    public var description: String {
        "\(Self.pad(year, 4))-\(Self.pad(month, 2))-\(Self.pad(day, 2))"
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool { lhs.ordinal < rhs.ordinal }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = CalendarDate(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "日付は YYYY-MM-DD で書いてください: \(text)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    private static func ordinal(year: Int, month: Int, day: Int) -> Int {
        // Howard Hinnant の days_from_civil
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    static func pad(_ value: Int, _ width: Int) -> String {
        let text = String(value)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
}

/// 時刻（時・分）。JSON では "HH:MM"。
public struct ClockTime: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    /// 0:00 からの分。
    public let minutes: Int

    public init?(hour: Int, minute: Int) {
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }
        minutes = hour * 60 + minute
    }

    /// "HH:MM" または "H:MM" を読む。
    public init?(_ text: String) {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, (1...2).contains(parts[0].count), parts[1].count == 2,
              let hour = Int(parts[0]), let minute = Int(parts[1])
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }
    public var description: String { "\(CalendarDate.pad(hour, 2)):\(CalendarDate.pad(minute, 2))" }

    public static func < (lhs: ClockTime, rhs: ClockTime) -> Bool { lhs.minutes < rhs.minutes }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let time = ClockTime(text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "時刻は HH:MM で書いてください: \(text)")
        }
        self = time
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

/// 両端を含む日付の範囲。
public struct DateRange: Hashable, Sendable, Codable {
    public var start: CalendarDate
    public var end: CalendarDate

    public init(start: CalendarDate, end: CalendarDate) {
        self.start = start
        self.end = end
    }

    public func contains(_ date: CalendarDate) -> Bool { start <= date && date <= end }
}
