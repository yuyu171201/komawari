import KomawariCore
import SwiftUI

/// 標準の時間割（毎週の授業）の編集画面。タームごとに曜日 × コマのグリッドで表示し、
/// 授業をタップするとその授業の全コマをまとめて編集できる。
struct CoursesScreen: View {
    let timetable: Timetable

    @Environment(\.dismiss) private var dismiss
    @State private var term: String
    @State private var form: GroupFormTarget?

    /// 「すべて」を表すタームの値。
    private static let allTerms = ""

    init(timetable: Timetable) {
        self.timetable = timetable
        // 今日を含むターム、なければ最初のタームから開く
        let today = CalendarDate.today()
        let names = timetable.terms.keys.sorted()
        let current = names.first { timetable.terms[$0]?.contains(today) == true }
        _term = State(initialValue: current ?? names.first ?? Self.allTerms)
    }

    private var periods: [Period] { timetable.periods.sorted { $0.start < $1.start } }

    /// 選んだタームに開講している授業（学期全体の授業を含む）。
    private var visible: [Course] {
        timetable.courses.filter { term == Self.allTerms || $0.term == nil || $0.term == term }
    }

    private var weekdays: [Int] {
        let used = Set(visible.map(\.weekday))
        return (0..<7).filter { $0 < 5 || used.contains($0) }
    }

    /// コマ番号を持たない授業（時刻を直接指定したもの）がある場合だけ「他」の行を出す。
    private var rows: [Int?] {
        let hasCustom = visible.contains { if case .time = $0.slot { true } else { false } }
        return periods.map { Optional($0.number) } + (hasCustom ? [nil] : [])
    }

    private func courses(weekday: Int, period: Int?) -> [Course] {
        visible.filter { course in
            guard course.weekday == weekday else { return false }
            switch course.slot {
            case .period(let number): return number == period
            case .time: return period == nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !timetable.terms.isEmpty {
                        Picker("ターム", selection: $term) {
                            ForEach(timetable.terms.keys.sorted(), id: \.self) { Text("第\($0)ターム").tag($0) }
                            Text("すべて").tag(Self.allTerms)
                        }
                        .pickerStyle(.segmented)
                    }
                    grid
                    Text("授業をタップすると、その授業の全コマをまとめて編集できます。空いているコマをタップすると授業を追加します。")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("標準の時間割")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完了") { dismiss() } }
            }
            .sheet(item: $form) { target in
                GroupForm(target: target, timetable: timetable)
            }
        }
        .tint(Theme.main)
    }

