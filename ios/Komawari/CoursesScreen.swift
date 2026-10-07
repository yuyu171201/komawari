import KomawariCore
import SwiftUI

/// 標準の時間割（毎週の授業）の編集画面。曜日ごとに授業を並べ、追加・変更・削除できる。
struct CoursesScreen: View {
    let timetable: Timetable

    @Environment(TimetableStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var form: CourseFormTarget?
    @State private var errorMessage: String?

    /// 並べ替えた授業と、元の配列での位置。
    private func courses(on weekday: Int) -> [(index: Int, course: Course)] {
        timetable.courses.enumerated()
            .filter { $0.element.weekday == weekday }
            .map { (index: $0.offset, course: $0.element) }
            .sorted { start(of: $0.course) < start(of: $1.course) }
    }

    private func start(of course: Course) -> ClockTime {
        switch course.slot {
        case .period(let number):
            timetable.periods.first { $0.number == number }?.start ?? ClockTime(hour: 0, minute: 0)!
        case .time(let start, _): start
        }
    }

    private var weekdays: [Int] {
        let used = Set(timetable.courses.map(\.weekday))
        return (0..<7).filter { $0 < 5 || used.contains($0) }
    }

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.accent)
                        .font(.subheadline)
                }
                ForEach(weekdays, id: \.self) { weekday in
                    Section("\(Schedule.weekdayNames[weekday])曜日") {
                        ForEach(courses(on: weekday), id: \.index) { item in
                            Button { form = .edit(item.index) } label: { CourseRow(course: item.course, timetable: timetable) }
                                .swipeActions {
                                    Button("削除", role: .destructive) { delete(at: item.index) }
                                }
                        }
                        Button { form = .add(weekday: weekday) } label: {
                            Label("授業を追加", systemImage: "plus")
                                .font(.subheadline)
                        }
                    }
                }
            }
            .navigationTitle("標準の時間割")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $form) { target in
                CourseForm(target: target, timetable: timetable)
            }
        }
        .tint(Theme.main)
    }

    private func delete(at index: Int) {
        do {
            try store.edit { timetable in
                timetable.courses.remove(at: index)
                timetable.removeOrphanedClassChanges()
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? TimetableError)?.description ?? "削除できませんでした"
        }
    }
}

enum CourseFormTarget: Identifiable {
    case add(weekday: Int)
    /// `Timetable.courses` での位置。
    case edit(Int)

    var id: String {
        switch self {
        case .add(let weekday): "add-\(weekday)"
        case .edit(let index): "edit-\(index)"
        }
    }
}

private struct CourseRow: View {
    let course: Course
    let timetable: Timetable

    private var slotText: String {
        switch course.slot {
        case .period(let number): "\(number)限"
        case .time(let start, let end): "\(start)–\(end)"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(slotText)
                .font(.subheadline.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.main)
                .frame(minWidth: 36, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(course.name).foregroundStyle(Color.primary)
                if let room = course.room {
                    Text(room).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            if let term = course.term {
                Text("第\(term)ターム")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.main)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.mainSoft, in: Capsule())
            }
        }
    }
}

/// 授業1件の入力画面。追加のときは複数のコマをまとめて選べる。
private struct CourseForm: View {
    let target: CourseFormTarget
    let timetable: Timetable

    @Environment(TimetableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var room = ""
    @State private var weekday = 0
    @State private var term: String?
    @State private var usesCustomTime = false
    @State private var periods: Set<Int> = []
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var errorMessage: String?

    private var isNew: Bool {
        if case .add = target { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("授業名", text: $name)
                    TextField("教室（任意）", text: $room)
                }
                Section {
                    Picker("曜日", selection: $weekday) {
                        ForEach(0..<7, id: \.self) { Text("\(Schedule.weekdayNames[$0])曜日").tag($0) }
                    }
                    if !timetable.terms.isEmpty {
                        Picker("開講期間", selection: $term) {
                            Text("学期全体").tag(String?.none)
                            ForEach(timetable.terms.keys.sorted(), id: \.self) { Text("第\($0)ターム").tag(String?.some($0)) }
                        }
                    }
                }
                Section {
                    if usesCustomTime {
                        DatePicker("開始", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $end, displayedComponents: .hourAndMinute)
                    } else {
                        ForEach(timetable.periods.sorted { $0.start < $1.start }, id: \.number) { period in
                            Button { toggle(period.number) } label: {
                                HStack {
                                    Text("\(period.number)限").foregroundStyle(Color.primary)
                                    Text("\(period.start)–\(period.end)").foregroundStyle(.secondary)
                                    Spacer()
                                    if periods.contains(period.number) {
                                        Image(systemName: "checkmark").fontWeight(.semibold)
                                    }
                                }
                            }
                        }
                    }
                    Toggle("時刻を直接指定する", isOn: $usesCustomTime)
                } header: {
                    Text("コマ")
                } footer: {
                    if isNew, !usesCustomTime { Text("2コマ続きの授業は、両方のコマを選ぶとまとめて追加できます。") }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.subheadline)
                    }
                }
                if case .edit(let index) = target {
                    Section {
                        Button("この授業を削除", role: .destructive) { save { $0.courses.remove(at: index) } }
                    }
                }
            }
            .navigationTitle(isNew ? "授業を追加" : "授業を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(isNew ? "追加" : "保存") { commit() } }
            }
            .onAppear(perform: fill)
        }
        .tint(Theme.main)
    }

    /// 追加のときは複数選択、編集のときは1つだけ選ぶ。
    private func toggle(_ number: Int) {
        if !isNew {
            periods = [number]
        } else if !periods.insert(number).inserted {
            periods.remove(number)
        }
    }

    private func fill() {
        switch target {
        case .add(let day):
            weekday = day
            start = Self.date(from: ClockTime(hour: 18, minute: 0)!)
            end = Self.date(from: ClockTime(hour: 19, minute: 30)!)
        case .edit(let index):
            let course = timetable.courses[index]
            name = course.name
            room = course.room ?? ""
            weekday = course.weekday
            term = course.term
            switch course.slot {
            case .period(let number):
                periods = [number]
                start = Self.date(from: ClockTime(hour: 18, minute: 0)!)
                end = Self.date(from: ClockTime(hour: 19, minute: 30)!)
            case .time(let from, let to):
                usesCustomTime = true
                start = Self.date(from: from)
                end = Self.date(from: to)
            }
        }
    }

    private func commit() {
        let name = name.trimmingCharacters(in: .whitespaces)
        let room = room.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "授業名を入力してください"
            return
        }
        let slots: [Slot]
        if usesCustomTime {
            slots = [.time(start: ClockTime.now(at: start), end: ClockTime.now(at: end))]
        } else {
            guard !periods.isEmpty else {
                errorMessage = "コマを選んでください"
                return
            }
            slots = periods.sorted().map(Slot.period)
        }
        let courses = slots.map {
            Course(name: name, weekday: weekday, slot: $0, room: room.isEmpty ? nil : room, term: term)
        }

        save { timetable in
            switch target {
            case .add: timetable.courses += courses
            case .edit(let index): timetable.courses[index] = courses[0]
            }
        }
    }

    /// 授業の一覧を書き換え、対象の授業が無くなった変更を片付けてから保存する。
    private func save(_ change: @escaping (inout Timetable) -> Void) {
        do {
            try store.edit { timetable in
                change(&timetable)
                timetable.removeOrphanedClassChanges()
            }
            dismiss()
        } catch let error as TimetableError {
            errorMessage = error.description
        } catch {
            errorMessage = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    private static func date(from time: ClockTime) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
    }
}
