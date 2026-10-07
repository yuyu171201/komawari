import KomawariCore
import SwiftUI

/// 週単位の時間割（曜日 × コマ番号のグリッド）。
struct WeekScreen: View {
    @Environment(TimetableStore.self) private var store
    @State private var monday = WeekScreen.initialDate().monday

    @State private var editing: EditTarget?
    /// この週の変更（休講・教室変更など）を登録するモード。オンの間だけタップで登録画面が開く。
    @State private var isEditing = false
    @State private var showsCourses = false

    /// 起動引数 `-date YYYY-MM-DD` があればその週から開く（動作確認用）。
    private static func initialDate() -> CalendarDate {
        UserDefaults.standard.string(forKey: "date").flatMap(CalendarDate.init) ?? .today()
    }

    var body: some View {
        // 今日・現在のコマのハイライトを1分ごとに更新する
        TimelineView(.everyMinute) { timeline in
            let today = CalendarDate.today(at: timeline.date)
            content(today: today, now: ClockTime.now(at: timeline.date))
        }
        .background(Theme.background.ignoresSafeArea())
        .foregroundStyle(Theme.text)
    }

    @ViewBuilder
    private func content(today: CalendarDate, now: ClockTime) -> some View {
        if let schedule = store.schedule {
            let days = schedule.week(containing: monday)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header(days: days, today: today)
                    if isEditing {
                        EditingBar { withAnimation(.snappy) { isEditing = false } }
                    } else {
                        SummaryBox(
                            text: summaryText(days: days, today: today),
                            changed: !Schedule.summary(of: days).isEmpty)
                    }
                    WeekGrid(
                        days: days, periods: schedule.timetable.periods,
                        today: today, now: now, isEditing: isEditing
                    ) {
                        editing = $0
                    }
                    footer
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }
            // 画面に収まっているときは縦に動かさない（収まらない端末・文字サイズでだけスクロールする）
            .scrollBounceBehavior(.basedOnSize)
            .gesture(weekSwipe)
            .fullScreenCover(isPresented: $showsCourses) {
                CoursesScreen(timetable: schedule.timetable)
            }
            .sheet(item: $editing) { target in
                EditSheet(target: target, timetable: schedule.timetable)
                    .presentationDetents([.medium, .large])
            }
        } else {
            ContentUnavailableView(
                "時間割を表示できません",
                systemImage: "exclamationmark.triangle",
                description: Text(store.errorMessage ?? ""))
        }
    }

    private func header(days: [DayPlan], today: CalendarDate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rangeTitle(days))
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.horizontal, 4)
                // マーカーを引いたような見出し
                .background(alignment: .bottom) { Theme.mainPale.frame(height: 10) }
            HStack(spacing: 8) {
                Menu {
                    Button("この週の変更を登録", systemImage: "calendar.badge.exclamationmark") {
                        withAnimation(.snappy) { isEditing = true }
                    }
                    Button("標準の時間割を編集", systemImage: "tablecells") { showsCourses = true }
                } label: {
                    Label("編集", systemImage: "pencil")
                }
                Spacer(minLength: 4)
                Button { move(weeks: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("前週")
                Button("今週") { withAnimation(.snappy) { monday = today.monday } }
                Button { move(weeks: 1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("翌週")
            }
            .buttonStyle(RaisedButtonStyle())
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ForEach([Status.swapped, .extra, .roomChanged, .off], id: \.self) { status in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.card(status).fill)
                        .overlay(alignment: .leading) { Theme.card(status).bar.frame(width: 4) }
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                        .frame(width: 14, height: 14)
                    Text(Theme.badge(status) ?? "")
                }
            }
            Spacer()
            if store.isSample { Text("サンプル表示中") }
        }
        .font(.caption)
        .foregroundStyle(Theme.muted)
    }

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let (dx, dy) = (value.translation.width, value.translation.height)
                guard abs(dx) > 60, abs(dx) > abs(dy) * 2 else { return }
                move(weeks: dx < 0 ? 1 : -1)
            }
    }

    private func move(weeks: Int) {
        withAnimation(.snappy) { monday = monday.adding(days: 7 * weeks) }
    }

    private func rangeTitle(_ days: [DayPlan]) -> String {
        guard let first = days.first?.date, let last = days.last?.date else { return "" }
        let year = last.year == first.year ? "" : "\(last.year)年"
        let month = !year.isEmpty || last.month != first.month ? "\(last.month)月" : ""
        return "\(first.year)年\(first.month)月\(first.day)日 〜 \(year)\(month)\(last.day)日"
    }

    private func summaryText(days: [DayPlan], today: CalendarDate) -> String {
        let weeks = (monday.ordinal - today.monday.ordinal) / 7
        let prefix = [0: "今週は", 1: "来週は", -1: "先週は"][weeks] ?? "この週は"
        let items = Schedule.summary(of: days)
        return prefix + (items.isEmpty ? "通常どおり" : items.joined(separator: "、"))
    }
}

