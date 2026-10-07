import KomawariCore
import SwiftUI

/// 登録画面を開く対象。
enum EditTarget: Identifiable {
    /// 授業カード（通常授業なら休講・教室変更、補講なら削除）。
    case session(DayPlan, Session)
    /// 空きコマ（補講の追加）。
    case slot(DayPlan, Period)
    /// 日付（振替・休講）。
    case day(DayPlan)

    var id: String {
        switch self {
        case .session(let day, let session):
            "session-\(day.date)-\(session.name)-\(session.start)-\(session.status.rawValue)"
        case .slot(let day, let period): "slot-\(day.date)-\(period.number)"
        case .day(let day): "day-\(day.date)"
        }
    }
}

private func label(_ date: CalendarDate) -> String {
    "\(date.month)/\(date.day)(\(Schedule.weekdayNames[date.weekday]))"
}

/// 授業変更の登録画面。対象に応じた入力欄を出し、保存時に整合性を確かめる。
struct EditSheet: View {
    let target: EditTarget
    let timetable: Timetable

    var body: some View {
        switch target {
        case .session(let day, let session) where session.status == .extra:
            ExtraDetailForm(day: day, session: session)
        case .session(let day, let session):
            ClassForm(day: day, session: session, timetable: timetable)
        case .slot(let day, let period):
            AddExtraForm(day: day, period: period, timetable: timetable)
        case .day(let day):
            DayForm(day: day, timetable: timetable)
        }
    }
}

/// 登録画面の共通の枠。保存に失敗したら理由を表示して閉じない。
private struct FormScaffold<Content: View>: View {
    let title: String
    let subtitle: String
    var saveLabel = "保存"
    var saveRole: ButtonRole?
    /// nil なら保存ボタンを出さない。
    let save: ((inout Timetable) throws -> Void)?
    @ViewBuilder let content: Content

    @Environment(TimetableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                content
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(title).font(.headline).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(save == nil ? "閉じる" : "キャンセル") { dismiss() }
                }
                if let save {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saveLabel, role: saveRole) { commit(save) }
                    }
                }
            }
        }
        .tint(Theme.main)
    }

    private func commit(_ save: (inout Timetable) throws -> Void) {
        do {
            try store.edit(save)
            dismiss()
        } catch let error as TimetableError {
            errorMessage = error.description
        } catch let error as InputError {
            errorMessage = error.message
        } catch {
            errorMessage = "保存できませんでした: \(error.localizedDescription)"
        }
    }
}

private struct InputError: Error {
    let message: String
}

// MARK: - 授業: 休講・教室変更

private struct ClassForm: View {
    let day: DayPlan
    let session: Session
    private let siblingPeriods: [Int]

    private enum Choice: Hashable { case normal, off, room }
    @State private var choice: Choice
    @State private var room: String
    @State private var wholeDay: Bool

    init(day: DayPlan, session: Session, timetable: Timetable) {
        self.day = day
        self.session = session
        siblingPeriods = day.classes
            .filter { $0.name == session.name && $0.status != .extra }
            .compactMap(\.period)

        switch timetable.classState(on: day.date, name: session.name, period: session.period) {
        case .normal:
            _choice = State(initialValue: .normal)
            _room = State(initialValue: "")
            _wholeDay = State(initialValue: true)
        case .off:
            _choice = State(initialValue: .off)
            _room = State(initialValue: "")
            _wholeDay = State(initialValue: timetable.hasWholeDayChange(on: day.date, name: session.name))
        case .room(let current):
            _choice = State(initialValue: .room)
            _room = State(initialValue: current)
            _wholeDay = State(initialValue: timetable.hasWholeDayChange(on: day.date, name: session.name))
        }
    }

    private var canNarrow: Bool { session.period != nil && siblingPeriods.count > 1 }

    var body: some View {
        FormScaffold(
            title: session.name,
            subtitle: "\(label(day.date)) " + (session.period.map { "\($0)限 " } ?? "") + "\(session.start)–\(session.end)",
            save: { timetable in
                let state: ClassState
                switch choice {
                case .normal: state = .normal
                case .off: state = .off
                case .room:
                    let name = room.trimmingCharacters(in: .whitespaces)
                    guard !name.isEmpty else { throw InputError(message: "新しい教室を入力してください") }
                    state = .room(name)
                }
                timetable.setClass(
                    on: day.date, name: session.name, period: session.period,
                    siblingPeriods: siblingPeriods, to: state, wholeDay: !canNarrow || wholeDay)
            }
        ) {
            Section {
                Picker("この授業", selection: $choice) {
                    Text("通常どおり").tag(Choice.normal)
                    Text("休講").tag(Choice.off)
                    Text("教室変更").tag(Choice.room)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                if choice == .room {
                    TextField("新しい教室", text: $room)
                    if let original = session.originalRoom ?? (session.status == .roomChanged ? nil : session.room) {
                        LabeledContent("いつもの教室", value: original)
                    }
                }
            }
            if canNarrow {
                Section {
                    Toggle("この日の全コマ（\(siblingPeriods.count)コマ）に適用", isOn: $wholeDay)
                } footer: {
                    Text("オフにすると \(session.period ?? 0)限だけを変更します。")
                }
            }
        }
    }
}

// MARK: - 補講

private struct ExtraDetailForm: View {
    let day: DayPlan
    let session: Session

