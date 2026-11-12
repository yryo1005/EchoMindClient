import SwiftUI

/// 常時録音の状態を表示するラベル．録音中は書き込み中の録音ファイルの経過時間を1秒ごとに更新する．
///
/// 録音タブと設定画面の状態の一覧で共用する．
struct RecordingStatusLabel: View {
    private var recorder: AudioRecorder { .shared }

    var body: some View {
        switch recorder.state {
        case .recording:
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Label {
                    Text("録音中 \(elapsedLabel(at: context.date))")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                }
            }
        case .pausedForExternalInput:
            Label("iPhone本体のマイクを使えないため一時停止しています．", systemImage: "mic.slash")
                .foregroundStyle(.orange)
        case .stopped:
            Label("停止中", systemImage: "stop.circle")
                .foregroundStyle(.secondary)
        case .interrupted(let reason):
            Label(reason, systemImage: "pause.circle")
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    /// 書き込み中の録音ファイルの経過時間を「12:34」形式で返す．
    /// - Parameter date: 現在時刻
    /// - Returns: 経過時間の文字列．録音ファイルがまだ作成されていない場合は空文字列．
    private func elapsedLabel(at date: Date) -> String {
        guard let startedAt = recorder.currentSegmentStartedAt else { return "" }
        return Duration.seconds(max(0, date.timeIntervalSince(startedAt))).formatted(.time(pattern: .minuteSecond))
    }
}