    private var grid: some View {
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Theme.mainSoft.frame(width: 34)
                ForEach(weekdays, id: \.self) { weekday in
                    Text(Schedule.weekdayNames[weekday])
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.main)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.mainSoft)
                }
            }
            ForEach(rows, id: \.self) { period in
                GridRow {
                    Text(period.map(String.init) ?? "他")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.main)
                        .frame(width: 26, height: 26)
                        .overlay { Circle().stroke(Theme.mainPale, lineWidth: 2) }
                        .frame(width: 34)
                        .frame(maxHeight: .infinity)
                        .background(Theme.surface)
                    ForEach(weekdays, id: \.self) { weekday in
                        cell(weekday: weekday, period: period)
                    }
                }
            }
        }
        .background(Theme.line)
        .overlay(alignment: .top) { Theme.main.frame(height: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
    }

    private func cell(weekday: Int, period: Int?) -> some View {
        let courses = courses(weekday: weekday, period: period)
        return VStack(spacing: 4) {
            ForEach(Array(courses.enumerated()), id: \.offset) { item in
                Button { form = .edit(group(of: item.element)) } label: {
                    CourseCard(course: item.element, showsTerm: term == Self.allTerms)
                }
                .buttonStyle(.plain)
            }
            if courses.isEmpty, period != nil {
                Image(systemName: "plus")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.mainPale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
        .contentShape(Rectangle())
        .onTapGesture {
            guard let period else { return }
            form = .add(CourseGroup(
                name: "", term: term == Self.allTerms ? nil : term,
                slots: [CourseSlot(weekday: weekday, slot: .period(period))]))
        }
        .accessibilityAction(named: "授業を追加") {
            guard let period else { return }
            form = .add(CourseGroup(
                name: "", term: term == Self.allTerms ? nil : term,
                slots: [CourseSlot(weekday: weekday, slot: .period(period))]))
        }
    }

    private func group(of course: Course) -> CourseGroup {
        timetable.courseGroups.first {
            $0.name == course.name && $0.room == course.room && $0.term == course.term
        } ?? CourseGroup(
            name: course.name, room: course.room, term: course.term,
            slots: [CourseSlot(weekday: course.weekday, slot: course.slot)])
    }
}

enum GroupFormTarget: Identifiable {
    /// 新しい授業。最初から選んでおくコマとタームを持つ。
    case add(CourseGroup)
    /// 既存の授業（同一の授業のまとまり）。
    case edit(CourseGroup)

    var id: String {
        switch self {
        case .add(let group): "add-\(group.slots)-\(group.term ?? "")"
        case .edit(let group): "edit-\(group.name)-\(group.room ?? "")-\(group.term ?? "")"
        }
    }
}

private struct CourseCard: View {
    let course: Course
    let showsTerm: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.name).font(.caption.bold())
            if case .time(let start, let end) = course.slot {
                Text("\(start)–\(end)").font(.caption2).foregroundStyle(Theme.muted)
            }
            if let room = course.room {
                Text(room).font(.caption2).foregroundStyle(Theme.muted)
            }
            // 通期の授業は、どのタームを見ていても区別できるようにする
            if course.term == nil {
                tag("通期")
            } else if showsTerm, let term = course.term {
                tag("第\(term)")
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.card(.normal).fill)
        .overlay(alignment: .leading) { Theme.card(.normal).bar.frame(width: 4) }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 7, topTrailingRadius: 7))
        .shadow(color: .black.opacity(0.14), radius: 1.5, y: 1.5)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(Theme.main)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.mainSoft, in: Capsule())
    }
}

/// 授業1つ（同一の授業のまとまり）の入力画面。
/// 名前・教室・開講期間は全コマで共通で、開かれる曜日とコマを表から選ぶ。
private struct GroupForm: View {
    let target: GroupFormTarget
    let timetable: Timetable

    @Environment(TimetableStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var room: String
    @State private var term: String?
    /// コマ番号で指定するコマ。
    @State private var cells: Set<Cell>
    /// 時刻を直接指定するコマ。
    @State private var customSlots: [CourseSlot]
    @State private var newWeekday: Int
    @State private var newStart = GroupForm.date(hour: 18, minute: 0)
    @State private var newEnd = GroupForm.date(hour: 19, minute: 30)
    @State private var errorMessage: String?

    // 表の選択状態を最初の描画から反映させるため、初期値は init で入れる
    init(target: GroupFormTarget, timetable: Timetable) {
        self.target = target
        self.timetable = timetable
        let group: CourseGroup
        switch target {
        case .add(let initial), .edit(let initial): group = initial
        }
        var cells = Set<Cell>()
        var customSlots: [CourseSlot] = []
        for slot in group.slots {
            switch slot.slot {
            case .period(let number): cells.insert(Cell(weekday: slot.weekday, period: number))
            case .time: customSlots.append(slot)
            }
        }
        _name = State(initialValue: group.name)
        _room = State(initialValue: group.room ?? "")
        _term = State(initialValue: group.term)
        _cells = State(initialValue: cells)
        _customSlots = State(initialValue: customSlots)
        _newWeekday = State(initialValue: group.slots.first?.weekday ?? 0)
    }

    private struct Cell: Hashable {
        var weekday: Int
        var period: Int
    }

    private var original: CourseGroup? {
        if case .edit(let group) = target { return group }
        return nil
    }

    private var periods: [Period] { timetable.periods.sorted { $0.start < $1.start } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("授業名", text: $name)
                    TextField("教室（任意）", text: $room)
                    if !timetable.terms.isEmpty {
                        Picker("開講期間", selection: $term) {
                            Text("学期全体（通期）").tag(String?.none)
                            ForEach(timetable.terms.keys.sorted(), id: \.self) { Text("第\($0)ターム").tag(String?.some($0)) }
                        }
                    }
                }
                Section {
                    slotMatrix
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text("曜日とコマ")
                } footer: {
                    Text("2コマ続きの授業や、別の曜日にもある授業は、すべてのコマを選んでください。")
                }
                Section("時刻を直接指定するコマ") {
                    ForEach(customSlots, id: \.self) { slot in
                        HStack {
                            if case .time(let start, let end) = slot.slot {
                                Text("\(Schedule.weekdayNames[slot.weekday])曜 \(start)–\(end)")
                            }
                            Spacer()
                            Button("削除", systemImage: "minus.circle.fill", role: .destructive) {
                                customSlots.removeAll { $0 == slot }
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                    }
                    DisclosureGroup("追加する") {
                        Picker("曜日", selection: $newWeekday) {
                            ForEach(0..<7, id: \.self) { Text("\(Schedule.weekdayNames[$0])曜日").tag($0) }
                        }
                        DatePicker("開始", selection: $newStart, displayedComponents: .hourAndMinute)
                        DatePicker("終了", selection: $newEnd, displayedComponents: .hourAndMinute)
                        Button("このコマを追加", action: addCustomSlot)
                    }
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.accent)
                            .font(.subheadline)
                    }
                }
                if let original {
                    Section {
                        Button("この授業を削除（全\(original.slots.count)コマ）", role: .destructive) {
                            save(nil)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                }
            }
            .navigationTitle(original == nil ? "授業を追加" : "授業を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(original == nil ? "追加" : "保存") { commit() } }
            }
        }
        .tint(Theme.main)
    }

