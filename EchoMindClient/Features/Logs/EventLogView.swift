import SwiftUI

/// 録音と送信のログを確認する画面．設定画面から開く．
///
/// 選んだ期間について，録音の集計(録音ファイル数，録音時間，空白，バッテリー残量の推移)と，
/// 録音の空白(その間に起きた出来事)を表示する．あわせて，ログの一覧を種類で絞り込んで表示し，
/// ログのファイルを書き出せる．
struct EventLogView: View {
    /// 集計する期間．
    private enum Period: TimeInterval, CaseIterable, Identifiable {
        case day = 86_400
        case threeDays = 259_200
        case week = 604_800

        var id: TimeInterval { rawValue }

        var title: String {
            switch self {
            case .day: "24時間"
            case .threeDays: "3日"
            case .week: "7日"
            }
        }
    }

    /// ログの一覧の絞り込み．
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "すべて"
        case recording = "録音"
        case segment = "ファイル"
        case upload = "送信"
        case app = "アプリ"

        var id: String { rawValue }

        var category: LogEntry.Category? {
            switch self {
            case .all: nil
            case .recording: .recording
            case .segment: .segment
            case .upload: .upload
            case .app: .app
            }
        }
    }

    /// ログの一覧に表示する最大の件数．
    private static let maxListedEntries = 500

    @State private var entries: [LogEntry] = []
    @State private var period = Period.day
    @State private var filter = Filter.all
    @State private var loadedAt = Date()

    var body: some View {
        let timeline = RecordingTimeline(entries: entries, from: loadedAt.addingTimeInterval(-period.rawValue), to: loadedAt)
        List {
            Section {
                Picker("期間", selection: $period) {
                    ForEach(Period.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                LabeledContent("録音ファイル", value: "\(timeline.segments.count)件，\(timeline.totalBytes.formatted(.byteCount(style: .file)))")
                LabeledContent("録音時間", value: Self.durationLabel(timeline.recordedDuration))
                LabeledContent("空白", value: "\(timeline.gaps.count)回，\(Self.durationLabel(timeline.gapDuration))")
                if let battery = timeline.batteryRange {
                    LabeledContent("バッテリー", value: "\(battery.first)% → \(battery.last)%")
                }
            } header: {
                Text("録音の集計")
            } footer: {
                Text("区切られた録音ファイルの記録から集計します．録音中のファイルは区切られるまで含まれません．空白は，前のファイルの終了から次のファイルの開始までが\(Int(RecordingTimeline.gapThreshold))秒を超えたものです．")
            }

            Section("録音の空白") {
                if timeline.gaps.isEmpty {
                    Text("空白はありません")
                        .foregroundStyle(.secondary)
                }
                ForEach(timeline.gaps.reversed()) { gap in
                    GapRow(gap: gap)
                }
            }

            Section {
                Picker("種類", selection: $filter) {
                    ForEach(Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                ForEach(listedEntries) { entry in
                    LogEntryRow(entry: entry)
                }
            } header: {
                Text("ログ(新しい順)")
            } footer: {
                Text("ログは\(Int(EventLog.retention / 86_400))日間保存します．最大\(Self.maxListedEntries)件を表示します．")
            }
        }
        .navigationTitle("ログ")
        .toolbar {
            ShareLink(item: EventLog.shared.fileURL) {
                Label("書き出す", systemImage: "square.and.arrow.up")
            }
        }
        .task { reload() }
        .refreshable { reload() }
    }

    /// 絞り込んだログ(新しい順，最大`maxListedEntries`件)．
    private var listedEntries: [LogEntry] {
        let filtered = filter.category.map { category in entries.filter { $0.category == category } } ?? entries
        return Array(filtered.reversed().prefix(Self.maxListedEntries))
    }

    /// ログを読み込み直す．
    private func reload() {
        entries = EventLog.shared.entries()
        loadedAt = Date()
    }

    /// 時間を「3時間12分」形式の文字列にする．
    /// - Parameter duration: 時間(秒)
    /// - Returns: 時間の文字列
    fileprivate static func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds < 60 {
            return "\(seconds)秒"
        }
        let hours = seconds / 3_600
        let minutes = seconds % 3_600 / 60
        return hours > 0 ? "\(hours)時間\(minutes)分" : "\(minutes)分\(seconds % 60)秒"
    }
}

/// 録音の空白の1行．期間，長さ，その間に起きた出来事を表示する．
private struct GapRow: View {
    let gap: RecordingTimeline.Gap

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(gap.start.monthDayTimeWithSecondsLabel)〜\(gap.end.timeWithSecondsLabel)")
                .font(.subheadline)
                .monospacedDigit()
            Text(EventLogView.durationLabel(gap.duration))
                .font(.caption.bold())
                .foregroundStyle(.orange)
            Text(gap.events.isEmpty ? "この間の出来事は記録されていません．" : gap.events.joined(separator: "\n"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// ログの1行．日時，種類のアイコン，説明を表示する．録音ファイルの区切りは録音した区間とサイズも表示する．
private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date.monthDayTimeWithSecondsLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(entry.message)
                    .font(.subheadline)
                if let segment = entry.segment {
                    Text(segmentDetail(segment))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    /// 種類ごとのアイコン．
    private var icon: String {
        switch entry.category {
        case .app: "app"
        case .recording: "mic"
        case .segment: "waveform"
        case .upload: "arrow.up.circle"
        }
    }

    /// 録音ファイルの区切りの詳細(区間，長さ，サイズ，バッテリー残量)．
    /// - Parameter segment: 録音ファイルの区切りの情報
    /// - Returns: 詳細の文字列
    private func segmentDetail(_ segment: LogEntry.Segment) -> String {
        let duration = EventLogView.durationLabel(segment.endedAt.timeIntervalSince(segment.startedAt))
        let battery = segment.batteryLevel.map { "，バッテリー\($0)%" } ?? ""
        return "\(segment.startedAt.timeWithSecondsLabel)〜\(segment.endedAt.timeWithSecondsLabel)(\(duration)，\(segment.byteSize.formatted(.byteCount(style: .file)))\(battery))"
    }
}

#Preview {
    NavigationStack {
        EventLogView()
    }
}
