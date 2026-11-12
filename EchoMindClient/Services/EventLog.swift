import Foundation
import os

/// 端末に残す出来事の記録(ログ)の1件．
nonisolated struct LogEntry: Codable, Identifiable, Sendable {
    /// 出来事の種類．
    enum Category: String, Codable, CaseIterable, Sendable {
        /// アプリの起動，前面・バックグラウンドの切り替え．
        case app
        /// 録音の開始・停止・中断・再開．
        case recording
        /// 録音ファイルの区切り(録音した区間)．
        case segment
        /// 録音ファイルの送信．
        case upload
    }

    /// 録音ファイルの区切りの記録に付ける情報．
    struct Segment: Codable, Sendable {
        let clientFileId: String
        let startedAt: Date
        let endedAt: Date
        let byteSize: Int64
        /// 区切った時点のバッテリー残量(%)．取得できない場合はnil．
        let batteryLevel: Int?
    }

    let id: UUID
    let date: Date
    let category: Category
    let message: String
    let segment: Segment?
}

/// 録音と送信の経過を端末のファイルに記録するクラス．
///
/// 録音ファイルは送信後に削除されるため，録音が途中で止まらなかったか，送信が正しく行われたかを
/// 後から確認できるよう，出来事をJSON Lines形式(1行に1件)で`Application Support/Logs/events.jsonl`に追記する．
/// ファイルはアプリの画面から確認・書き出しでき，`devicectl`でMacに取り出すこともできる．
/// `retention`より古い記録は起動時に削除する．どのスレッドからも呼べるよう，ファイルの操作はロックで保護する．
nonisolated final class EventLog: @unchecked Sendable {
    static let shared = EventLog()

    /// 記録を保持する期間(秒)．
    static let retention: TimeInterval = 14 * 24 * 60 * 60

    private static let logger = Logger(subsystem: "EchoMind", category: "EventLog")

    /// 記録を保存するファイル．
    let fileURL: URL

    private let lock = NSLock()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// - Parameter directory: 記録を保存するディレクトリ(既定はApplication Support/Logs)
    init(directory: URL = URL.applicationSupportDirectory.appending(path: "Logs", directoryHint: .isDirectory)) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appending(path: "events.jsonl")
    }

    /// 出来事を記録する．
    /// - Parameters:
    ///   - category: 出来事の種類
    ///   - message: 出来事の説明
    ///   - segment: 録音ファイルの区切りの場合はその情報
    ///   - date: 出来事の日時(既定は現在時刻)
    func record(_ category: LogEntry.Category, _ message: String, segment: LogEntry.Segment? = nil, date: Date = Date()) {
        let entry = LogEntry(id: UUID(), date: date, category: category, message: message, segment: segment)
        guard var line = try? encoder.encode(entry) else { return }
        line.append(0x0A)
        lock.withLock {
            do {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    defer { try? handle.close() }
                    try handle.seekToEnd()
                    try handle.write(contentsOf: line)
                } else {
                    try line.write(to: fileURL)
                }
            } catch {
                Self.logger.error("ログを書き込めませんでした: \(error.localizedDescription)")
            }
        }
    }

    /// 記録をすべて読み出す．
    /// - Returns: 記録(古い順)．読み出せない行は飛ばす．
    func entries() -> [LogEntry] {
        lock.withLock { readLocked() }
    }

    /// `retention`より古い記録を削除する．アプリの起動時に呼ぶ．
    /// - Parameter now: 現在時刻
    func prune(now: Date = Date()) {
        lock.withLock {
            let entries = readLocked()
            let kept = entries.filter { now.timeIntervalSince($0.date) <= Self.retention }
            guard kept.count < entries.count else { return }
            var data = Data()
            for entry in kept {
                guard let line = try? encoder.encode(entry) else { continue }
                data.append(line)
                data.append(0x0A)
            }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// ファイルから記録を読み出す(ロックを保持した状態で呼ぶ)．
    /// - Returns: 記録(古い順)
    private func readLocked() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return data.split(separator: 0x0A).compactMap { try? decoder.decode(LogEntry.self, from: Data($0)) }
    }
}
