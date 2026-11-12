import BackgroundTasks
import Foundation
import Network
import Observation
import SwiftData
import UIKit
import os

/// 録音ファイルをサーバーへ送信し，サーバーでの処理が終わったファイルを端末から削除するクラス．
///
/// Wi-Fiに接続され，かつ充電中の場合に自動で送信する(それぞれの条件は設定で外せる)．`sendNow()`を呼ぶと，書き込み中の録音ファイルを
/// 区切ったうえで，条件に関わらず(モバイル通信でも)すべての録音ファイルを送信する．
///
/// 録音ファイルは録音開始時刻の古い順に1件ずつ扱い，`POST /api/upload`で送信した後，
/// `GET /api/upload/{id}/status`をポーリングして`safe_to_delete_client_copy`が`true`になった時点で削除する．
/// - サーバーでの処理が失敗した(`failed`)場合は，待ち時間を倍にしながら再送し，`maxFailures`回で自動での再送を止める．
/// - 送信から`processingTimeout`を超えても処理中の場合，またはアップロード記録が見つからない(404)場合は再送する．
/// - 通信の失敗(サーバーの停止等)は失敗の回数に数えず，`transportRetryDelay`後に再試行する．
/// 送信の結果と，Wi-Fi・充電の状態の変化は`EventLog`に記録する．
@Observable
final class UploadManager {
    static let shared = UploadManager()

    /// バックグラウンドでの送信に用いる`BGProcessingTask`の識別子(Info.plistの
    /// `BGTaskSchedulerPermittedIdentifiers`と一致させる)．
    static let backgroundTaskIdentifier = (Bundle.main.bundleIdentifier ?? "EchoMindClient") + ".upload"
    /// サーバーでの処理の失敗を何回まで再送するか．
    static let maxFailures = 5
    /// 処理状況を確認する間隔(秒)．
    static let pollInterval: TimeInterval = 30
    /// 送信からこの時間(秒)を超えても処理中の場合は再送する．
    static let processingTimeout: TimeInterval = 60 * 60
    /// 通信に失敗した場合に再試行するまでの時間(秒)．
    static let transportRetryDelay: TimeInterval = 5 * 60

    private static let logger = Logger(subsystem: "EchoMind", category: "UploadManager")
    private static let requiresWiFiKey = "uploadRequiresWiFi"
    private static let requiresChargingKey = "uploadRequiresCharging"
    private static let lastCompletedAtKey = "uploadLastCompletedAt"

