import Foundation

/// 会話・発言・人物の閲覧APIを呼び出す名前空間．
enum BrowseAPI {
    /// 会話一覧を1回で取得する件数．
    nonisolated static let pageSize = 20

    /// 会話一覧を開始時刻の新しい順に取得する．
    /// - Parameters:
    ///   - offset: スキップする件数(ページング用)
    ///   - limit: 取得する件数
    ///   - personId: 指定した場合，この人物が参加した会話のみに絞り込む
    /// - Returns: 会話一覧
    /// - Throws: `APIError`
    static func conversations(offset: Int, limit: Int = pageSize, personId: String? = nil) async throws
        -> [ConversationSummary]
    {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let personId {
            query.append(URLQueryItem(name: "person_id", value: personId))
        }
        return try await APIClient.shared.send(.get, "api/conversations", query: query)
    }

    /// 会話の詳細(発言一覧)を取得する．
    /// - Parameter conversationId: 会話ID
    /// - Returns: 会話の詳細
    /// - Throws: `APIError`
    static func conversation(id conversationId: String) async throws -> ConversationDetail {
        try await APIClient.shared.send(.get, "api/conversations/\(conversationId)")
    }

    /// 人物一覧を発言数の多い順に取得する．
    /// - Returns: 人物一覧
    /// - Throws: `APIError`
    static func persons() async throws -> [Person] {
        try await APIClient.shared.send(.get, "api/persons")
    }

    /// 人物の名前を設定する．
    /// - Parameters:
    ///   - personId: 人物ID
    ///   - name: 設定する名前(空文字列はサーバーで拒否される)
    /// - Returns: 更新後の人物情報
    /// - Throws: `APIError`
    static func updatePersonName(personId: String, name: String) async throws -> Person {
        try await APIClient.shared.send(.put, "api/persons/\(personId)/name", body: UpdatePersonNameRequest(name: name))
    }

    /// 発言の音声データ(AAC/.m4a)を取得する．
    /// - Parameter utteranceId: 発言ID
    /// - Returns: 音声ファイルのデータ
    /// - Throws: `APIError`
    static func audio(utteranceId: String) async throws -> Data {
        try await APIClient.shared.data("api/audio/\(utteranceId)")
    }

    /// 指定した日時を含む会話を探す．
    ///
    /// 質問の回答が返す参照日時は発言の開始時刻のみであり，会話IDを含まない．
    /// そのため，会話一覧を新しい順にたどり，開始から終了までの間に参照日時を含む会話を探す．
    /// 一覧の会話がすべて参照日時より前に始まっている場合，それ以降のページにも該当する会話はないため探索を打ち切る．
    ///
    /// - Parameters:
    ///   - time: 探す日時(発言の開始時刻)
    ///   - maxPages: たどるページ数の上限
    /// - Returns: 日時を含む会話．見つからない場合はnil．
    /// - Throws: `APIError`
    static func conversation(containing time: Date, maxPages: Int = 50) async throws -> ConversationSummary? {
        // サーバーの日時はマイクロ秒を含むため，端の比較で取りこぼさないよう1秒の余裕を持たせる
        let tolerance: TimeInterval = 1
        for page in 0..<maxPages {
            let summaries = try await conversations(offset: page * pageSize)
            if let match = summaries.first(where: {
                $0.startedAt.addingTimeInterval(-tolerance) <= time && time <= $0.endedAt.addingTimeInterval(tolerance)
            }) {
                return match
            }
            let isLastPage = summaries.count < pageSize
            let passedTime = summaries.last.map { $0.startedAt.addingTimeInterval(-tolerance) < time } ?? true
            if isLastPage || passedTime {
                return nil
            }
        }
        return nil
    }
}
