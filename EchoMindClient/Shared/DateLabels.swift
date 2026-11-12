import Foundation

/// 画面に表示する日時の文字列．いずれも端末のタイムゾーン(日本時間)で表示する．
///
/// ロケールに任せた書式では日本語環境で「11/07, 9:23」のように区切りが入るため，書式を明示する．
extension Date {
    /// 「11/7 9:23」形式の文字列．
    var monthDayTimeLabel: String {
        formatted(Self.verbatim("\(month: .defaultDigits)/\(day: .defaultDigits) \(hour: .twentyFourHourNoPadding):\(minute: .twoDigits)"))
    }

    /// 「11/7 9:23:05」形式の文字列．
    var monthDayTimeWithSecondsLabel: String {
        formatted(Self.verbatim("\(month: .defaultDigits)/\(day: .defaultDigits) \(hour: .twentyFourHourNoPadding):\(minute: .twoDigits):\(second: .twoDigits)"))
    }

    /// 「9:23:05」形式の文字列．
    var timeWithSecondsLabel: String {
        formatted(Self.verbatim("\(hour: .twentyFourHourNoPadding):\(minute: .twoDigits):\(second: .twoDigits)"))
    }

    /// 会話の期間を表す文字列を返す．
    /// - Parameters:
    ///   - start: 開始日時
    ///   - end: 終了日時
    /// - Returns: 「11/7(土) 9:00〜9:30」形式の文字列．日付をまたぐ場合は終了側にも日付を付ける．
    static func periodLabel(from start: Date, to end: Date) -> String {
        let startLabel = start.formatted(
            verbatim("\(month: .defaultDigits)/\(day: .defaultDigits)(\(weekday: .abbreviated)) \(hour: .twentyFourHourNoPadding):\(minute: .twoDigits)")
        )
        let endLabel = Calendar.current.isDate(start, inSameDayAs: end)
            ? end.formatted(verbatim("\(hour: .twentyFourHourNoPadding):\(minute: .twoDigits)"))
            : end.monthDayTimeLabel
        return "\(startLabel)〜\(endLabel)"
    }

    /// 端末のロケール・タイムゾーンで，指定した書式の文字列を作るスタイルを返す．
    /// - Parameter format: 書式
    /// - Returns: 日時の書式スタイル
    private static func verbatim(_ format: Date.FormatString) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: format, locale: .current, timeZone: .current, calendar: .current)
    }
}

extension Date.FormatStyle.Symbol.VerbatimHour {
    /// 24時間制，ゼロ埋めなしの時(例: 9)．
    fileprivate static var twentyFourHourNoPadding: Self {
        .defaultDigits(clock: .twentyFourHour, hourCycle: .zeroBased)
    }
}
