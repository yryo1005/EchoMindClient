import Foundation
import Observation
import SwiftData

/// 質問の送信と，回答・エラーの履歴への保存を行うクラス．
@Observable
final class ChatController {
    /// 回答の生成はGemini APIの再試行(レート制限時の待機)で時間がかかる場合があるため，通常のAPIより長く待つ．
    private static let answerTimeout: TimeInterval = 120

    /// 回答を待っているかどうか．
    private(set) var isWaitingForAnswer = false

    private let api: APIClient

    /// - Parameter api: 使用するAPIクライアント
    init(api: APIClient = .shared) {
        self.api = api
    }

    /// 質問を履歴に追加し，サーバーに送信して回答を履歴に追加する．
    /// - Parameters:
    ///   - query: 質問文
    ///   - userId: ログイン中のアカウントのユーザーID
    ///   - context: 履歴を保存するSwiftDataのコンテキスト
    func ask(_ query: String, userId: String, in context: ModelContext) async {
        context.insert(ChatMessage(userId: userId, role: .user, text: query))
        await requestAnswer(to: query, userId: userId, in: context)
    }

    /// 送信に失敗した質問を再送する．エラーのメッセージは履歴から削除する．
    /// - Parameters:
    ///   - errorMessage: 送信に失敗したことを示すメッセージ
    ///   - context: 履歴を保存するSwiftDataのコンテキスト
    func retry(_ errorMessage: ChatMessage, in context: ModelContext) async {
        guard let query = errorMessage.failedQuery else { return }
        let userId = errorMessage.userId
        context.delete(errorMessage)
        await requestAnswer(to: query, userId: userId, in: context)
    }

    /// アカウントのチャット履歴をすべて削除する．
    /// - Parameters:
    ///   - userId: 履歴を削除するアカウントのユーザーID
    ///   - context: 履歴を保存するSwiftDataのコンテキスト
    func deleteHistory(userId: String, in context: ModelContext) {
        try? context.delete(model: ChatMessage.self, where: #Predicate { $0.userId == userId })
        try? context.save()
    }

    /// サーバーに質問を送信し，回答またはエラーを履歴に追加する．
    /// - Parameters:
    ///   - query: 質問文
    ///   - userId: ログイン中のアカウントのユーザーID
    ///   - context: 履歴を保存するSwiftDataのコンテキスト
    private func requestAnswer(to query: String, userId: String, in context: ModelContext) async {
        isWaitingForAnswer = true
        defer {
            isWaitingForAnswer = false
            try? context.save()
        }

        do {
            let response: ChatResponse = try await api.send(
                .post, "api/chat", body: ChatRequest(query: query), timeout: Self.answerTimeout
            )
            context.insert(
                ChatMessage(userId: userId, role: .assistant, text: response.answer, references: response.references)
            )
        } catch {
            context.insert(
                ChatMessage(userId: userId, role: .error, text: error.localizedDescription, failedQuery: query)
            )
        }
    }
}
