import AVFoundation
import Observation
import SwiftData
import UIKit
import os

/// 常時録音を制御するクラス．
///
/// `AVAudioEngine`でマイクの音声を受け取り，`RecordingFileWriter`で1時間ごとの録音ファイルに保存する．
/// 録音を有効にした状態はアプリを再起動しても保持し，起動時・前面に戻った時に自動で再開する．
/// 電話やSiri等による中断，入出力の経路の変化，メディアサービスのリセットの後は録音を再開し，
/// 再開できない場合はローカル通知で知らせる．録音の開始・停止・中断と録音ファイルの区切りは`EventLog`に記録する．
/// Bluetooth機器やイヤホンの接続中もiPhone本体のマイクで録音を続ける．本体のマイクを使えない間
/// (外部のマイクに入力が切り替わった場合等)のみ録音ファイルへの書き込みを一時停止し，使えるようになると再開する．
@Observable
final class AudioRecorder {
    /// 録音の状態．
    enum State: Equatable {
        /// 停止中(録音が無効)．
        case stopped
        /// 録音中．
        case recording
        /// iPhone本体のマイクを使えないため書き込みを一時停止している．
        ///
        /// 本体のマイクに戻ったことをバックグラウンドでも検出して再開できるよう，`AVAudioEngine`は動かしたままにする
        /// (音声の入出力を止めるとアプリが一時停止され，経路の変化の通知を受け取れなくなるため)．
        case pausedForExternalInput
        /// 録音は有効だが，中断などで止まっている．
        case interrupted(String)
        /// 録音を開始できなかった．
        case failed(String)
    }

    static let shared = AudioRecorder()

    /// 1つの録音ファイルの最大の長さ(秒)．
    nonisolated static let segmentDuration: TimeInterval = 60 * 60

    private static let enabledKey = "recordingEnabled"
    private static let logger = Logger(subsystem: "EchoMind", category: "AudioRecorder")

