import Foundation
import Observation

/// ログイン状態を管理するクラス．
///
/// アクセストークンがKeychainに保存されていればログイン済みとして扱う．サーバーに接続できない
/// 状態でもログイン済みの画面(録音機能等)を使えるよう，起動時にサーバーへの問い合わせ結果を待たない．
/// 認証が必要なAPIで401が返った場合(トークンの期限切れ等)は自動的にログアウトする．
@Observable
final class AuthSession {
    /// アプリ全体で共有するインスタンス．APIクライアントの401処理(自動ログアウト)はこのインスタンスにのみ紐づける
    /// (プレビュー等で別のインスタンスを作成しても，共有インスタンスの401処理が上書きされないようにするため)．
    static let shared: AuthSession = {
        let session = AuthSession()
        APIClient.shared.onUnauthorized = { [weak session] in
            session?.logout()
        }
        return session
    }()

    /// ログイン中のユーザー情報をUserDefaultsに保存する際のキー．
    private static let currentUserKey = "currentUser"

    /// ログイン済みかどうか(アクセストークンを保持しているかどうか)．
    private(set) var isLoggedIn: Bool
    /// ログイン中のユーザー情報．端末に保存した値を起動時に読み込み，サーバーから取得した値で更新する．
    /// ログイン直後でまだ一度も取得できていない場合はnil．
    private(set) var currentUser: User? {
        didSet { Self.saveCachedUser(currentUser) }
    }

    private let api: APIClient

    /// アプリでは`shared`を使用する．このイニシャライザはプレビュー等で独立したインスタンスが必要な場合に用いる．
    /// - Parameter api: 使用するAPIクライアント
    init(api: APIClient = .shared) {
        self.api = api
        isLoggedIn = KeychainStore.load(account: APIClient.accessTokenAccount) != nil
        currentUser = isLoggedIn ? Self.loadCachedUser() : nil
    }

    /// メールアドレスとパスワードでログインする．
    /// - Parameters:
    ///   - email: メールアドレス
    ///   - password: パスワード
    /// - Throws: `APIError`，`KeychainStore.KeychainError`
    func login(email: String, password: String) async throws {
        let response: TokenResponse = try await api.send(
            .post, "api/auth/login", body: Credentials(email: email, password: password), requiresAuth: false
        )
        try didReceiveToken(response.accessToken)
    }

    /// アカウントを登録し，そのままログインする．
    /// - Parameters:
    ///   - email: メールアドレス
    ///   - password: パスワード(8文字以上)
    /// - Throws: `APIError`，`KeychainStore.KeychainError`
    func register(email: String, password: String) async throws {
        let response: TokenResponse = try await api.send(
            .post, "api/auth/register", body: Credentials(email: email, password: password), requiresAuth: false
        )
        try didReceiveToken(response.accessToken)
    }

    /// サーバーからログイン中のユーザー情報を取得する．
    ///
    /// 通信に失敗してもログイン状態は変えない(オフラインでも利用を続けられるようにするため)．
    /// トークンが無効な場合は，APIクライアントの401処理によりログアウトされる．
    func refreshCurrentUser() async {
        guard isLoggedIn else { return }
        if let user: User = try? await api.send(.get, "api/auth/me") {
            currentUser = user
        }
    }

    /// ログアウトする(Keychainのアクセストークンを削除する)．
    func logout() {
        KeychainStore.delete(account: APIClient.accessTokenAccount)
        isLoggedIn = false
        currentUser = nil
    }

    /// 発行されたアクセストークンを保存し，ログイン状態にする．
    /// - Parameter token: アクセストークン(JWT)
    /// - Throws: `KeychainStore.KeychainError`
    private func didReceiveToken(_ token: String) throws {
        try KeychainStore.save(token, account: APIClient.accessTokenAccount)
        currentUser = nil
        isLoggedIn = true
        Task { await refreshCurrentUser() }
    }

    /// 端末に保存したユーザー情報を読み込む．
    /// - Returns: 保存されているユーザー情報．存在しない場合はnil．
    private static func loadCachedUser() -> User? {
        guard let data = UserDefaults.standard.data(forKey: currentUserKey) else { return nil }
        return try? JSONDecoder().decode(User.self, from: data)
    }

    /// ユーザー情報を端末に保存する．nilの場合は削除する．
    /// - Parameter user: 保存するユーザー情報
    private static func saveCachedUser(_ user: User?) {
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: currentUserKey)
        } else {
            UserDefaults.standard.removeObject(forKey: currentUserKey)
        }
    }
}
