import Foundation

/// 人物(話者)の情報(`GET /api/persons`のレスポンスの要素)．
nonisolated struct Person: Decodable, Identifiable, Hashable {
    let personId: String
    /// 名前．自動推定・手動設定のいずれもされていない場合はnil．
    var name: String?
    /// 全会話での発言数．
    let utteranceCount: Int

    var id: String { personId }

    /// 画面に表示する名前．名前が未設定の場合は人物IDの先頭8文字を添えて区別する．
    var displayName: String {
        Self.displayName(name: name, personId: personId)
    }

    /// 人物の表示名を返す．
    /// - Parameters:
    ///   - name: 人物の名前(未設定の場合はnil)
    ///   - personId: 人物ID
    /// - Returns: 名前，または「名前未設定 (人物IDの先頭8文字)」
    static func displayName(name: String?, personId: String) -> String {
        if let name, !name.isEmpty {
            return name
        }
        return "名前未設定 (\(personId.prefix(8)))"
    }
}

/// `PUT /api/persons/{person_id}/name`のリクエストボディ．
nonisolated struct UpdatePersonNameRequest: Encodable {
    let name: String
}

/// 会話一覧の1件(`GET /api/conversations`のレスポンスの要素)．
nonisolated struct ConversationSummary: Decodable, Identifiable, Hashable {
    let conversationId: String
    let startedAt: Date
    let endedAt: Date
    /// 参加者の名前．名前が未設定の人物は"(人物IDの先頭8文字)"となる．
    let participantNames: [String]
    let utteranceCount: Int

    var id: String { conversationId }
}

/// 会話の詳細(`GET /api/conversations/{conversation_id}`のレスポンス)．
nonisolated struct ConversationDetail: Decodable {
    let conversationId: String
    let startedAt: Date
    let endedAt: Date
    /// 発言の一覧(開始時刻順)．
    let utterances: [Utterance]
}

/// 会話内の1つの発言．
nonisolated struct Utterance: Decodable, Identifiable {
    let utteranceId: String
    let personId: String
    let personName: String?
    let startTime: Date
    let endTime: Date
    let text: String

    var id: String { utteranceId }

    /// 画面に表示する話者名．
    var speakerName: String {
        Person.displayName(name: personName, personId: personId)
    }
}
