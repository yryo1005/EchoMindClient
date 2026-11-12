import SwiftData

/// アプリ全体で共有するSwiftDataのコンテナ．
///
/// 画面(`@Query`)だけでなく，録音の制御(`AudioRecorder`)からも録音ファイルの記録を
/// 追加するため，コンテナを1つにまとめる．
enum AppDataStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(for: ChatMessage.self, RecordingFile.self)
        } catch {
            fatalError("SwiftDataのコンテナを作成できませんでした: \(error)")
        }
    }()
}
