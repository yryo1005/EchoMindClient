import UserNotifications

/// ローカル通知を送る名前空間．
///
/// バックグラウンドで録音が止まり，自動で再開できなかった場合にユーザーへ知らせるために用いる．
enum LocalNotifier {
    /// 録音停止の通知を識別するID(同じ通知が重ならないよう上書きする)．
    private static let recordingStoppedId = "recordingStopped"

    /// 通知の許可を求める(初回のみダイアログが表示される)．
    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// 録音が止まったことを通知する．
    /// - Parameter reason: 停止した理由
    static func notifyRecordingStopped(reason: String) {
        let content = UNMutableNotificationContent()
        content.title = "録音が停止しています"
        content.body = "\(reason)アプリを開くと録音を再開します．"
        content.sound = .default
        let request = UNNotificationRequest(identifier: recordingStoppedId, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// 録音停止の通知を取り消す(録音を再開できた場合)．
    static func clearRecordingStopped() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [recordingStoppedId])
    }
}
