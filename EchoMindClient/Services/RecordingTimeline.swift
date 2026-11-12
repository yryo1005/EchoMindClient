import Foundation

/// ログの録音ファイルの区切りの記録から，指定した期間の録音の状況(合計時間，空白)を集計した結果．
///
/// 録音の空白は，連続する2つの録音ファイルの間で，前のファイルの終了から次のファイルの開始までが
/// `gapThreshold`を超えるものとする．空白の間に記録された出来事(中断，マイクの切り替え等)を原因の手がかりとして添える．
nonisolated struct RecordingTimeline {
    /// 録音の空白．
    struct Gap: Identifiable {
        let start: Date
        let end: Date
        /// 空白の間に記録された出来事の説明．
        let events: [String]

        var id: Date { start }
        var duration: TimeInterval { end.timeIntervalSince(start) }
    }

    /// 空白とみなす最小の間隔(秒)．
    static let gapThreshold: TimeInterval = 5

    /// 期間内の録音ファイル(録音開始時刻の古い順)．
    let segments: [LogEntry.Segment]
    /// 録音の空白(古い順)．
    let gaps: [Gap]

    /// 録音した時間の合計(秒)．
    var recordedDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.endedAt.timeIntervalSince($1.startedAt) }
    }

    /// 録音ファイルの合計サイズ(バイト)．
    var totalBytes: Int64 {
        segments.reduce(0) { $0 + $1.byteSize }
    }

    /// 空白の合計(秒)．
    var gapDuration: TimeInterval {
        gaps.reduce(0) { $0 + $1.duration }
    }

    /// 期間の最初と最後の録音ファイルのバッテリー残量(%)．
    var batteryRange: (first: Int, last: Int)? {
        let levels = segments.compactMap(\.batteryLevel)
        guard let first = levels.first, let last = levels.last else { return nil }
        return (first, last)
    }

    /// - Parameters:
    ///   - entries: ログの記録
    ///   - start: 集計する期間の開始(この時刻以降に終了した録音ファイルを対象とする)
    ///   - end: 集計する期間の終了
    init(entries: [LogEntry], from start: Date, to end: Date) {
        let segments = entries.compactMap(\.segment)
            .filter { $0.endedAt >= start && $0.startedAt <= end }
            .sorted { $0.startedAt < $1.startedAt }
        let events = entries.filter { $0.category != .segment }

        var gaps: [Gap] = []
        for (previous, next) in zip(segments, segments.dropFirst())
        where next.startedAt.timeIntervalSince(previous.endedAt) > Self.gapThreshold {
            // 区切りの直前・直後に記録された出来事も原因になり得るため，前後に少し幅を持たせる
            let messages = events
                .filter { $0.date >= previous.endedAt.addingTimeInterval(-2) && $0.date <= next.startedAt.addingTimeInterval(2) }
                .map(\.message)
            gaps.append(Gap(start: previous.endedAt, end: next.startedAt, events: messages))
        }
        self.segments = segments
        self.gaps = gaps
    }
}