    /// 自動で送信する条件にWi-Fi(または有線)での接続を含めるかどうか(既定はtrue)．
    /// falseの場合はモバイル通信でも自動で送信する．
    var requiresWiFi = UserDefaults.standard.object(forKey: requiresWiFiKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(requiresWiFi, forKey: Self.requiresWiFiKey)
            conditionsDidChange()
        }
    }
    /// 自動で送信する条件に充電中であることを含めるかどうか(既定はtrue)．
    var requiresCharging = UserDefaults.standard.object(forKey: requiresChargingKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(requiresCharging, forKey: Self.requiresChargingKey)
            conditionsDidChange()
        }
    }
    /// サーバーでの処理が最後に完了した(録音ファイルを削除した)日時．
    private(set) var lastCompletedAt = UserDefaults.standard.object(forKey: lastCompletedAtKey) as? Date {
        didSet { UserDefaults.standard.set(lastCompletedAt, forKey: Self.lastCompletedAtKey) }
    }

    /// Wi-Fi(または有線)でネットワークに接続しているかどうか．
    private(set) var isWiFiConnected = false
    /// 何らかの手段でネットワークに接続しているかどうか．
    private(set) var isNetworkAvailable = false
    /// 充電中(または満充電で給電中)かどうか．
    private(set) var isCharging = false
    /// 送信の処理を実行中かどうか．
    private(set) var isRunning = false
    /// 手動での送信を実行中かどうか．
    private(set) var isManualRun = false
    /// 送信中・処理状況を確認中の録音ファイルのID．
    private(set) var activeFileId: String?
    /// 直近の送信の処理の結果を表すメッセージ(エラー等)．
    private(set) var lastMessage: String?

    /// 自動で送信する条件(設定に応じて，Wi-Fiに接続，充電中)を満たしているかどうか．
    var canUploadAutomatically: Bool {
        isNetworkAvailable && (!requiresWiFi || isWiFiConnected) && (!requiresCharging || isCharging)
    }

    /// 自動で送信する条件の説明(例: 「Wi-Fiに接続し，かつ充電中」)．
    var automaticConditionDescription: String {
        switch (requiresWiFi, requiresCharging) {
        case (true, true): "Wi-Fiに接続し，かつ充電中"
        case (true, false): "Wi-Fiに接続中"
        case (false, true): "ネットワークに接続し，かつ充電中"
        case (false, false): "ネットワークに接続中"
        }
    }

    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var wakeRequested = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var backgroundTask: BGTask?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateBatteryState()
        observers.append(NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { UploadManager.shared.updateBatteryState() }
        })
        pathMonitor.pathUpdateHandler = Self.makePathUpdateHandler()
        pathMonitor.start(queue: DispatchQueue(label: "EchoMind.UploadManager.path"))
    }

    /// 録音ファイルが追加された際に呼ぶ．条件を満たしていれば送信を始める．
    func recordingsDidChange() {
        start()
    }

    /// 書き込み中の録音ファイルを区切り，条件に関わらずすべての録音ファイルを今すぐ送信する．
    ///
    /// 自動での再送を止めた録音ファイルや，再試行の待ち時間中の録音ファイルも対象とする．
    func sendNow() {
        EventLog.shared.record(.upload, "手動で送信を開始しました．")
        AudioRecorder.shared.finishCurrentSegment()
        let context = AppDataStore.container.mainContext
        for file in (try? context.fetch(FetchDescriptor<RecordingFile>())) ?? [] {
            if file.uploadState == .gaveUp {
                file.uploadState = .pending
                file.failureCount = 0
            }
            file.nextAttemptAt = nil
        }
        try? context.save()
        isManualRun = true
        lastMessage = nil
        wakeRequested = true
        start()
    }

    /// 端末内のすべての録音ファイルを送信せずに削除する．実行中の送信の処理も中止する．
    ///
    /// 未送信の録音を残したままログアウトし，別のアカウントに送信されることを防ぐために用いる．
    func discardAllRecordings() {
        runTask?.cancel()
        let context = AppDataStore.container.mainContext
        let files = (try? context.fetch(FetchDescriptor<RecordingFile>())) ?? []
        EventLog.shared.record(.upload, "ログアウトのため未送信の録音\(files.count)件を削除しました．")
        for file in files {
            try? FileManager.default.removeItem(at: file.url)
            context.delete(file)
        }
        try? context.save()
    }

    /// 送信の処理が実行中でなければ開始する．条件を満たさない場合はすぐに終了する．
    func start() {
        guard runTask == nil else {
            wakeRequested = true
            return
        }
        // タスクが実際に始まるまでの間も実行中として表示する(ボタンの二重押し等を防ぐため)
        isRunning = true
        runTask = Task {
            await run()
            runTask = nil
        }
    }

    /// バックグラウンドでの送信を予約する(Wi-Fiでなくてもネットワークに接続され，給電中の場合に実行される)．
    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = true
        Task {
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
            } catch {
                Self.logger.error("バックグラウンドでの送信を予約できませんでした: \(error.localizedDescription)")
            }
        }
    }

    /// `BGProcessingTask`を受け取り，送信の処理が終わるまで実行する．
    /// - Parameter task: システムが起動したバックグラウンドタスク
    func handleBackgroundTask(_ task: BGTask) {
        scheduleBackgroundTask()
        backgroundTask = task
        task.expirationHandler = {
            Task { @MainActor in
                UploadManager.shared.runTask?.cancel()
                UploadManager.shared.completeBackgroundTask(success: false)
            }
        }
        Task {
            start()
            await runTask?.value
            completeBackgroundTask(success: true)
        }
    }

    /// 実行中のバックグラウンドタスクに完了を伝える．
    /// - Parameter success: 処理を最後まで行えたかどうか
    private func completeBackgroundTask(success: Bool) {
        backgroundTask?.setTaskCompleted(success: success)
        backgroundTask = nil
    }

    /// 送信の処理の本体．送信できる録音ファイルがなくなるか，条件を満たさなくなるまで1件ずつ処理する．
    private func run() async {
        isRunning = true
        defer {
            isRunning = false
            isManualRun = false
            activeFileId = nil
        }
        while !Task.isCancelled {
            guard AuthSession.shared.isLoggedIn, AppConfig.serverURL != nil else { return }
            guard isManualRun ? isNetworkAvailable : canUploadAutomatically else {
                if isManualRun {
                    lastMessage = "ネットワークに接続されていないため送信できません．"
                    EventLog.shared.record(.upload, lastMessage ?? "")
                }
                return
            }
            guard let file = nextFile() else { return }
            if let nextAttemptAt = file.nextAttemptAt, nextAttemptAt > Date() {
                await sleep(until: nextAttemptAt)
                continue
            }
            activeFileId = file.clientFileId
            guard await process(clientFileId: file.clientFileId) else { return }
        }
    }

    /// 次に扱う録音ファイルを返す．自動での再送を止めた録音ファイルは除き，録音開始時刻の最も古いものとする．
    /// - Returns: 録音ファイル．送信するものがない場合はnil．
    private func nextFile() -> RecordingFile? {
        let gaveUp = RecordingFile.UploadState.gaveUp.rawValue
        var descriptor = FetchDescriptor<RecordingFile>(
            predicate: #Predicate { $0.uploadStateRawValue != gaveUp },
            sortBy: [SortDescriptor(\.startedAt)]
        )
        descriptor.fetchLimit = 1
        return try? AppDataStore.container.mainContext.fetch(descriptor).first
    }

    /// IDに対応する録音ファイルの記録を返す．送信中にユーザーが削除した場合はnilとなる．
    /// - Parameter clientFileId: 録音ファイルのID
    /// - Returns: 録音ファイルの記録
    private func file(withId clientFileId: String) -> RecordingFile? {
        let descriptor = FetchDescriptor<RecordingFile>(predicate: #Predicate { $0.clientFileId == clientFileId })
        return try? AppDataStore.container.mainContext.fetch(descriptor).first
    }

    /// 録音ファイルの状態に応じて，送信または処理状況の確認を1回行う．
    /// - Parameter clientFileId: 録音ファイルのID
    /// - Returns: 処理を続けてよい場合はtrue．ログインの期限切れ等で中断すべき場合はfalse．
    private func process(clientFileId: String) async -> Bool {
        guard let file = file(withId: clientFileId) else { return true }
        let result: Bool
        switch file.uploadState {
        case .pending:
            result = await upload(clientFileId: clientFileId)
        case .processing:
            result = await checkStatus(clientFileId: clientFileId)
        case .gaveUp:
            result = true
        }
        try? AppDataStore.container.mainContext.save()
        return result
    }

    /// 録音ファイルを`POST /api/upload`で送信する．
    /// - Parameter clientFileId: 録音ファイルのID
    /// - Returns: 処理を続けてよいかどうか
    private func upload(clientFileId: String) async -> Bool {
        guard let file = file(withId: clientFileId) else { return true }
        guard FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)) else {
            Self.logger.error("録音ファイルが見つからないため記録を削除します: \(file.fileName)")
            EventLog.shared.record(.upload, "\(Self.label(of: file))のファイルが見つからないため記録を削除しました．")
            remove(file, isProcessed: false)
            return true
        }
        let fields = [
            ("recorded_started_at", file.startedAt.formatted(.iso8601)),
            ("client_file_id", file.clientFileId),
        ]
        do {
            let response: UploadResponse = try await APIClient.shared.upload(
                "api/upload", fields: fields, fileField: "file", fileURL: file.url, mimeType: "audio/aac"
            )
            guard let file = self.file(withId: clientFileId) else { return true }
            if response.safeToDeleteClientCopy == true {
                EventLog.shared.record(.upload, "\(Self.label(of: file))は処理済みのため削除しました(\(response.processingStatus ?? response.status))．")
                remove(file, isProcessed: true)
                return true
            }
            EventLog.shared.record(
                .upload,
                "\(Self.label(of: file))を送信しました(\(response.status == "duplicate" ? "処理中の重複" : "受付"))．"
            )
            file.uploadState = .processing
            file.uploadRecordId = response.uploadRecordId
            file.uploadedAt = Date()
            file.lastError = nil
            file.nextAttemptAt = Date().addingTimeInterval(Self.pollInterval)
            return true
        } catch {
            return handle(error, clientFileId: clientFileId)
        }
    }

    /// 送信済みの録音ファイルの処理状況を`GET /api/upload/{id}/status`で確認する．
    /// - Parameter clientFileId: 録音ファイルのID
    /// - Returns: 処理を続けてよいかどうか
    private func checkStatus(clientFileId: String) async -> Bool {
        guard let file = file(withId: clientFileId) else { return true }
        guard let uploadRecordId = file.uploadRecordId else {
            markForResend(file)
            return true
        }
        do {
            let status: UploadStatusResponse = try await APIClient.shared.send(.get, "api/upload/\(uploadRecordId)/status")
            guard let file = self.file(withId: clientFileId) else { return true }
            if status.safeToDeleteClientCopy {
                let result = status.status == "completed" ? "会話として保存" : "会話なし(\(status.status))"
                EventLog.shared.record(.upload, "\(Self.label(of: file))のサーバーでの処理が完了したため削除しました(\(result))．")
                remove(file, isProcessed: true)
            } else if status.status == "failed" {
                registerFailure(file, message: "サーバーでの処理に失敗しました．")
            } else if let uploadedAt = file.uploadedAt, Date().timeIntervalSince(uploadedAt) > Self.processingTimeout {
                Self.logger.info("処理が終わらないため再送します: \(file.fileName)")
                EventLog.shared.record(.upload, "\(Self.label(of: file))の処理が終わらないため送り直します．")
                markForResend(file)
            } else {
                file.nextAttemptAt = Date().addingTimeInterval(Self.pollInterval)
            }
            return true
        } catch APIError.server(statusCode: 404, _) {
            // サーバーのデータベースが初期化された等でアップロード記録が失われたため，送り直す
            if let file = self.file(withId: clientFileId) {
                EventLog.shared.record(.upload, "\(Self.label(of: file))のアップロード記録が見つからないため送り直します．")
                markForResend(file)
            }
            return true
        } catch {
            return handle(error, clientFileId: clientFileId)
        }
    }

    /// 送信・処理状況の確認で発生したエラーを処理する．
    /// - Parameters:
    ///   - error: 発生したエラー
    ///   - clientFileId: 録音ファイルのID
    /// - Returns: 処理を続けてよいかどうか
    private func handle(_ error: Error, clientFileId: String) -> Bool {
        let message = error.localizedDescription
        Self.logger.error("録音ファイルの送信に失敗しました: \(message)")
        lastMessage = message
        guard let file = file(withId: clientFileId) else { return true }
        switch error {
        case APIError.unauthorized, APIError.serverURLNotConfigured:
            EventLog.shared.record(.upload, "送信を中止しました: \(message)")
            return false
        case APIError.transport:
            EventLog.shared.record(.upload, "\(Self.label(of: file))の通信に失敗しました: \(message)")
            // サーバーの停止や通信の切断は録音ファイルの問題ではないため，失敗の回数に数えない
            file.lastError = message
            file.nextAttemptAt = Date().addingTimeInterval(Self.transportRetryDelay)
            // 手動での送信は，その場で結果を知らせて終了する
            return !isManualRun
        default:
            registerFailure(file, message: message)
            return true
        }
    }

    /// 処理の失敗を記録する．上限の回数に達した場合は自動での再送を止める．
    ///
    /// 再送までの待ち時間は1分，2分，4分，8分と倍にする．
    /// - Parameters:
    ///   - file: 録音ファイルの記録
    ///   - message: 失敗の内容
    private func registerFailure(_ file: RecordingFile, message: String) {
        file.failureCount += 1
        file.lastError = message
        file.uploadRecordId = nil
        EventLog.shared.record(
            .upload,
            "\(Self.label(of: file))の処理に失敗しました(\(file.failureCount)/\(Self.maxFailures)回): \(message)"
                + (file.failureCount >= Self.maxFailures ? " 自動での再送を中止します．" : "")
        )
        if file.failureCount >= Self.maxFailures {
            file.uploadState = .gaveUp
            file.nextAttemptAt = nil
        } else {
            file.uploadState = .pending
            file.nextAttemptAt = Date().addingTimeInterval(60 * pow(2, Double(file.failureCount - 1)))
        }
    }

    /// 録音ファイルを送り直す対象にする．
    /// - Parameter file: 録音ファイルの記録
    private func markForResend(_ file: RecordingFile) {
        file.uploadState = .pending
        file.uploadRecordId = nil
        file.nextAttemptAt = nil
    }

    /// サーバーでの処理が終わった(またはファイルの実体が失われた)録音ファイルを端末から削除する．
    /// - Parameters:
    ///   - file: 録音ファイルの記録
    ///   - isProcessed: サーバーでの処理が完了したかどうか(最後に送信が完了した日時の記録に用いる)
    private func remove(_ file: RecordingFile, isProcessed: Bool) {
        if isProcessed {
            lastCompletedAt = Date()
        }
        try? FileManager.default.removeItem(at: file.url)
        AppDataStore.container.mainContext.delete(file)
        try? AppDataStore.container.mainContext.save()
    }

    /// ログに記す録音ファイルの呼び名(例: 「11/12 9:00の録音」)．
    /// - Parameter file: 録音ファイルの記録
    /// - Returns: 録音開始時刻を含む呼び名
    private static func label(of file: RecordingFile) -> String {
        "\(file.startedAt.monthDayTimeWithSecondsLabel)の録音"
    }

    /// 指定した日時まで待つ．`start()`・`sendNow()`の呼び出しや条件の変化があれば途中で戻る．
    /// - Parameter date: 待つ期限
    private func sleep(until date: Date) async {
        wakeRequested = false
        while Date() < date, !wakeRequested, !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// 充電の状態を更新する．条件を満たした場合は送信を始める．
    private func updateBatteryState() {
        let state = UIDevice.current.batteryState
        let isCharging = state == .charging || state == .full
        if isCharging != self.isCharging {
            EventLog.shared.record(.upload, isCharging ? "充電を開始しました．" : "充電を終了しました．")
        }
        self.isCharging = isCharging
        conditionsDidChange()
    }

    /// ネットワークの接続状態を更新する．条件を満たした場合は送信を始める．
    /// - Parameters:
    ///   - isWiFi: Wi-Fi(または有線)で接続しているかどうか
    ///   - isAvailable: 何らかの手段で接続しているかどうか
    private func updateNetwork(isWiFi: Bool, isAvailable: Bool) {
        if isWiFi != isWiFiConnected || isAvailable != isNetworkAvailable {
            let state = isWiFi ? "Wi-Fiに接続" : (isAvailable ? "モバイル通信に接続" : "ネットワークに未接続")
            EventLog.shared.record(.upload, "ネットワークの状態が変わりました(\(state))．")
        }
        isWiFiConnected = isWiFi
        isNetworkAvailable = isAvailable
        conditionsDidChange()
    }

    /// 送信の条件が変化した際の処理．
    private func conditionsDidChange() {
        wakeRequested = true
        if canUploadAutomatically {
            start()
        }
    }

    /// ネットワークの状態の変化を受け取る処理を作る．
    ///
    /// `NWPathMonitor`は専用のキューから呼ぶため，MainActorに隔離されない文脈で作る．
    /// - Returns: ネットワークの状態の変化を受け取る処理
    nonisolated private static func makePathUpdateHandler() -> @Sendable (NWPath) -> Void {
        { path in
            let isAvailable = path.status == .satisfied
            let isWiFi = isAvailable && (path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet))
            Task { @MainActor in
                UploadManager.shared.updateNetwork(isWiFi: isWiFi, isAvailable: isAvailable)
            }
        }
    }
}