    /// 曜日 × コマの表。タップで選択を切り替える。
    private var slotMatrix: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Color.clear.frame(width: 22, height: 1)
                ForEach(0..<6, id: \.self) { weekday in
                    Text(Schedule.weekdayNames[weekday])
                        .font(.caption.bold())
                        .foregroundStyle(Theme.main)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(periods, id: \.number) { period in
                GridRow {
                    Text("\(period.number)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.muted)
                        .frame(width: 22)
                    ForEach(0..<6, id: \.self) { weekday in
                        let cell = Cell(weekday: weekday, period: period.number)
                        let isOn = cells.contains(cell)
                        Button {
                            if !cells.insert(cell).inserted { cells.remove(cell) }
                        } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(isOn ? Theme.main : Theme.mainSoft)
                                .frame(height: 34)
                                .overlay {
                                    if isOn {
                                        Image(systemName: "checkmark")
                                            .font(.caption.bold())
                                            .foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(Schedule.weekdayNames[weekday])曜 \(period.number)コマ")
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func addCustomSlot() {
        let start = ClockTime.now(at: newStart)
        let end = ClockTime.now(at: newEnd)
        guard start < end else {
            errorMessage = "終了は開始より後の時刻にしてください"
            return
        }
        let slot = CourseSlot(weekday: newWeekday, slot: .time(start: start, end: end))
        if !customSlots.contains(slot) { customSlots.append(slot) }
        errorMessage = nil
    }

    private func commit() {
        let name = name.trimmingCharacters(in: .whitespaces)
        let room = room.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            errorMessage = "授業名を入力してください"
            return
        }
        let slots = cells
            .sorted { ($0.weekday, $0.period) < ($1.weekday, $1.period) }
            .map { CourseSlot(weekday: $0.weekday, slot: .period($0.period)) } + customSlots
        guard !slots.isEmpty else {
            errorMessage = "曜日とコマを1つ以上選んでください"
            return
        }
        save(CourseGroup(name: name, room: room.isEmpty ? nil : room, term: term, slots: slots))
    }

    private func save(_ group: CourseGroup?) {
        do {
            try store.edit { $0.replaceGroup(original, with: group) }
            dismiss()
        } catch let error as TimetableError {
            errorMessage = error.description
        } catch {
            errorMessage = "保存できませんでした: \(error.localizedDescription)"
        }
    }

    private static func date(hour: Int, minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}
