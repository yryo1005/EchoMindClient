import SwiftData
import SwiftUI

/// 設定画面．ログイン済みの場合は，状態の一覧(録音，未送信の録音，最後の送信，空き容量，ログの画面への移動)，常時録音の切り替え，
/// 自動送信の条件の設定，アカウントの表示とログアウトを表示する．あわせて，サーバーURLの入力と疎通確認，
/// アプリのバージョンを表示する．
///
/// ログイン画面からもシートとして表示するため，アカウントの欄はログイン済みの場合のみ表示する．
/// 端末に未送信の録音がある場合，または常時録音が有効な場合は，ログアウトの前に警告を表示する．
/// ログアウト後に別のアカウントでログインすると，前のアカウントの録音が新しいアカウントに送信されるためである．
struct SettingsView: View {
    /// 疎通確認の状態．
    private enum HealthState {
        case idle
        case checking
        case ok
        case failed(String)
    }

    @Environment(AuthSession.self) private var authSession
    @AppStorage(AppConfig.serverURLKey) private var serverURLText = ""
    @State private var healthState = HealthState.idle
    @State private var isConfirmingLogout = false
    @State private var isWarningUnsentRecordings = false
    @Query private var recordingFiles: [RecordingFile]

    private var recorder: AudioRecorder { .shared }
    private var uploader: UploadManager { .shared }

    var body: some View {
        NavigationStack {
            Form {
                if authSession.isLoggedIn {
                    statusSection
                    recordingSection
                    uploadSettingsSection
                    accountSection
                }

                Section {
                    TextField("https://echomind.example.com", text: $serverURLText)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: serverURLText) { healthState = .idle }
                } header: {
                    Text("サーバーURL")
                } footer: {
                    if !serverURLText.isEmpty && AppConfig.normalizedServerURL(from: serverURLText) == nil {
                        Text("http:// または https:// から始まるURLを入力してください．")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("接続を確認", action: startHealthCheck)
                        .disabled(AppConfig.normalizedServerURL(from: serverURLText) == nil || isChecking)
                    healthStatusRow
                }

                Section("アプリ") {
                    LabeledContent("バージョン", value: Self.appVersion)
                }
            }
            .navigationTitle("設定")
        }
    }

    /// 録音と送信の状態の一覧．
    private var statusSection: some View {
        Section("状態") {
            RecordingStatusLabel()
            LabeledContent("未送信の録音", value: unsentSummary)
            LabeledContent("最後の送信の完了", value: uploader.lastCompletedAt?.monthDayTimeLabel ?? "なし")
            LabeledContent("送信", value: uploadStatusLabel)
            LabeledContent("端末の空き容量", value: RecordingStorage.availableCapacity()?.formatted(.byteCount(style: .file)) ?? "不明")
            NavigationLink("録音と送信のログ") {
                EventLogView()
            }
        }
    }

    /// 常時録音の切り替え．
    private var recordingSection: some View {
        Section {
            Toggle("常時録音", isOn: Binding(
                get: { recorder.isEnabled },
                set: { enabled in Task { await recorder.setEnabled(enabled) } }
            ))
        } header: {
            Text("録音")
        } footer: {
            Text("録音は1時間ごとにファイルに区切って端末に保存し，送信してサーバーでの処理が終わると端末から削除します．")
        }
    }

    /// 自動送信の条件の設定．
    private var uploadSettingsSection: some View {
        @Bindable var uploader = uploader
        return Section {
            Toggle("Wi-Fi接続時のみ", isOn: $uploader.requiresWiFi)
            Toggle("充電中のみ", isOn: $uploader.requiresCharging)
            UploadConditionRows()
        } header: {
            Text("自動送信の条件")
        } footer: {
            Text("現在の条件: \(uploader.automaticConditionDescription)の場合に自動で送信します．「Wi-Fi接続時のみ」を外すとモバイル通信でも送信します(1時間の録音は約15MB)．")
        }
    }

