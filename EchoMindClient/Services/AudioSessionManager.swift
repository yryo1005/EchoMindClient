import AVFoundation
import os

/// アプリ全体で共有する`AVAudioSession`の設定をまとめた名前空間．
///
/// 録音と発言音声の再生を両立させるため，カテゴリは常に`.playAndRecord`とする．
/// - `.mixWithOthers`: 他のアプリの音楽再生等と共存させ，それらによって録音が中断されないようにする．
/// - `.defaultToSpeaker`: 再生音を受話口ではなくスピーカーから出す．
/// - `.allowBluetoothA2DP`: AirPods等のBluetooth機器を出力先にできるようにする．指定しない場合，
///   録音中は出力がスピーカーに固定され，他のアプリの音声もイヤホンから流れなくなる．
/// 入力はiPhone本体のマイクに固定する．Bluetoothのヘッドセットのマイク(HFP)は使わない
/// (AirPods等が低音質の通話モードに切り替わるのを避けるため)．有線のヘッドセットを接続した場合も，
/// 録音の条件を揃えるため本体のマイクを優先する．
enum AudioSessionManager {
    private static let logger = Logger(subsystem: "EchoMind", category: "AudioSessionManager")

    /// 音声セッションを設定して有効にし，入力をiPhone本体のマイクに固定する．
    /// - Throws: 音声セッションの設定・有効化に失敗した場合のエラー
    static func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(
            .playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP]
        )
        try session.setActive(true)
        preferBuiltInMic()
    }

    /// 音声セッションを無効にし，他のアプリに音声の再開を促す．
    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 入力にiPhone本体のマイクを優先して使うよう設定する．
    ///
    /// 有線のヘッドセットの接続等で入力が切り替わった後にも呼び，本体のマイクに戻す．
    static func preferBuiltInMic() {
        let session = AVAudioSession.sharedInstance()
        guard let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        guard session.preferredInput?.uid != builtInMic.uid else { return }
        do {
            try session.setPreferredInput(builtInMic)
        } catch {
            logger.error("本体のマイクを入力に設定できませんでした: \(error.localizedDescription)")
        }
    }

    /// 現在の入力がiPhone本体のマイクかどうか．
    static var isBuiltInMicInUse: Bool {
        AVAudioSession.sharedInstance().currentRoute.inputs.contains { $0.portType == .builtInMic }
    }
}
