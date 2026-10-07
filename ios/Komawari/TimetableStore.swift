import Foundation
import KomawariCore
import Observation

/// 時間割データを読み込んで保持する。
///
/// 次の順で最初に見つかったものを使う:
/// 1. アプリの書類フォルダの `timetable.json`（アプリ内で編集・取り込みしたもの）
/// 2. アプリに同梱した `timetable.json`（自分の時間割。リポジトリには含めない）
/// 3. 同梱のサンプル `SampleTimetable.json`
@MainActor
@Observable
final class TimetableStore {
    private(set) var schedule: Schedule?
    private(set) var errorMessage: String?
    /// サンプルの時間割を表示しているか。
    private(set) var isSample = false

    init() {
        load()
    }

    private var documents: URL { URL.documentsDirectory.appending(path: "timetable.json") }

    /// 時間割を書き換えて保存する。書き換えた結果が不整合なら何も変えずにエラーを投げる。
    func edit(_ change: (inout Timetable) throws -> Void) throws {
        guard var timetable = schedule?.timetable else { return }
        try change(&timetable)
        let updated = try Schedule(timetable)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(timetable).write(to: documents, options: .atomic)
        schedule = updated
        isSample = false
    }

    func load() {
        let candidates: [(url: URL?, isSample: Bool)] = [
            (FileManager.default.fileExists(atPath: documents.path) ? documents : nil, false),
            (Bundle.main.url(forResource: "timetable", withExtension: "json"), false),
            (Bundle.main.url(forResource: "SampleTimetable", withExtension: "json"), true),
        ]
        guard let source = candidates.first(where: { $0.url != nil }), let url = source.url else {
            schedule = nil
            errorMessage = "時間割データが見つかりません"
            return
        }

        do {
            let timetable = try JSONDecoder().decode(Timetable.self, from: Data(contentsOf: url))
            schedule = try Schedule(timetable)
            isSample = source.isSample
            errorMessage = nil
        } catch let error as TimetableError {
            schedule = nil
            errorMessage = error.description
        } catch let DecodingError.dataCorrupted(context) {
            schedule = nil
            errorMessage = context.debugDescription
        } catch {
            schedule = nil
            errorMessage = "時間割データを読めません: \(error.localizedDescription)"
        }
    }
}

extension CalendarDate {
    /// 端末の時刻での今日。端末の暦が和暦などでも西暦で求める。
    static func today(at now: Date = .now) -> CalendarDate {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return CalendarDate(year: parts.year!, month: parts.month!, day: parts.day!)!
    }
}

extension CalendarDate {
    /// カレンダーUI（DatePicker）に渡す Date。端末の時刻でのその日の正午。
    var pickerDate: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }
}

extension ClockTime {
    /// 端末の時刻での現在時刻。
    static func now(at now: Date = .now) -> ClockTime {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        return ClockTime(hour: parts.hour!, minute: parts.minute!)!
    }
}
