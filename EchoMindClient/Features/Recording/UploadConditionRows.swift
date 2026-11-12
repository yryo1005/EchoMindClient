import SwiftUI

/// 自動送信の条件(Wi-Fiの接続，充電)の現在の状態を表示する行．
///
/// 設定で条件から外した項目には「条件外」と添える．録音タブと設定画面で共用する．
struct UploadConditionRows: View {
    private var uploader: UploadManager { .shared }

    var body: some View {
        LabeledContent("Wi-Fi", value: label(uploader.isWiFiConnected ? "接続中" : "未接続", isRequired: uploader.requiresWiFi))
        LabeledContent("充電", value: label(uploader.isCharging ? "充電中" : "未充電", isRequired: uploader.requiresCharging))
    }

    /// 状態の文字列に，条件から外しているかどうかを添える．
    /// - Parameters:
    ///   - state: 状態の文字列
    ///   - isRequired: 自動送信の条件に含めているかどうか
    /// - Returns: 表示する文字列
    private func label(_ state: String, isRequired: Bool) -> String {
        isRequired ? state : "\(state)(条件外)"
    }
}
