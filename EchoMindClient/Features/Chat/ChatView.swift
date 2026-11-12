import SwiftData
import SwiftUI

/// 質問(QA)タブの画面．過去の会話記録について質問し，回答を表示する．
struct ChatView: View {
    @Environment(AuthSession.self) private var authSession

    var body: some View {
        NavigationStack {
            Group {
                if let userId = authSession.currentUser?.userId {
                    ChatThreadView(userId: userId)
                } else {
                    // ログイン直後にユーザー情報を取得するまでの短い間のみ表示される
                    ProgressView("アカウント情報を取得中…")
                }
            }
            .navigationTitle("質問")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: ConversationReference.self) { reference in
                ConversationLookupView(time: reference.time)
            }
        }
    }
}

/// 1つのアカウントのチャット履歴と入力欄．
private struct ChatThreadView: View {
    /// 回答待ちの表示に用いるスクロール位置のID．
    private static let waitingRowID = "waiting"

    let userId: String

    @Environment(\.modelContext) private var modelContext
    @Query private var messages: [ChatMessage]
    @State private var controller = ChatController()
    @State private var draft = ""
    @State private var isConfirmingDeletion = false
    @FocusState private var isInputFocused: Bool

    /// - Parameter userId: 表示するアカウントのユーザーID
    init(userId: String) {
        self.userId = userId
        _messages = Query(filter: #Predicate<ChatMessage> { $0.userId == userId }, sort: \ChatMessage.createdAt)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatMessageRow(message: message) {
                            Task { await controller.retry(message, in: modelContext) }
                        }
                        .id(message.persistentModelID)
                    }
                    if controller.isWaitingForAnswer {
                        waitingRow.id(Self.waitingRowID)
                    }
                }
                .padding()
            }
            .overlay {
                if messages.isEmpty && !controller.isWaitingForAnswer {
                    emptyState
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onAppear { scrollToBottom(proxy, animated: false) }
            .onChange(of: messages.count) { scrollToBottom(proxy, animated: true) }
            .onChange(of: controller.isWaitingForAnswer) { scrollToBottom(proxy, animated: true) }
        }
        .safeAreaInset(edge: .bottom) { inputBar }
        .toolbar {
            Menu("その他", systemImage: "ellipsis.circle") {
                Button("履歴を削除", systemImage: "trash", role: .destructive) { isConfirmingDeletion = true }
                    .disabled(messages.isEmpty)
            }
        }
        .confirmationDialog("この端末に保存されている質問の履歴をすべて削除しますか？", isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("削除", role: .destructive) { controller.deleteHistory(userId: userId, in: modelContext) }
        }
    }

    /// 履歴が空のときに表示する案内．
    private var emptyState: some View {
        ContentUnavailableView(
            "過去の会話について質問できます",
            systemImage: "bubble.left.and.text.bubble.right",
            description: Text("例: 「明日のMTGは何時から？」")
        )
    }

    /// 回答を待っている間に表示する行．
    private var waitingRow: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("回答を生成中…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    /// 画面下部の入力欄．
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("質問を入力", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($isInputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.background.secondary, in: .rect(cornerRadius: 18))
            Button("送信", systemImage: "arrow.up.circle.fill", action: send)
                .labelStyle(.iconOnly)
                .font(.title)
                .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// 送信できる状態かどうか(入力があり，回答待ちでない)．
    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !controller.isWaitingForAnswer
    }

    /// 入力中の質問を送信する．
    private func send() {
        let query = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        draft = ""
        Task { await controller.ask(query, userId: userId, in: modelContext) }
    }

    /// 最新のメッセージ(回答待ちの場合はその表示)までスクロールする．
    /// - Parameters:
    ///   - proxy: スクロール位置を操作するプロキシ
    ///   - animated: アニメーションするかどうか
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let target: AnyHashable? = controller.isWaitingForAnswer
            ? Self.waitingRowID
            : messages.last.map { AnyHashable($0.persistentModelID) }
        guard let target else { return }
        withAnimation(animated ? .default : nil) {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }
}

/// チャットの1件のメッセージを表示する行．
private struct ChatMessageRow: View {
    let message: ChatMessage
    /// エラーのメッセージで「再送」が押された際の処理．
    let onRetry: () -> Void

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(12)
                    .foregroundStyle(.white)
                    .background(.tint, in: .rect(cornerRadius: 16))
                    .textSelection(.enabled)
            }
        case .assistant:
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.text)
                        .textSelection(.enabled)
                    if !message.references.isEmpty {
                        referencesView
                    }
                }
                .padding(12)
                .background(.background.secondary, in: .rect(cornerRadius: 16))
                Spacer(minLength: 48)
            }
        case .error:
            VStack(alignment: .leading, spacing: 8) {
                Label(message.text, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                if message.failedQuery != nil {
                    Button("再送", systemImage: "arrow.clockwise", action: onRetry)
                        .buttonStyle(.bordered)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 回答の根拠となった発言の日時の一覧．タップすると該当する会話を開く．
    private var referencesView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("参照した会話")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ForEach(Self.uniqueReferences(message.references), id: \.self) { time in
                NavigationLink(value: ConversationReference(time: time)) {
                    Label(time.monthDayTimeLabel, systemImage: "waveform")
                }
                .font(.caption)
            }
        }
    }

    /// 参照日時から，表示が同じ分になるものを除いて古い順に並べる．
    /// - Parameter references: 参照日時
    /// - Returns: 重複のない参照日時(古い順)．同じ分のものは最も古い日時を残す．
    private static func uniqueReferences(_ references: [Date]) -> [Date] {
        var seenLabels = Set<String>()
        return references.sorted().filter { seenLabels.insert($0.monthDayTimeLabel).inserted }
    }
}

#Preview {
    ChatView()
        .environment(AuthSession())
        .modelContainer(for: ChatMessage.self, inMemory: true)
}
