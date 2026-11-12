import BackgroundTasks
import SwiftData
import SwiftUI

/// EchoMindクライアントのエントリポイント．
///
/// 起動時には，強制終了などで記録されずに残った録音ファイルを記録してから，録音が有効であれば再開する．
/// アプリが前面に戻った時にも，中断されたままの録音を再開する．
/// 録音ファイルの送信は起動時・前面に戻った時に開始し，バックグラウンドに移る際には
/// バックグラウンドでの送信を予約する．
@main struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // バックグラウンドタスクの登録は，起動の処理が終わる前に行う必要がある
        BGTaskScheduler.shared.register(forTaskWithIdentifier: UploadManager.backgroundTaskIdentifier, using: .main) { task in
            MainActor.assumeIsolated { UploadManager.shared.handleBackgroundTask(task) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthSession.shared)
                .task {
                    EventLog.shared.prune()
                    EventLog.shared.record(.app, "アプリを起動しました．")
                    AudioRecorder.shared.registerUnrecordedFiles()
                    await AudioRecorder.shared.resumeIfNeeded()
                    UploadManager.shared.start()
                }
        }
        .modelContainer(AppDataStore.container)
        .onChange(of: scenePhase) {
            switch scenePhase {
            case .active:
                EventLog.shared.record(.app, "アプリが前面に表示されました．")
                Task { await AudioRecorder.shared.resumeIfNeeded() }
                UploadManager.shared.start()
            case .background:
                EventLog.shared.record(.app, "アプリがバックグラウンドに移りました．")
                UploadManager.shared.scheduleBackgroundTask()
            default:
                break
            }
        }
    }
}
