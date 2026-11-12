import Foundation

/// `POST /api/upload`のレスポンス．
///
/// 新規に受け付けた場合は`status`が"accepted"，同じ音声を処理済み・処理中の場合は"duplicate"となり，
/// "duplicate"の場合のみ`processingStatus`と`safeToDeleteClientCopy`を含む．
nonisolated struct UploadResponse: Decodable, Sendable {
    let status: String
    let uploadRecordId: String
    let processingStatus: String?
    let safeToDeleteClientCopy: Bool?
}

/// `GET /api/upload/{upload_record_id}/status`のレスポンス．
nonisolated struct UploadStatusResponse: Decodable, Sendable {
    let uploadRecordId: String
    /// "processing"，"completed"，"rejected"，"failed"のいずれか．
    let status: String
    let isFinished: Bool
    let safeToDeleteClientCopy: Bool
    let conversationId: String?
}
