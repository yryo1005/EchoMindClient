import Foundation

/// アカウント登録・ログインのリクエストボディ．
nonisolated struct Credentials: Encodable {
    let email: String
    let password: String
}

/// アカウント登録・ログインのレスポンス(`access_token`，`token_type`)．
nonisolated struct TokenResponse: Decodable {
    let accessToken: String
}

/// ログイン中のユーザー情報(`GET /api/auth/me`のレスポンス)．
///
/// オフラインで起動した場合もアカウントを識別できるよう，端末にも保存する(`AuthSession`)．
nonisolated struct User: Codable, Equatable {
    let userId: String
    let email: String
    let role: String
}
