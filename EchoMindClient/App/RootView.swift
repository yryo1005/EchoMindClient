import SwiftData
import SwiftUI

/// アプリのルート画面．未ログインの場合はログイン画面を，ログイン済みの場合は機能ごとのタブを表示する．
///
/// 録音タブには，対処が必要な状態(録音が有効なのに止まっている，自動での再送を中止した録音がある)の件数をバッジで表示する．
struct RootView: View {
    @Environment(AuthSession.self) private var authSession
    @Query private var recordingFiles: [RecordingFile]

    var body: some View {
        if authSession.isLoggedIn {
            mainTabs
                .task { await authSession.refreshCurrentUser() }
        } else {
            LoginView()
        }
    }

    /// ログイン後に表示する機能ごとのタブ．
    private var mainTabs: some View {
        TabView {
            Tab("質問", systemImage: "bubble.left.and.text.bubble.right") {
                ChatView()
            }
            Tab("会話", systemImage: "waveform") {
                NavigationStack {
                    ConversationListView(personId: nil, title: "会話")
                }
            }
            Tab("人物", systemImage: "person.2") {
                NavigationStack {
                    PersonsView()
                }
            }
            Tab("録音", systemImage: "record.circle") {
                RecordingView()
            }
            .badge(recordingAttentionCount)
            Tab("設定", systemImage: "gearshape") {
                SettingsView()
            }
        }
    }

    /// 録音タブで対処が必要な項目の数．
    private var recordingAttentionCount: Int {
        let gaveUp = recordingFiles.count { $0.uploadState == .gaveUp }
        return gaveUp + (AudioRecorder.shared.needsAttention ? 1 : 0)
    }
}

#Preview {
    RootView()
        .environment(AuthSession())
        .modelContainer(for: [ChatMessage.self, RecordingFile.self], inMemory: true)
}
