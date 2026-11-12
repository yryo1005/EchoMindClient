import SwiftUI

/// 会話の詳細(発言一覧)の画面．発言ごとに音声を再生できる．
///
/// 話者名をタップすると，その人物の名前を設定できる(音声を聞いて誰か分かった時にその場で設定するため)．
struct ConversationDetailView: View {
    let conversationId: String
    /// 強調表示する発言の開始時刻(質問の回答の参照日時から開いた場合)．
    var highlightTime: Date?

    @State private var detail: ConversationDetail?
    @State private var errorMessage: String?
    @State private var player = AudioClipPlayer()
    @State private var editingTarget: PersonNameTarget?

    var body: some View {
        Group {
            if let detail {
                utteranceList(detail)
            } else if let errorMessage {
                List {
                    LoadErrorRow(message: errorMessage) {
                        Task { await load() }
                    }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(detail.map { $0.startedAt.monthDayTimeLabel } ?? "会話")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if detail == nil {
                await load()
            }
        }
        .onDisappear { player.stop() }
        .personNameEditor(target: $editingTarget) { _ in
            // 同じ人物の他の発言の話者名も変わるため，会話を読み込み直す
            Task { await load() }
        }
        .alert(
            "再生できませんでした",
            isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.errorMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(player.errorMessage ?? "")
        }
    }

    /// 発言一覧を表示するリスト．強調表示する発言があればその位置までスクロールする．
    /// - Parameter detail: 会話の詳細
    /// - Returns: 発言一覧のビュー
    private func utteranceList(_ detail: ConversationDetail) -> some View {
        let highlightedId = highlightedUtteranceId(in: detail)
        return ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(detail.utterances) { utterance in
                        UtteranceRow(
                            utterance: utterance,
                            isPlaying: player.activeUtteranceId == utterance.id,
                            isLoading: player.activeUtteranceId == utterance.id && player.isLoading,
                            onTogglePlayback: { player.toggle(utteranceId: utterance.id) },
                            onEditSpeakerName: {
                                editingTarget = PersonNameTarget(personId: utterance.personId, currentName: utterance.personName)
                            }
                        )
                        .listRowBackground(utterance.id == highlightedId ? Color.accentColor.opacity(0.15) : nil)
                        .id(utterance.id)
                    }
                } header: {
                    Text(Date.periodLabel(from: detail.startedAt, to: detail.endedAt))
                }
            }
            .onAppear {
                if let highlightedId {
                    proxy.scrollTo(highlightedId, anchor: .center)
                }
            }
        }
    }

    /// 強調表示する発言のIDを返す．
    /// - Parameter detail: 会話の詳細
    /// - Returns: 開始時刻が`highlightTime`に最も近い発言のID(1秒以内のもの)．該当しない場合はnil．
    private func highlightedUtteranceId(in detail: ConversationDetail) -> String? {
        guard let highlightTime else { return nil }
        return detail.utterances
            .min { abs($0.startTime.timeIntervalSince(highlightTime)) < abs($1.startTime.timeIntervalSince(highlightTime)) }
            .flatMap { abs($0.startTime.timeIntervalSince(highlightTime)) <= 1 ? $0.id : nil }
    }

    /// 会話の詳細を読み込む．
    private func load() async {
        errorMessage = nil
        do {
            detail = try await BrowseAPI.conversation(id: conversationId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 発言の1行．話者名(タップすると名前を設定する)，時刻，本文，再生ボタンを表示する．
private struct UtteranceRow: View {
    let utterance: Utterance
    let isPlaying: Bool
    let isLoading: Bool
    let onTogglePlayback: () -> Void
    let onEditSpeakerName: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Button(action: onEditSpeakerName) {
                        Label(utterance.speakerName, systemImage: "pencil")
                            .labelStyle(SpeakerNameLabelStyle())
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(utterance.personName == nil ? .secondary : .primary)
                    .accessibilityHint("この人物の名前を設定します")
                    Text(utterance.startTime.timeWithSecondsLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(utterance.text)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            playbackButton
        }
        .padding(.vertical, 2)
    }

    /// 再生・停止のボタン．音声の読み込み中は進行状況を表示する．
    @ViewBuilder
    private var playbackButton: some View {
        if isLoading {
            ProgressView()
                .frame(width: 32, height: 32)
        } else {
            Button(
                isPlaying ? "停止" : "再生",
                systemImage: isPlaying ? "stop.circle.fill" : "play.circle.fill",
                action: onTogglePlayback
            )
            .labelStyle(.iconOnly)
            .font(.title2)
            .buttonStyle(.borderless)
        }
    }
}

/// 話者名のラベルの見た目．名前の後ろに小さな鉛筆のアイコンを付け，タップで編集できることを示す．
private struct SpeakerNameLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
                .font(.subheadline.bold())
            configuration.icon
                .font(.caption2)
                .foregroundStyle(.tint)
        }
    }
}

#Preview {
    NavigationStack {
        ConversationDetailView(conversationId: "preview")
    }
}
