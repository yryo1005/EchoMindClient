import Foundation

/// 録音ファイルの保存先とファイル名の規則をまとめた名前空間．
///
/// ファイル名に録音ファイルのID(サーバーへ送る`client_file_id`)と録音開始時刻(UTC)を含める．
/// アプリが録音中に強制終了されてデータベースに記録できなかったファイルも，ファイル名から
/// IDと開始時刻を復元して送信の対象にできるようにするためである．
nonisolated enum RecordingStorage {
    /// 録音ファイルの拡張子．
    ///
    /// ADTS形式のAAC(.aac)は短いフレームの連続で構成され，ファイルを閉じずにアプリが終了しても
    /// それまでの音声を読み出せる．m4aはファイルを閉じる際に目次(moov)を書き込むため，
    /// 強制終了されると録音中のファイル全体が読めなくなる．
    static let fileExtension = "aac"

    private static let fileNamePrefix = "rec_"

    /// 録音ファイルを保存するディレクトリ(Application Support/Recordings)．
    ///
    /// iCloudバックアップの対象外とする．ファイル保護は既定の
    /// `completeUntilFirstUserAuthentication`(初回のロック解除後は画面ロック中でも読み書きできる)である．
    static let directory: URL = {
        let base = URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return base
    }()

    /// 録音開始時刻をファイル名に埋め込む際の書式(UTC，例: 20261111T090000Z)．
    /// 区切りのない数字列を解析できるよう，年は4桁に固定する．
    private static let timestampFormat: Date.FormatString =
        "\(year: .padded(4))\(month: .twoDigits)\(day: .twoDigits)T\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased))\(minute: .twoDigits)\(second: .twoDigits)Z"

    private static let timestampStyle = Date.VerbatimFormatStyle(
        format: timestampFormat, locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    private static let timestampParser = Date.ParseStrategy(
        format: timestampFormat, locale: Locale(identifier: "en_US_POSIX"), timeZone: .gmt,
        calendar: Calendar(identifier: .gregorian)
    )

    /// 録音ファイルのファイル名を作る．
    /// - Parameters:
    ///   - clientFileId: 録音ファイルのID(UUID文字列)
    ///   - startedAt: 録音開始時刻
    /// - Returns: 「rec_20261111T090000Z_<ID>.aac」形式のファイル名
    static func fileName(clientFileId: String, startedAt: Date) -> String {
        "\(fileNamePrefix)\(startedAt.formatted(timestampStyle))_\(clientFileId).\(fileExtension)"
    }

    /// ファイル名から録音ファイルのIDと録音開始時刻を取り出す．
    /// - Parameter fileName: 録音ファイルのファイル名
    /// - Returns: IDと録音開始時刻．規則に合わないファイル名の場合はnil．
    static func parse(fileName: String) -> (clientFileId: String, startedAt: Date)? {
        guard fileName.hasPrefix(fileNamePrefix), fileName.hasSuffix(".\(fileExtension)") else { return nil }
        let body = fileName.dropFirst(fileNamePrefix.count).dropLast(fileExtension.count + 1)
        let parts = body.split(separator: "_", maxSplits: 1)
        guard parts.count == 2,
              let startedAt = try? Date(String(parts[0]), strategy: timestampParser)
        else { return nil }
        return (String(parts[1]), startedAt)
    }

    /// 保存されている録音ファイルの一覧を返す．
    /// - Returns: 録音ファイルのURL
    static func storedFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        return urls.filter { parse(fileName: $0.lastPathComponent) != nil }
    }

    /// ファイルのサイズを返す．
    /// - Parameter url: ファイルのURL
    /// - Returns: バイト数．取得できない場合は0．
    static func fileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    /// 録音ファイルを保存する領域の空き容量を返す．
    /// - Returns: 空き容量(バイト)．取得できない場合はnil．
    static func availableCapacity() -> Int64? {
        try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    /// ファイルの最終更新日時を返す．
    /// - Parameter url: ファイルのURL
    /// - Returns: 最終更新日時．取得できない場合はnil．
    static func modificationDate(of url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