    var body: some View {
        FormScaffold(
            title: "\(session.name)（補講）",
            subtitle: label(day.date),
            saveLabel: "削除",
            saveRole: .destructive,
            save: { timetable in
                let slot: Slot = session.period.map(Slot.period) ?? .time(start: session.start, end: session.end)
                timetable.removeExtra(on: day.date, name: session.name, slot: slot)
            }
        ) {
            Section {
                LabeledContent("時間", value: (session.period.map { "\($0)限 " } ?? "") + "\(session.start)–\(session.end)")
                if let room = session.room { LabeledContent("教室", value: room) }
            } footer: {
                Text("「削除」でこの補講の登録を取り消します。")
            }
        }
    }
}

/// 補講の入力欄（授業名・教室・コマ）。
private struct ExtraFields: View {
    @Binding var name: String
    @Binding var room: String
    @Binding var period: Int
    let periods: [Period]
    let courseNames: [String]

    var body: some View {
        Section("補講を追加") {
            HStack {
                TextField("授業名", text: $name)
                if !courseNames.isEmpty {
                    Menu {
                        ForEach(courseNames, id: \.self) { candidate in
                            Button(candidate) { name = candidate }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("授業から選ぶ")
                }
            }
            TextField("教室（任意）", text: $room)
            Picker("コマ", selection: $period) {
                ForEach(periods, id: \.number) { Text("\($0.number)限 \($0.start)–\($0.end)").tag($0.number) }
            }
        }
    }

    static func extra(name: String, room: String, period: Int) throws -> ExtraClass {
        let name = name.trimmingCharacters(in: .whitespaces)
        let room = room.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw InputError(message: "授業名を入力してください") }
        return ExtraClass(name: name, slot: .period(period), room: room.isEmpty ? nil : room)
    }
}

private struct AddExtraForm: View {
    let day: DayPlan
    let timetable: Timetable
    @State private var name = ""
    @State private var room = ""
    @State private var period: Int

    init(day: DayPlan, period: Period, timetable: Timetable) {
        self.day = day
        self.timetable = timetable
        _period = State(initialValue: period.number)
    }

    var body: some View {
        FormScaffold(
            title: "補講を追加",
            subtitle: label(day.date),
            saveLabel: "追加",
            save: { try $0.addExtra(on: day.date, ExtraFields.extra(name: name, room: room, period: period)) }
        ) {
            ExtraFields(
                name: $name, room: $room, period: $period,
                periods: timetable.periods, courseNames: timetable.courseNames)
        }
    }
}

// MARK: - 日: 振替・休講

private struct DayForm: View {
    let day: DayPlan
    let timetable: Timetable

    private enum Choice: Hashable { case normal, swap, off, hold }
    @State private var choice: Choice
    @State private var asWeekday: Int

    init(day: DayPlan, timetable: Timetable) {
        self.day = day
        self.timetable = timetable
        let fallback = day.date.weekday == 0 ? 1 : 0
        switch timetable.dayState(on: day.date) {
        case .normal:
            _choice = State(initialValue: .normal)
            _asWeekday = State(initialValue: fallback)
        case .off:
            _choice = State(initialValue: .off)
            _asWeekday = State(initialValue: fallback)
        case .hold:
            _choice = State(initialValue: .hold)
            _asWeekday = State(initialValue: fallback)
        case .swap(let weekday):
            _choice = State(initialValue: .swap)
            _asWeekday = State(initialValue: weekday)
        }
    }

    private var inTerm: Bool { timetable.term.contains(day.date) }

    var body: some View {
        FormScaffold(
            title: label(day.date),
            subtitle: inTerm ? (day.holiday ?? "この日全体の変更") : "学期外",
            save: inTerm ? { timetable in
                let state: DayState = switch choice {
                case .normal: .normal
                case .swap: .swap(asWeekday: asWeekday)
                case .off: .off
                case .hold: .hold
                }
                timetable.setDay(on: day.date, to: state)
            } : nil
        ) {
            if inTerm {
                Section {
                    Picker("この日", selection: $choice) {
                        Text(day.holiday == nil ? "通常どおり" : "通常どおり（祝日のため休み）").tag(Choice.normal)
                        Text("振替（別の曜日の授業）").tag(Choice.swap)
                        if day.holiday == nil {
                            Text("休講（この日は授業なし）").tag(Choice.off)
                        } else {
                            Text("祝日だが授業を行う").tag(Choice.hold)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    if choice == .swap {
                        Picker("何曜日の授業にするか", selection: $asWeekday) {
                            ForEach(0..<5, id: \.self) { weekday in
                                if weekday != day.date.weekday {
                                    Text("\(Schedule.weekdayNames[weekday])曜授業").tag(weekday)
                                }
                            }
                        }
                    }
                }
            } else {
                Section {
                    Text("学期外の日です。補講は空いているコマをタップして追加できます。")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