/// 左に色帯のあるボックス。変更がある週はオレンジになる。
private struct SummaryBox: View {
    let text: String
    let changed: Bool

    var body: some View {
        Text(text)
            .font(changed ? .subheadline.bold() : .subheadline)
            .foregroundStyle(changed ? Theme.text : Theme.muted)
            // 週によって行数が変わると下の時間割が上下にずれるので、常に2行分の高さを取る
            .lineLimit(2, reservesSpace: true)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 9)
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .background(changed ? Theme.warmSoft : Theme.mainSoft)
            .overlay(alignment: .leading) { (changed ? Theme.warm : Theme.main).frame(width: 6) }
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
    }
}

/// 変更の登録中に、サマリーの代わりに出す案内。高さはサマリーと同じにして時間割を動かさない。
private struct EditingBar: View {
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("変更を登録中\n授業・空きコマ・日付をタップ")
                .font(.subheadline.bold())
                .lineLimit(2, reservesSpace: true)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("完了", action: onDone)
                .font(.subheadline.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.accent, in: Capsule())
        }
        .padding(.vertical, 9)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .background(Theme.accentSoft)
        .overlay(alignment: .leading) { Theme.accent.frame(width: 6) }
        .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8))
    }
}

/// 押すと沈む立体ボタン。
private struct RaisedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let pressed = configuration.isPressed
        configuration.label
            .font(.subheadline.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minWidth: 38, minHeight: 34)
            .background(Theme.main, in: RoundedRectangle(cornerRadius: 6))
            .background(Theme.mainDeep, in: RoundedRectangle(cornerRadius: 6).offset(y: pressed ? 1 : 4))
            .offset(y: pressed ? 3 : 0)
            .padding(.bottom, 4)
            .animation(.easeOut(duration: 0.08), value: pressed)
    }
}

/// グリッド内の授業カードと日付見出し用。押している間だけ少し沈む。
private struct PressableCellStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
    }
}

private struct WeekGrid: View {
    let days: [DayPlan]
    let periods: [Period]
    let today: CalendarDate
    let now: ClockTime
    let isEditing: Bool
    let onSelect: (EditTarget) -> Void

    private struct Row: Identifiable {
        var number: Int?
        var id: Int { number ?? -1 }
    }

    private var rows: [Row] {
        var rows = periods.sorted { $0.start < $1.start }.map { Row(number: $0.number) }
        // コマ番号を持たない授業（時刻を直接指定したもの）がある週だけ「他」の行を足す
        if days.contains(where: { $0.classes.contains { $0.period == nil } }) { rows.append(Row(number: nil)) }
        return rows
    }

    var body: some View {
        let showsToday = days.contains { $0.date == today }
        Grid(horizontalSpacing: 1, verticalSpacing: 1) {
            GridRow {
                Theme.mainSoft.frame(width: 34)
                ForEach(days, id: \.date) { day in
                    Button { onSelect(.day(day)) } label: { DayHeader(day: day, isToday: day.date == today) }
                        .accessibilityHint("この日の振替・休講を登録")
                }
            }
            ForEach(rows) { row in
                let period = periods.first { $0.number == row.number }
                let isNow = period.map { $0.start <= now && now < $0.end } ?? false
                GridRow {
                    PeriodLabel(text: row.number.map(String.init) ?? "他", isNow: isNow && showsToday)
                    ForEach(days, id: \.date) { day in
                        SlotCell(
                            day: day,
                            sessions: day.classes.filter { $0.period == row.number },
                            isToday: day.date == today,
                            isNow: isNow && day.date == today,
                            period: period,
                            isEditing: isEditing,
                            onSelect: onSelect)
                    }
                }
            }
        }
        .buttonStyle(PressableCellStyle())
        // ふだんはタップしても何も起きない。登録モードのときだけ登録画面を開く
        .allowsHitTesting(isEditing)
        .background(Theme.line)
        .overlay(alignment: .top) { (isEditing ? Theme.accent : Theme.main).frame(height: 5) }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 3)
    }
}

private struct DayHeader: View {
    let day: DayPlan
    let isToday: Bool