    /// 録音の状態．
    private(set) var state = State.stopped
    /// 書き込み中の録音ファイルの録音開始時刻．
    private(set) var currentSegmentStartedAt: Date?
    /// 録音を有効にしているかどうか(アプリを再起動しても保持する)．
    private(set) var isEnabled = UserDefaults.standard.bool(forKey: enabledKey) {
        didSet { UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey) }
    }

    @ObservationIgnored private var engine = AVAudioEngine()
    @ObservationIgnored private lazy var writer = Self.makeWriter()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var messageTokens: [NotificationCenter.ObservationToken] = []

    private init() {
        observeNotifications()
    }

    /// 録音の有効・無効を切り替える．
    /// - Parameter enabled: 録音を有効にするかどうか
    func setEnabled(_ enabled: Bool) async {
        isEnabled = enabled
        EventLog.shared.record(.recording, enabled ? "常時録音を有効にしました．" : "常時録音を無効にしました．")
        if enabled {
            await LocalNotifier.requestAuthorization()
            await start()
        } else {
            stop()
            state = .stopped
        }
    }

    /// 録音が有効で止まっている場合に録音を再開する．アプリの起動時・前面に戻った時に呼ぶ．
    func resumeIfNeeded() async {
        guard isEnabled, !isEngineRunning else { return }
        await start()
    }

    /// 書き込み中の録音ファイルを区切る．録音は止めず，次の音声から新しい録音ファイルに書き込む．
    ///
    /// 区切った録音ファイルはデータベースに記録された時点で`UploadManager`に通知される．
    /// 録音ファイルを今すぐ送信する際に呼ぶ．
    func finishCurrentSegment() {
        writer.finishSegment()
    }

    /// 録音が有効なのに止まっている(中断から復帰できない，マイクが許可されていない等)かどうか．
    var needsAttention: Bool {
        switch state {
        case .interrupted, .failed: true
        case .stopped, .recording, .pausedForExternalInput: false
        }
    }

    /// `AVAudioEngine`を動かしている状態(録音中，または本体のマイクを使えないための一時停止中)かどうか．
    private var isEngineRunning: Bool {
        state == .recording || state == .pausedForExternalInput
    }

    /// データベースに記録されていない録音ファイルを記録する．
    ///
    /// 録音中にアプリが強制終了されると，書き込み中だった録音ファイルは記録されないまま残る．
    /// ADTS形式のため途中までの音声は読み出せるので，ファイル名から録音ファイルのIDと開始時刻を，
    /// ファイルの最終更新日時から終了時刻を復元して記録する．録音を開始する前に呼ぶ．
    func registerUnrecordedFiles() {
        let context = AppDataStore.container.mainContext
        let recorded = Set(((try? context.fetch(FetchDescriptor<RecordingFile>())) ?? []).map(\.fileName))
        let writingFileName = writer.currentFileName

        for url in RecordingStorage.storedFiles() {
            let fileName = url.lastPathComponent
            guard !recorded.contains(fileName), fileName != writingFileName,
                  let (clientFileId, startedAt) = RecordingStorage.parse(fileName: fileName)
            else { continue }
            let endedAt = RecordingStorage.modificationDate(of: url) ?? startedAt
            register(
                clientFileId: clientFileId, fileName: fileName, startedAt: startedAt, endedAt: endedAt, in: context,
                isRecovered: true
            )
        }
        try? context.save()
    }

    /// 録音を開始する．
    private func start() async {
        guard await AVAudioApplication.requestRecordPermission() else {
            isEnabled = false
            state = .failed("マイクへのアクセスが許可されていません．設定アプリでEchoMindClientのマイクを許可してください．")
            EventLog.shared.record(.recording, "マイクへのアクセスが許可されていないため録音を開始できませんでした．")
            return
        }
        do {
            try AudioSessionManager.activate()
            try startEngine()
            EventLog.shared.record(.recording, "録音を開始しました．")
            applyInputState()
            LocalNotifier.clearRecordingStopped()
        } catch {
            Self.logger.error("録音を開始できませんでした: \(error.localizedDescription)")
            EventLog.shared.record(.recording, "録音を開始できませんでした(\(error.localizedDescription))．")
            stop()
            state = .interrupted("録音を開始できませんでした(\(error.localizedDescription))．")
        }
    }

    /// 録音を停止し，書き込み中の録音ファイルを閉じる．
    private func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        writer.finishSegment()
        AudioSessionManager.deactivate()
    }

    /// マイクの入力にタップを設置して`AVAudioEngine`を開始する．
    /// - Throws: マイクを使用できない場合，または`AVAudioEngine`を開始できない場合のエラー
    private func startEngine() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.inputUnavailable
        }
        input.removeTap(onBus: 0)
        // タップの処理はオーディオ処理のスレッドから呼ばれる(@Sendableのため，MainActorには隔離されない)．
        // 受け取るバッファは読み取り専用のため，変換器に渡せるようコピーする
        let writer = writer
        try input.installAudioTap(onBus: 0, bufferSize: 4_096, format: format) { buffer, _ in
            writer.write(AVAudioPCMBuffer(copying: buffer))
        }
        engine.prepare()
        try engine.start()
    }

    /// 入力の経路に合わせて，書き込みの一時停止・再開を切り替える．`AVAudioEngine`の動作中に呼ぶ．
    ///
    /// 本体以外のマイクの音声は録音の条件(距離，音質)が異なるため書き込まない．
    private func applyInputState() {
        let isBuiltInMic = AudioSessionManager.isBuiltInMicInUse
        let newState = isBuiltInMic ? State.recording : .pausedForExternalInput
        if newState == .pausedForExternalInput, state != .pausedForExternalInput {
            EventLog.shared.record(.recording, "本体のマイクを使えないため録音を一時停止しました．")
        } else if newState == .recording, state == .pausedForExternalInput {
            EventLog.shared.record(.recording, "本体のマイクに戻ったため録音を再開しました．")
        }
        writer.isSuspended = !isBuiltInMic
        state = newState
    }

    /// 録音が意図せず止まった際の処理．録音ファイルを区切り，再開を試みる．
    /// - Parameter reason: 止まった理由(通知に表示する)
    private func handleUnexpectedStop(reason: String) async {
        guard isEnabled else { return }
        EventLog.shared.record(.recording, "録音が止まったため再開します: \(reason)")
        stop()
        state = .interrupted(reason)
        await start()
        if !isEngineRunning {
            EventLog.shared.record(.recording, "録音を再開できませんでした．")
            LocalNotifier.notifyRecordingStopped(reason: reason)
        }
    }

    /// 録音ファイルの書き込みを終えた際の処理．データベースに記録する．
    /// - Parameter segment: 書き込みを終えた録音ファイルの情報
    private func didFinishSegment(_ segment: RecordingFileWriter.FinishedSegment) {
        currentSegmentStartedAt = nil
        let context = AppDataStore.container.mainContext
        register(
            clientFileId: segment.clientFileId, fileName: segment.fileName,
            startedAt: segment.startedAt, endedAt: segment.endedAt, in: context
        )
        try? context.save()
        UploadManager.shared.recordingsDidChange()
    }

    /// 録音ファイルをデータベースに記録する．音声がほとんど含まれないファイルは削除する．
    /// - Parameters:
    ///   - clientFileId: 録音ファイルのID
    ///   - fileName: ファイル名
    ///   - startedAt: 録音開始時刻
    ///   - endedAt: 録音終了時刻
    ///   - context: SwiftDataのコンテキスト
    ///   - isRecovered: 強制終了などで記録されなかったファイルを起動時に記録する場合はtrue
    private func register(
        clientFileId: String, fileName: String, startedAt: Date, endedAt: Date, in context: ModelContext,
        isRecovered: Bool = false
    ) {
        let url = RecordingStorage.directory.appending(path: fileName)
        let byteSize = RecordingStorage.fileSize(of: url)
        // 1秒未満の録音は会話を含み得ないため保存しない(32kbpsで1秒は約4KB)
        guard endedAt.timeIntervalSince(startedAt) >= 1, byteSize > 4_000 else {
            try? FileManager.default.removeItem(at: url)
            EventLog.shared.record(.recording, "1秒未満の録音を破棄しました．")
            return
        }
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        EventLog.shared.record(
            .segment,
            isRecovered ? "記録されていなかった録音ファイルを復元しました．" : "録音ファイルを区切りました．",
            segment: LogEntry.Segment(
                clientFileId: clientFileId, startedAt: startedAt, endedAt: endedAt, byteSize: byteSize,
                batteryLevel: level >= 0 ? Int((level * 100).rounded()) : nil
            )
        )
        context.insert(
            RecordingFile(clientFileId: clientFileId, fileName: fileName, startedAt: startedAt, endedAt: endedAt, byteSize: byteSize)
        )
    }

    /// 中断・経路の変化・メディアサービスのリセットの通知を監視する．
    private func observeNotifications() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()

        messageTokens.append(center.addObserver(of: session, for: .didBecomeInactive) { message in
            // 自分で無効にした場合(.appDeactivated)は中断ではないため無視する
            if case .systemInterruption = message.deactivationResult {
                AudioRecorder.shared.handleInterruptionBegan()
            }
        })
        messageTokens.append(center.addObserver(of: session, for: .resumptionRecommendation) { _ in
            AudioRecorder.shared.handleInterruptionEnded()
        })
        observers.append(center.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // 経路の変化でエンジンが止まった場合のみ再開する(録音の開始時の設定変更による通知で
                // 再開処理を繰り返さないため)
                let recorder = AudioRecorder.shared
                guard recorder.isEngineRunning, !recorder.engine.isRunning else { return }
                Task { await recorder.handleUnexpectedStop(reason: "音声の入出力の経路が変わりました．") }
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated {
                // 機器の接続で入力が本体のマイク以外に切り替わった場合は本体のマイクに戻し，
                // 戻せない間は書き込みを一時停止する
                let recorder = AudioRecorder.shared
                guard recorder.isEngineRunning, recorder.engine.isRunning else { return }
                AudioSessionManager.preferBuiltInMic()
                recorder.applyInputState()
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: session, queue: .main) { _ in
            MainActor.assumeIsolated {
                AudioRecorder.shared.engine = AVAudioEngine()
                Task { await AudioRecorder.shared.handleUnexpectedStop(reason: "音声システムがリセットされました．") }
            }
        })
    }

    /// 音声セッションの中断(電話，Siri，アラーム等)が始まった際の処理．
    ///
    /// 録音ファイルを区切る(録音の空白をファイルの途中に含めないため)．
    private func handleInterruptionBegan() {
        guard isEnabled else { return }
        EventLog.shared.record(.recording, "電話などにより録音が中断されました．")
        stop()
        state = .interrupted("電話などにより録音が中断されました．")
    }

    /// 音声セッションの中断が終わった際の処理．
    ///
    /// 常時録音が目的のため，システムが再開を推奨するかどうかに関わらず録音の再開を試みる．
    private func handleInterruptionEnded() {
        guard isEnabled, !isEngineRunning else { return }
        EventLog.shared.record(.recording, "中断が終わりました．")
        Task { await handleUnexpectedStop(reason: "電話などにより録音が中断されました．") }
    }

    /// 録音ファイルの書き込み処理を作る．
    ///
    /// コールバックはメインスレッド以外(タップ)からも呼ばれるため，MainActorに隔離されない文脈で作る．
    /// - Returns: 録音ファイルの書き込み処理
    nonisolated private static func makeWriter() -> RecordingFileWriter {
        RecordingFileWriter(
            segmentDuration: segmentDuration,
            onSegmentStarted: { startedAt in
                Task { @MainActor in AudioRecorder.shared.currentSegmentStartedAt = startedAt }
            },
            onSegmentFinished: { segment in
                // メインスレッドから区切った場合(停止，手動での送信等)は，呼び出し元に戻る前に記録を終える
                // (手動での送信が，区切った録音ファイルを確実に送信の対象にできるようにするため)
                if Thread.isMainThread {
                    MainActor.assumeIsolated { AudioRecorder.shared.didFinishSegment(segment) }
                } else {
                    Task { @MainActor in AudioRecorder.shared.didFinishSegment(segment) }
                }
            }
        )
    }

}

/// 録音の開始で発生するエラー．
enum RecorderError: LocalizedError {
    case inputUnavailable

    var errorDescription: String? {
        switch self {
        case .inputUnavailable:
            "マイクを使用できません．"
        }
    }
}
