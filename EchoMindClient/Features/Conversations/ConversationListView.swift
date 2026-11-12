import SwiftUI

/// 会話一覧の画面．会話タブ，および人物ごとの会話一覧として使用する．
///
/// 開始時刻の新しい順に`BrowseAPI.pageSize`件ずつ取得し，末尾までスクロールすると続きを読み込む．
struct ConversationListView: View {
    /// 絞り込む人物のID．nilの場合はすべての会話を表示する．
    let personId: String?
    /// 画面のタイトル．
    let title: String

    @State private var conversations: [ConversationSummary] = []
    @State private var hasLoaded = false
    @State private var isLoading = false
    @State private var canLoadMore = true
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(conversations) { conversation in
                NavigationLink(value: conversation) {
                    ConversationRow(conversation: conversation)
                }
                .onAppear {
                    if conversation == conversations.last {
                        Task { await load(reset: false) }
                    }
                }
            }
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
            if let errorMessage {
                LoadErrorRow(message: errorMessage) {
                    Task { await load(reset: conversations.isEmpty) }
                }
            }
        }
        .overlay {
            if hasLoaded && conversations.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "会話がありません",
                    systemImage: "waveform",
                    description: Text("録音した音声がサーバーで処理されると，ここに表示されます．")
                )
            }
        }
        .navigationTitle(title)
        .navigationDestination(for: ConversationSummary.self) { conversation in
            ConversationDetailView(conversationId: conversation.conversationId)
        }
        .task {
            if !hasLoaded {
                await load(reset: true)
            }
        }
        .refreshable { await load(reset: true) }
    }

    /// 会話一覧を読み込む．
    /// - Parameter reset: trueの場合は先頭から読み込み直し，falseの場合は続きを読み込む
    private func load(reset: Bool) async {
        guard !isLoading, reset || canLoadMore else { return }
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            let offset = reset ? 0 : conversations.count
            let page = try await BrowseAPI.conversations(offset: offset, personId: personId)
            conversations = reset ? page : conversations + page
            canLoadMore = page.count == BrowseAPI.pageSize
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 会話一覧の1行．期間，参加者，発言数を表示する．
private struct ConversationRow: View {
    let conversation: ConversationSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.periodLabel(from: conversation.startedAt, to: conversation.endedAt))
                .font(.headline)
            Text(conversation.participantNames.joined(separator: "，"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text("発言 \(conversation.utteranceCount)件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// 読み込みに失敗したことを示し，再試行ボタンを持つ行．
struct LoadErrorRow: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Button("再読み込み", systemImage: "arrow.clockwise", action: onRetry)
                .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        ConversationListView(personId: nil, title: "会話")
    }
}