    private var note: (text: String, fill: Color, ink: Color)? {
        if day.status == .swapped {
            return ("\(Schedule.weekdayNames[day.effectiveWeekday])曜授業", Theme.card(.swapped).bar, Theme.onLabel)
        }
        switch day.offReason {
        case .exception: return ("休講", Theme.card(.off).bar, Theme.onLabel)
        case .holiday: return (day.holiday ?? "祝日", Theme.card(.off).bar, Theme.onLabel)
        case .outOfTerm: return ("学期外", Theme.card(.off).bar, Theme.onLabel)
        case nil: return day.holiday.map { ("\($0)・授業あり", Theme.surface, Theme.accent) }
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            Text(Schedule.weekdayNames[day.date.weekday])
                .font(.caption.bold())
                .foregroundStyle(isToday ? Theme.accent : Theme.main)
            Text(day.date.day == 1 ? "\(day.date.month)/1" : "\(day.date.day)")
                .font(.body.bold())
                .monospacedDigit()
                .foregroundStyle(isToday ? .white : Theme.text)
                .padding(.horizontal, 5)
                .frame(minWidth: 30, minHeight: 30)
                .background(isToday ? Theme.accent : .clear, in: Capsule())
            // 祝日や振替のラベル。無い週でも同じ高さを空けておき、時間割が上下にずれないようにする
            ZStack {
                if let note {
                    Text(note.text)
                        .font(.system(size: 9, weight: .bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(note.ink)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(note.fill, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .frame(height: 24)
        }
        .padding(.top, 12)
        .padding(.bottom, 6)
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.mainSoft)
    }
}

private struct PeriodLabel: View {
    let text: String
    let isNow: Bool

    var body: some View {
        Text(text)
            .font(.subheadline.bold())
            .foregroundStyle(isNow ? .white : Theme.main)
            .frame(width: 26, height: 26)
            .background(isNow ? Theme.accent : .clear, in: Circle())
            .overlay { Circle().stroke(isNow ? Theme.accent : Theme.mainPale, lineWidth: 2) }
            .frame(width: 34)
            .frame(maxHeight: .infinity)
            .background(Theme.surface)
            .overlay(alignment: .leading) { if isNow { Theme.accent.frame(width: 3) } }
    }
}

private struct SlotCell: View {
    let day: DayPlan
    let sessions: [Session]
    let isToday: Bool
    let isNow: Bool
    let period: Period?
    let isEditing: Bool
    let onSelect: (EditTarget) -> Void

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(sessions.enumerated()), id: \.offset) { item in
                Button { onSelect(.session(day, item.element)) } label: { SessionCard(session: item.element) }
            }
            if isEditing, sessions.isEmpty, period != nil {
                Image(systemName: "plus")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.mainPale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(3)
        .frame(maxWidth: .infinity, minHeight: 78, maxHeight: .infinity, alignment: .top)
        .background(background)
        // 空いている部分をタップすると、そのコマに補講を追加する
        .contentShape(Rectangle())
        .onTapGesture { if let period { onSelect(.slot(day, period)) } }
        .accessibilityAction(named: "補講を追加") { if let period { onSelect(.slot(day, period)) } }
        .overlay { if isNow { Rectangle().strokeBorder(Theme.accent, lineWidth: 2) } }
    }

    private var background: Color {
        if day.status == .off { return Theme.offSurface }
        return isToday ? Theme.accentSoft.mix(with: Theme.surface, by: 0.6) : Theme.surface
    }
}

/// 左に色帯のある授業カード。
private struct SessionCard: View {
    let session: Session

    var body: some View {
        let colors = Theme.card(session.status)
        let isOff = session.status == .off
        VStack(alignment: .leading, spacing: 2) {
            Text(session.name)
                .font(.caption.weight(isOff ? .regular : .bold))
                .strikethrough(isOff)
            if session.period == nil {
                Text("\(session.start.description)–\(session.end.description)")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            if let room = session.room {
                Text(room)
                    .font(.caption2.weight(session.status == .roomChanged ? .bold : .regular))
                    .foregroundStyle(session.status == .roomChanged ? colors.bar : Theme.muted)
            }
            if session.status == .roomChanged, let original = session.originalRoom {
                Text("← \(original)")
                    .font(.caption2)
                    .strikethrough()
                    .foregroundStyle(Theme.muted)
            }
            if let makeup = session.makeupDate {
                Text("補講 \(makeup.month)/\(makeup.day)").font(.caption2.bold())
            } else if session.makeupPending {
                Text("補講未定").font(.caption2.bold())
            }
            if let badge = Theme.badge(session.status) {
                Spacer(minLength: 0)
                Text(badge)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.onLabel)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(colors.bar, in: Capsule())
            }
        }
        .foregroundStyle(isOff ? Theme.muted : Theme.text)
        .padding(.leading, 9)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(colors.fill)
        .overlay(alignment: .leading) { colors.bar.frame(width: 4) }
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 7, topTrailingRadius: 7))
        .shadow(color: .black.opacity(isOff ? 0 : 0.14), radius: 1.5, y: 1.5)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    WeekScreen()
        .environment(TimetableStore())
}
