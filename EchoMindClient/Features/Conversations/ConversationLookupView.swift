import SwiftUI

/// 質問の回答が参照した日時(発言の開始時刻)．画面遷移の値として用いる．
struct ConversationReference: Hashable {
    let time: Date
}

/// 参照日時を含む会話を探して表示する画面．
///
/// 質問の回答は会話IDを返さないため，`BrowseAPI.conversation(containing:)`で会話を探してから，
/// 該当する発言を強調表示した会話の詳細を表示する．
struct ConversationLookupView: View {
    /// 探索の状態．
    private enum LookupState {
        case searching
        case found(ConversationSummary)
        case notFound
        case failed(String)
    }

    let time: Date

    @State private var state = LookupState.searching

    var body: some View {
        switch state {
        case .searching:
            ProgressView("会話を探しています…")
                .task { await lookUp() }
        case .found(let conversation):
            ConversationDetailView(conversationId: conversation.conversationId, highlightTime: time)
        case .notFound:
            ContentUnavailableView(
                "会話が見つかりません",
                systemImage: "magnifyingglass",
                description: Text("\(time.monthDayTimeLabel) の発言を含む会話が見つかりませんでした．")
            )
        case .failed(let message):
            List {
                LoadErrorRow(message: message) {
                    state = .searching
                }
            }
        }
    }

    /// 参照日時を含む会話を探す．
    private func lookUp() async {
        do {
            if let conversation = try await BrowseAPI.conversation(containing: time) {
                state = .found(conversation)
            } else {
                state = .notFound
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }
}
