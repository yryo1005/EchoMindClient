import Foundation
import SwiftData

/// 端末内に保存した録音ファイルの記録．
///
/// 録音ファイルは1時間ごと(または録音の停止・中断・手動送信ごと)に区切られる．
/// `UploadManager`がサーバーへ送信し，サーバーでの処理が終わった時点でファイルと記録を削除する．
@Model
final class RecordingFile {
    /// サーバーへの送信の状態．
    enum UploadState: String, Codable {
        /// 送信を待っている．
        case pending
        /// 送信済みで，サーバーでの処理の完了を待っている．
        case processing
        /// 失敗が上限の回数に達したため，自動での再送を止めた(手動の送信で再開する)．
        case gaveUp
    }

    /// 録音ファイルのID．サーバーへ送信する際の`client_file_id`として用いる．
    @Attribute(.unique) var clientFileId: String
    /// `RecordingStorage.directory`内のファイル名．
    var fileName: String
    /// 録音開始時刻．サーバーへ送信する際の`recorded_started_at`として用いる．
    var startedAt: Date
    /// 録音終了時刻．
    var endedAt: Date
    /// ファイルのサイズ(バイト)．
    var byteSize: Int64
    /// 送信の状態(`UploadState`の値)．
    var uploadStateRawValue: String = UploadState.pending.rawValue
    /// サーバーが発行したアップロード記録のID．送信前，または再送が必要になった場合はnil．
    var uploadRecordId: String?
    /// 最後に送信した日時．
    var uploadedAt: Date?
    /// サーバーでの処理の失敗の回数．
    var failureCount: Int = 0
    /// 次に送信・状況の確認を行ってよい日時．nilの場合はすぐに行ってよい．
    var nextAttemptAt: Date?
    /// 直近のエラーの内容．
    var lastError: String?

    /// ファイルのURL．
    var url: URL { RecordingStorage.directory.appending(path: fileName) }

    /// 録音の長さ(秒)．
    var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }

    /// 送信の状態．
    var uploadState: UploadState {
        get { UploadState(rawValue: uploadStateRawValue) ?? .pending }
        set { uploadStateRawValue = newValue.rawValue }
    }

    /// - Parameters:
    ///   - clientFileId: 録音ファイルのID
    ///   - fileName: ファイル名
    ///   - startedAt: 録音開始時刻
    ///   - endedAt: 録音終了時刻
    ///   - byteSize: ファイルのサイズ(バイト)
    init(clientFileId: String, fileName: String, startedAt: Date, endedAt: Date, byteSize: Int64) {
        self.clientFileId = clientFileId
        self.fileName = fileName
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.byteSize = byteSize
    }
}
