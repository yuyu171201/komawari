/// 日本の祝日（国民の祝日に関する法律）。2020年以降の規定に対応する。
public enum JapaneseHolidays {
    /// 祝日ならその名前を返す。振替休日は「〇〇 振替休日」、祝日に挟まれた平日は「国民の休日」。
    public static func name(on date: CalendarDate) -> String? {
        if let name = fixedName(on: date) { return name }

        // 振替休日: 日曜の祝日のあと、最初の祝日でない日
        var previous = date.adding(days: -1)
        while let name = fixedName(on: previous) {
            if previous.weekday == 6 { return "\(name) 振替休日" }
            previous = previous.adding(days: -1)
        }

        // 国民の休日: 前日と翌日がともに祝日である平日
        if date.weekday != 6,
           fixedName(on: date.adding(days: -1)) != nil,
           fixedName(on: date.adding(days: 1)) != nil
        {
            return "国民の休日"
        }
        return nil
    }

    /// 法律で日付が決まっている祝日（振替休日・国民の休日を含まない）。
    private static func fixedName(on date: CalendarDate) -> String? {
        let (year, month, day) = (date.year, date.month, date.day)
        func isMonday(nth: Int) -> Bool { date.weekday == 0 && (day - 1) / 7 == nth - 1 }

        switch month {
        case 1:
            if day == 1 { return "元日" }
            if isMonday(nth: 2) { return "成人の日" }
        case 2:
            if day == 11 { return "建国記念の日" }
            if day == 23 { return "天皇誕生日" }
        case 3:
            if day == springEquinox(year) { return "春分の日" }
        case 4:
            if day == 29 { return "昭和の日" }
        case 5:
            if day == 3 { return "憲法記念日" }
            if day == 4 { return "みどりの日" }
            if day == 5 { return "こどもの日" }
        case 7:
            // 2020・2021年は東京オリンピックの特例で移動した
            switch year {
            case 2020:
                if day == 23 { return "海の日" }
                if day == 24 { return "スポーツの日" }
            case 2021:
                if day == 22 { return "海の日" }
                if day == 23 { return "スポーツの日" }
            default:
                if isMonday(nth: 3) { return "海の日" }
            }
        case 8:
            let mountainDay = year == 2020 ? 10 : year == 2021 ? 8 : 11
            if day == mountainDay { return "山の日" }
        case 9:
            if isMonday(nth: 3) { return "敬老の日" }
            if day == autumnEquinox(year) { return "秋分の日" }
        case 10:
            if year != 2020, year != 2021, isMonday(nth: 2) { return "スポーツの日" }
        case 11:
            if day == 3 { return "文化の日" }
            if day == 23 { return "勤労感謝の日" }
        default:
            break
        }
        return nil
    }

    // 春分・秋分の日は天文計算による近似式（1980〜2099年）
    private static func springEquinox(_ year: Int) -> Int {
        Int(20.8431 + 0.242194 * Double(year - 1980)) - (year - 1980) / 4
    }

    private static func autumnEquinox(_ year: Int) -> Int {
        Int(23.2488 + 0.242194 * Double(year - 1980)) - (year - 1980) / 4
    }
}
