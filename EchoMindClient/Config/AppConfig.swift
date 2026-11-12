import Foundation

/// アプリ全体の設定値を管理する名前空間．
///
/// サーバーURL(Cloudflare Tunnelで公開したEchoMindServerのURL)は端末ごとに異なり得るため，
/// ソースコードには埋め込まず，設定画面から入力した値をUserDefaultsに保存して用いる．
enum AppConfig {
    /// サーバーURLをUserDefaultsに保存する際のキー．
    static let serverURLKey = "serverURL"

    /// 保存されているサーバーURLを取得する．
    /// - Returns: 正規化済みのサーバーURL．未設定または不正な形式の場合はnil．
    static var serverURL: URL? {
        guard let text = UserDefaults.standard.string(forKey: serverURLKey) else { return nil }
        return normalizedServerURL(from: text)
    }

    /// 入力されたサーバーURLの文字列を検証し，末尾のスラッシュを除いたURLに正規化する．
    /// - Parameter text: ユーザーが入力したURL文字列(例: "https://echomind.example.com/")
    /// - Returns: http/httpsのスキームとホストを持つURL．条件を満たさない場合はnil．
    static func normalizedServerURL(from text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host() != nil
        else { return nil }
        return url
    }
}
