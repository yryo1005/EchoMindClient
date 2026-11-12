import Foundation
import SwiftData

/// `POST /api/chat`のリクエストボディ．
nonisolated struct ChatRequest: Encodable {
    let query: String
}

/// `POST /api/chat`のレスポンス．
nonisolated struct ChatResponse: Decodable {
    /// 回答テキスト．
    let answer: String
    /// 回答の根拠となった発言の開始時刻(UTC)．
    let references: [Date]
}

/// 端末内に保存するチャットの1件のメッセージ．
///
/// チャット履歴はサーバーに保存されないため，SwiftDataで端末内に保存する．
/// 同じ端末で別のアカウントにログインした場合に履歴が混ざらないよう，ユーザーIDを持たせる．
@Model
final class ChatMessage {
    /// メッセージの種類．
    enum Role: String {
        /// ユーザーの質問．
        case user
        /// サーバーからの回答．
        case assistant
        /// 送信に失敗したことを示すメッセージ．
        case error
    }

    /// メッセージを送受信したアカウントのユーザーID．
    var userId: String
    /// `Role`の値(SwiftDataの検索条件で扱いやすいよう文字列で保存する)．
    var roleRawValue: String
    /// 本文．エラーの場合はエラーメッセージ．
    var text: String
    /// 回答の根拠となった発言の開始時刻(回答の場合のみ)．
    var references: [Date]
    /// 送信に失敗した質問の本文(エラーの場合のみ．再送に用いる)．
    var failedQuery: String?
    /// 作成日時．
    var createdAt: Date

    /// メッセージの種類．
    var role: Role { Role(rawValue: roleRawValue) ?? .error }

    /// - Parameters:
    ///   - userId: アカウントのユーザーID
    ///   - role: メッセージの種類
    ///   - text: 本文
    ///   - references: 回答の根拠となった発言の開始時刻
    ///   - failedQuery: 送信に失敗した質問の本文
    ///   - createdAt: 作成日時
    init(
        userId: String, role: Role, text: String, references: [Date] = [], failedQuery: String? = nil,
        createdAt: Date = .now
    ) {
        self.userId = userId
        self.roleRawValue = role.rawValue
        self.text = text
        self.references = references
        self.failedQuery = failedQuery
        self.createdAt = createdAt
    }
}