    /// 未送信の録音の件数と合計サイズの文字列．
    private var unsentSummary: String {
        guard !recordingFiles.isEmpty else { return "なし" }
        let size = recordingFiles.reduce(Int64(0)) { $0 + $1.byteSize }.formatted(.byteCount(style: .file))
        let gaveUp = recordingFiles.count { $0.uploadState == .gaveUp }
        return "\(recordingFiles.count)件，\(size)" + (gaveUp > 0 ? "(送信を中止\(gaveUp)件)" : "")
    }

    /// 送信の状況の文字列．
    private var uploadStatusLabel: String {
        if uploader.isRunning {
            return uploader.isManualRun ? "送信中(手動)" : "送信中"
        }
        if recordingFiles.isEmpty {
            return "送信するものはありません"
        }
        return uploader.canUploadAutomatically ? "待機中" : "条件を満たすまで待機"
    }

    /// アプリのバージョン(例: 「1.0 (1)」)．
    private static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }

    /// ログイン中のアカウントとログアウトボタンを表示する欄．
    private var accountSection: some View {
        Section("アカウント") {
            LabeledContent("メールアドレス", value: authSession.currentUser?.email ?? "取得中…")
            Button("ログアウト", role: .destructive) {
                if hasUnsentRecordings {
                    isWarningUnsentRecordings = true
                } else {
                    isConfirmingLogout = true
                }
            }
            .confirmationDialog("ログアウトしますか？", isPresented: $isConfirmingLogout, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) { authSession.logout() }
            }
            .alert("未送信の録音があります", isPresented: $isWarningUnsentRecordings) {
                Button("録音を停止してすべて送信") { stopRecordingAndSendAll() }
                Button("録音を削除してログアウト", role: .destructive) { discardRecordingsAndLogout() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text(unsentRecordingsMessage)
            }
        }
    }

    /// ログアウトの前に送信すべき録音(未送信の録音ファイル，または録音中の内容)があるかどうか．
    private var hasUnsentRecordings: Bool {
        !recordingFiles.isEmpty || recorder.isEnabled
    }

    /// 未送信の録音の警告に表示する文．
    private var unsentRecordingsMessage: String {
        var lines = ["アカウント間で録音が混ざらないよう，ログアウトの前に録音を停止して，すべての録音を送信してください．"]
        if !recordingFiles.isEmpty {
            lines.append("端末の未送信の録音: \(recordingFiles.count)件")
        }
        if recorder.isEnabled {
            lines.append("常時録音が有効です(録音中の内容も送信の対象になります)．")
        }
        lines.append("送信が終わり，録音タブの一覧が空になってからログアウトしてください．")
        return lines.joined(separator: "\n")
    }

    /// 常時録音を停止し，録音中の内容を含むすべての録音を送信する．
    private func stopRecordingAndSendAll() {
        Task {
            await recorder.setEnabled(false)
            UploadManager.shared.sendNow()
        }
    }

    /// 常時録音を停止し，未送信の録音をすべて削除してからログアウトする．
    private func discardRecordingsAndLogout() {
        Task {
            await recorder.setEnabled(false)
            UploadManager.shared.discardAllRecordings()
            authSession.logout()
        }
    }

    /// 疎通確認を実行中かどうか．
    private var isChecking: Bool {
        if case .checking = healthState { return true }
        return false
    }

    /// 疎通確認の結果を表示する行．
    @ViewBuilder
    private var healthStatusRow: some View {
        switch healthState {
        case .idle:
            EmptyView()
        case .checking:
            ProgressView()
        case .ok:
            Label("接続できました", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    /// 入力中のサーバーURLに対して疎通確認を開始する．
    private func startHealthCheck() {
        guard let url = AppConfig.normalizedServerURL(from: serverURLText) else { return }
        healthState = .checking
        Task {
            do {
                try await ServerHealth.check(baseURL: url)
                healthState = .ok
            } catch {
                healthState = .failed(error.localizedDescription)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environment(AuthSession())
        .modelContainer(for: RecordingFile.self, inMemory: true)
}
