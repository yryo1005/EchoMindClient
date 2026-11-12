import AVFoundation
import Observation

/// 発言の音声クリップをダウンロードして再生するクラス．
///
/// `GET /api/audio/{utterance_id}`は認証ヘッダが必要なため，ストリーミングではなく
/// 音声データ全体を取得してから`AVAudioPlayer`で再生する．発言のクリップは数秒程度と短いため，
/// 取得したデータはこのインスタンスが存在する間メモリに保持し，同じ発言の再生時に再利用する．
@Observable
final class AudioClipPlayer: NSObject, AVAudioPlayerDelegate {
    /// 再生中(または読み込み中)の発言ID．
    private(set) var activeUtteranceId: String?
    /// 音声データを読み込み中かどうか．
    private(set) var isLoading = false
    /// 直近の再生で発生したエラーのメッセージ．
    var errorMessage: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var cache: [String: Data] = [:]

    /// 指定した発言が再生中であれば停止し，そうでなければ再生する．
    /// - Parameter utteranceId: 発言ID
    func toggle(utteranceId: String) {
        if activeUtteranceId == utteranceId {
            stop()
        } else {
            Task { await play(utteranceId: utteranceId) }
        }
    }

    /// 再生を停止する．
    func stop() {
        player?.stop()
        player = nil
        activeUtteranceId = nil
        isLoading = false
    }

    /// 発言の音声を取得して再生する．再生中の別の発言は停止する．
    /// - Parameter utteranceId: 発言ID
    private func play(utteranceId: String) async {
        stop()
        activeUtteranceId = utteranceId
        errorMessage = nil

        do {
            let data = try await loadAudio(utteranceId: utteranceId)
            // 読み込み中に別の発言が選ばれた，または停止された場合は再生しない
            guard activeUtteranceId == utteranceId else { return }

            // 録音中でも録音を止めずに再生できるよう，録音と共通の設定(.playAndRecord)を用いる
            try AudioSessionManager.activate()

            let player = try AVAudioPlayer(data: data)
            player.delegate = self
            player.play()
            self.player = player
        } catch {
            guard activeUtteranceId == utteranceId else { return }
            errorMessage = error.localizedDescription
            stop()
        }
    }

    /// 発言の音声データを取得する．取得済みであればメモリ上のデータを返す．
    /// - Parameter utteranceId: 発言ID
    /// - Returns: 音声ファイルのデータ
    /// - Throws: `APIError`
    private func loadAudio(utteranceId: String) async throws -> Data {
        if let data = cache[utteranceId] {
            return data
        }
        isLoading = true
        defer { isLoading = false }
        let data = try await BrowseAPI.audio(utteranceId: utteranceId)
        cache[utteranceId] = data
        return data
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if self.player === player {
                self.stop()
            }
        }
    }
}
