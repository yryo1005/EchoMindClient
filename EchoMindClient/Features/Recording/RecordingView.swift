import AVFoundation
import SwiftData
import SwiftUI

/// 録音タブの画面．録音の有効・無効の切り替え，録音の状態，送信の状況，端末内の録音ファイルの一覧を表示する．
///
/// 録音ファイルは`UploadManager`が自動で送信し，サーバーでの処理が終わると一覧から消える．
/// 「今すぐ送信」で，書き込み中の録音ファイルを区切って条件に関わらず送信できる．
/// 端末内での確認のために，録音ファイルの再生と手動での削除もできる．
struct RecordingView: View {
    @Query(sort: \RecordingFile.startedAt, order: .reverse) private var files: [RecordingFile]
    @Environment(\.modelContext) private var modelContext
    @State private var previewPlayer: AVAudioPlayer?
    @State private var previewingFileId: String?

    private var recorder: AudioRecorder { .shared }
    private var uploader: UploadManager { .shared }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("常時録音", isOn: Binding(
                        get: { recorder.isEnabled },
                        set: { enabled in Task { await recorder.setEnabled(enabled) } }
                    ))
                    RecordingStatusLabel()
                } footer: {
                    Text("録音は1時間ごとにファイルに区切って端末に保存します．電話などで中断された場合は自動で再開します．AirPods等のBluetooth機器やイヤホンの接続中も，iPhone本体のマイクで録音を続けます．")
                }

                uploadSection

                Section {
                    ForEach(files) { file in
                        RecordingFileRow(
                            file: file, isPlaying: previewingFileId == file.clientFileId,
                            isUploading: uploader.activeFileId == file.clientFileId
                        ) {
                            togglePreview(file)
                        }
                    }
                    .onDelete(perform: delete)
                } header: {
                    Text("保存した録音(\(files.count)件，\(totalSizeLabel))")
                } footer: {
                    Text("録音中のファイルは，区切られた時点(1時間ごと，停止・中断時，または「今すぐ送信」の時)で一覧に追加されます．")
                }
            }
            .navigationTitle("録音")
            .onDisappear(perform: stopPreview)
        }
    }

    /// 送信の条件と状況を表示し，今すぐ送信するボタンを置くセクション．
    private var uploadSection: some View {
        Section {
            UploadConditionRows()
            if uploader.isRunning {
                Label(uploader.isManualRun ? "送信中(手動)" : "送信中", systemImage: "arrow.up.circle")
                    .symbolEffect(.pulse)
            }
            if let message = uploader.lastMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button("今すぐ送信", systemImage: "paperplane") {
                uploader.sendNow()
            }
            .disabled(uploader.isManualRun)
        } header: {
            Text("送信")
        } footer: {
            Text("\(uploader.automaticConditionDescription)の場合に自動で送信します(条件は設定タブで変更できます)．「今すぐ送信」は録音中のファイルを区切り，条件に関わらず(モバイル通信でも)すべての録音を送信します．サーバーでの処理が終わった録音は端末から削除します．")
        }
    }

    /// 保存した録音ファイルの合計サイズの文字列．
    private var totalSizeLabel: String {
        files.reduce(Int64(0)) { $0 + $1.byteSize }.formatted(.byteCount(style: .file))
    }

    /// 録音ファイルを再生・停止する．
    /// - Parameter file: 録音ファイル
    private func togglePreview(_ file: RecordingFile) {
        if previewingFileId == file.clientFileId {
            stopPreview()
            return
        }
        stopPreview()
        do {
            try AudioSessionManager.activate()
            let player = try AVAudioPlayer(contentsOf: file.url)
            player.play()
            previewPlayer = player
            previewingFileId = file.clientFileId
        } catch {
            previewingFileId = nil
        }
    }

    /// 録音ファイルの再生を停止する．
    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingFileId = nil
    }

    /// 録音ファイルを端末から削除する．
    /// - Parameter offsets: 削除する行の位置
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let file = files[index]
            if previewingFileId == file.clientFileId {
                stopPreview()
            }
            try? FileManager.default.removeItem(at: file.url)
            modelContext.delete(file)
        }
        try? modelContext.save()
    }
}

/// 録音ファイルの1行．期間，長さ，サイズ，送信の状況，再生ボタンを表示する．
private struct RecordingFileRow: View {
    let file: RecordingFile
    let isPlaying: Bool
    let isUploading: Bool
    let onTogglePlayback: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(Date.periodLabel(from: file.startedAt, to: file.endedAt))
                    .font(.subheadline)
                Text("\(Duration.seconds(file.duration).formatted(.time(pattern: .hourMinuteSecond)))，\(file.byteSize.formatted(.byteCount(style: .file)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Text(uploadStatusLabel)
                    .font(.caption)
                    .foregroundStyle(file.uploadState == .gaveUp ? .red : .secondary)
            }
            Spacer()
            Button(
                isPlaying ? "停止" : "再生",
                systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill",
                action: onTogglePlayback
            )
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.borderless)
        }
    }

    /// 送信の状況の文字列．
    private var uploadStatusLabel: String {
        switch file.uploadState {
        case .pending where isUploading:
            "送信中…"
        case .pending where file.failureCount > 0:
            "再送待ち(失敗\(file.failureCount)/\(UploadManager.maxFailures)回)"
        case .pending where file.lastError != nil:
            "送信待ち(前回は通信に失敗)"
        case .pending:
            "送信待ち"
        case .processing:
            "サーバーで処理中"
        case .gaveUp:
            "送信を中止(\(UploadManager.maxFailures)回失敗)．「今すぐ送信」で再開します"
        }
    }
}

#Preview {
    RecordingView()
        .modelContainer(for: RecordingFile.self, inMemory: true)
}
