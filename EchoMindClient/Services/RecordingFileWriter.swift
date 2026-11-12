import AVFoundation
import os

/// マイクの音声をAAC(ADTS)に変換して録音ファイルに書き込むクラス．
///
/// `AVAudioEngine`のタップ(メインスレッド以外)から`write`が呼ばれ，録音の停止・中断時には
/// メインスレッドから`finishSegment`が呼ばれるため，内部の状態はロックで保護する．
/// 録音ファイルは最初の音声を受け取った時点で作成し，`segmentDuration`を超えると次のファイルに切り替える．
///
/// サーバーは「録音開始時刻 + ファイル先頭からの経過時間」で発言の時刻を求めるため，
/// 1つのファイルの途中に録音の空白があってはならない．録音が止まる場合は必ず`finishSegment`でファイルを区切る．
nonisolated final class RecordingFileWriter: @unchecked Sendable {
    /// 書き込みを終えた録音ファイルの情報．
    struct FinishedSegment: Sendable {
        let clientFileId: String
        let fileName: String
        let startedAt: Date
        let endedAt: Date
    }

    /// 録音ファイルの音声形式．サーバーの処理と同じ16kHzモノラルとし，1時間あたり約15MBに抑える．
    private static let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
    ]

    private static let logger = Logger(subsystem: "EchoMind", category: "RecordingFileWriter")

    private let segmentDuration: TimeInterval
    private let onSegmentStarted: @Sendable (Date) -> Void
    private let onSegmentFinished: @Sendable (FinishedSegment) -> Void
    private let lock = NSLock()

    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var segment: (clientFileId: String, fileName: String, startedAt: Date)?
    private var suspended = false

    /// - Parameters:
    ///   - segmentDuration: 1つの録音ファイルの最大の長さ(秒)
    ///   - onSegmentStarted: 新しい録音ファイルを作成した際に呼ばれる処理(引数は録音開始時刻)
    ///   - onSegmentFinished: 録音ファイルの書き込みを終えた際に呼ばれる処理
    init(
        segmentDuration: TimeInterval,
        onSegmentStarted: @escaping @Sendable (Date) -> Void,
        onSegmentFinished: @escaping @Sendable (FinishedSegment) -> Void
    ) {
        self.segmentDuration = segmentDuration
        self.onSegmentStarted = onSegmentStarted
        self.onSegmentFinished = onSegmentFinished
    }

    /// 書き込み中の録音ファイルのファイル名．書き込み中でなければnil．
    var currentFileName: String? {
        lock.withLock { segment?.fileName }
    }

    /// 書き込みを一時停止しているかどうか．
    ///
    /// 一時停止すると書き込み中の録音ファイルを閉じ，再開するまで受け取った音声を捨てる．
    /// 再開後に最初の音声を受け取った時点で新しい録音ファイルを作成する．
    var isSuspended: Bool {
        get { lock.withLock { suspended } }
        set {
            lock.withLock {
                suspended = newValue
                if newValue {
                    finishSegmentLocked(endedAt: Date())
                }
            }
        }
    }

    /// マイクの音声を録音ファイルに書き込む．必要に応じて録音ファイルを作成・切り替える．
    /// 一時停止中は何もしない．
    /// - Parameter buffer: マイクから受け取った音声(任意のサンプリング周波数・チャンネル数)
    func write(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard !suspended else { return }
            let now = Date()
            if let segment, now.timeIntervalSince(segment.startedAt) >= segmentDuration {
                finishSegmentLocked(endedAt: now)
            }
            do {
                let file = try self.file ?? startSegmentLocked(startedAt: now)
                guard let converted = convertLocked(buffer, to: file.processingFormat) else { return }
                try file.write(from: converted)
            } catch {
                Self.logger.error("録音ファイルへの書き込みに失敗しました: \(error.localizedDescription)")
            }
        }
    }

    /// 書き込み中の録音ファイルを閉じる．次に音声を受け取ると新しい録音ファイルを作成する．
    func finishSegment() {
        lock.withLock { finishSegmentLocked(endedAt: Date()) }
    }

    /// 新しい録音ファイルを作成する(ロックを保持した状態で呼ぶ)．
    /// - Parameter startedAt: 録音開始時刻
    /// - Returns: 作成した録音ファイル
    /// - Throws: ファイルの作成に失敗した場合のエラー
    private func startSegmentLocked(startedAt: Date) throws -> AVAudioFile {
        let clientFileId = UUID().uuidString
        let fileName = RecordingStorage.fileName(clientFileId: clientFileId, startedAt: startedAt)
        let file = try AVAudioFile(
            forWriting: RecordingStorage.directory.appending(path: fileName),
            settings: Self.outputSettings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        self.file = file
        segment = (clientFileId, fileName, startedAt)
        onSegmentStarted(startedAt)
        return file
    }

    /// 書き込み中の録音ファイルを閉じる(ロックを保持した状態で呼ぶ)．
    /// - Parameter endedAt: 録音終了時刻
    private func finishSegmentLocked(endedAt: Date) {
        guard let file, let segment else { return }
        file.close()
        self.file = nil
        self.segment = nil
        onSegmentFinished(
            FinishedSegment(
                clientFileId: segment.clientFileId, fileName: segment.fileName,
                startedAt: segment.startedAt, endedAt: endedAt
            )
        )
    }

    /// マイクの音声を録音ファイルの形式(16kHzモノラル)に変換する(ロックを保持した状態で呼ぶ)．
    ///
    /// 入力の形式は入出力の経路(内蔵マイク，有線ヘッドセット等)によって変わるため，
    /// 形式が変わった場合は変換器を作り直す．
    /// - Parameters:
    ///   - buffer: マイクから受け取った音声
    ///   - format: 変換後の形式
    /// - Returns: 変換した音声．変換に失敗した場合はnil．
    private func convertLocked(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if converter?.inputFormat != buffer.format || converter?.outputFormat != format {
            converter = AVAudioConverter(from: buffer.format, to: format)
        }
        guard let converter else { return nil }

        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1_024
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var hasProvidedInput = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if hasProvidedInput {
                inputStatus.pointee = .noDataNow
                return nil
            }
            hasProvidedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, output.frameLength > 0 else {
            if let conversionError {
                Self.logger.error("音声の変換に失敗しました: \(conversionError.localizedDescription)")
            }
            return nil
        }
        return output
    }
}
