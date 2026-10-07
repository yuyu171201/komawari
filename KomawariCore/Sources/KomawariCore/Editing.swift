/// 画面から登録する、ある授業のその日の扱い。
public enum ClassState: Hashable, Sendable {
    case normal
    case off
    case room(String)
}

/// 画面から登録する、その日全体の扱い。
public enum DayState: Hashable, Sendable {
    case normal
    /// 休講（この日は授業なし）。
    case off
    /// 振替: 指定した曜日（0=月）の授業を行う。
    case swap(asWeekday: Int)
    /// 祝日だが授業を行う。
    case hold
}

/// 授業変更の登録。例外のリストを書き換えるだけで、整合性は `Schedule(_:)` で確かめる。
extension Timetable {
    /// 登録済みの例外から見た、その日のその授業（コマ）の扱い。
    public func classState(on date: CalendarDate, name: String, period: Int?) -> ClassState {
        var state = ClassState.normal
        for case .classChange(date, name, let target, let change) in exceptions
        where target == nil || target == period {
            switch change {
            case .off: return .off
            case .room(let room): state = .room(room)
            }
        }
        return state
    }

    /// その日のその授業に、コマを絞らない変更（同名の全コマが対象）が登録されているか。
    public func hasWholeDayChange(on date: CalendarDate, name: String) -> Bool {
        exceptions.contains {
            if case .classChange(date, name, nil, _) = $0 { return true }
            return false
        }
    }

    /// その日のその授業を休講・教室変更・通常どおりにする。
    ///
    /// - Parameters:
    ///   - period: 対象のコマ。`wholeDay` が false のときだけ使う。
    ///   - siblingPeriods: その日にある同名の授業のコマ番号すべて。
    ///   - wholeDay: 同名の全コマに適用するか。false ならそのコマだけ変え、全コマに掛かっていた
    ///     変更は他のコマに付け直す。
    public mutating func setClass(
        on date: CalendarDate,
        name: String,
        period: Int?,
        siblingPeriods: [Int],
        to state: ClassState,
        wholeDay: Bool
    ) {
        let whole = wholeDay || period == nil
        var kept: [ScheduleException] = []
        var carried: [ScheduleException] = []
        for exception in exceptions {
            guard case .classChange(date, name, let target, let change) = exception else {
                kept.append(exception)
                continue
            }
            if whole { continue }
            if target == nil {
                carried += siblingPeriods.filter { $0 != period }.map {
                    .classChange(date: date, className: name, period: $0, change)
                }
            } else if target != period {
                kept.append(exception)
            }
        }

        exceptions = kept + carried
        let target = whole ? nil : period
        switch state {
        case .normal: break
        case .off: exceptions.append(.classChange(date: date, className: name, period: target, .off))
        case .room(let room): exceptions.append(.classChange(date: date, className: name, period: target, .room(room)))
        }
    }

    /// 登録済みの例外から見た、その日全体の扱い。
    public func dayState(on date: CalendarDate) -> DayState {
        var state = DayState.normal
        for exception in exceptions {
            switch exception {
            case .swap(date, let asWeekday): return .swap(asWeekday: asWeekday)
            case .dayOff(date, let off): state = off ? .off : .hold
            default: break
            }
        }
        return state
    }

    /// その日を振替・休講・祝日でも授業あり・通常どおりにする。
    public mutating func setDay(on date: CalendarDate, to state: DayState) {
        exceptions.removeAll {
            switch $0 {
            case .swap(date, _), .dayOff(date, _): true
            default: false
            }
        }
        switch state {
        case .normal: break
        case .off: exceptions.append(.dayOff(date: date, off: true))
        case .hold: exceptions.append(.dayOff(date: date, off: false))
        case .swap(let asWeekday): exceptions.append(.swap(date: date, asWeekday: asWeekday))
        }
    }

    /// 補講を追加する。
    public mutating func addExtra(on date: CalendarDate, _ extra: ExtraClass) {
        exceptions.append(.extra(date: date, extra))
    }

    /// 補講を1件取り消す。該当がなければ false。
    @discardableResult
    public mutating func removeExtra(on date: CalendarDate, name: String, slot: Slot) -> Bool {
        guard let index = exceptions.firstIndex(where: {
            if case .extra(date, let extra) = $0 { return extra.name == name && extra.slot == slot }
            return false
        }) else { return false }
        exceptions.remove(at: index)
        return true
    }

    /// 授業名の一覧（補講の入力候補用）。
    public var courseNames: [String] {
        Array(Set(courses.map(\.name))).sorted()
    }
}
