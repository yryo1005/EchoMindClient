import Foundation

/// HTTPメソッド．
nonisolated enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

/// APIの呼び出しで発生するエラー．
nonisolated enum APIError: LocalizedError {
    /// サーバーURLが設定されていない．
    case serverURLNotConfigured
    /// 認証が必要なAPIで401が返った(トークンの期限切れ等)．
    case unauthorized
    /// サーバーがエラーを返した．`detail`はFastAPIのエラーメッセージ．
    case server(statusCode: Int, detail: String?)
    /// HTTPのレスポンスではない．
    case invalidResponse
    /// レスポンスの形式が想定と異なる．
    case decoding(Error)
    /// 通信に失敗した(オフライン，タイムアウト等)．
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .serverURLNotConfigured:
            "設定画面でサーバーURLを入力してください．"
        case .unauthorized:
            "ログインの有効期限が切れました．もう一度ログインしてください．"
        case .server(let statusCode, let detail):
            detail ?? Self.defaultMessage(for: statusCode)
        case .invalidResponse, .decoding:
            "サーバーの応答を解釈できませんでした．"
        case .transport(let error):
            "サーバーに接続できませんでした(\(error.localizedDescription))．"
        }
    }

    /// FastAPIが文字列の`detail`を返さなかった場合に表示するメッセージを返す．
    /// - Parameter statusCode: HTTPステータスコード
    /// - Returns: 表示用のメッセージ
    private static func defaultMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 422:
            "入力内容の形式が正しくありません．"
        case 500...:
            "サーバーでエラーが発生しました(HTTP \(statusCode))．"
        default:
            "リクエストに失敗しました(HTTP \(statusCode))．"
        }
    }
}

/// EchoMindServerのAPIを呼び出すクライアント．
///
/// サーバーURLは`AppConfig`から，アクセストークンはKeychainから都度読み出す．
/// JSONのキーはサーバー側のスネークケースとSwift側のキャメルケースを自動で変換する．
final class APIClient {
    /// アプリ全体で共有するインスタンス．
    static let shared = APIClient()

    /// アクセストークンをKeychainに保存する際のアカウント名．
    static let accessTokenAccount = "accessToken"

    /// 認証が必要なAPIで401が返った際に呼ばれる処理(ログアウト等)．
    var onUnauthorized: (() -> Void)?

    private let session: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    /// - Parameter session: 通信に使用するURLSession
    init(session: URLSession = .shared) {
        self.session = session

        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase

        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ServerDate.parse(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "日時の形式が不正です: \(text)")
            }
            return date
        }
    }

    /// リクエストボディを持たないAPIを呼び出し，レスポンスをデコードして返す．
    /// - Parameters:
    ///   - method: HTTPメソッド
    ///   - path: サーバーURLからの相対パス(例: "api/auth/me")
    ///   - query: URLのクエリパラメータ(例: `limit=20`)
    ///   - requiresAuth: Authorizationヘッダを付与するかどうか
    ///   - timeout: 応答を待つ秒数
    /// - Returns: デコードしたレスポンス
    /// - Throws: `APIError`
    func send<Response: Decodable>(
        _ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], requiresAuth: Bool = true,
        timeout: TimeInterval = 30
    ) async throws -> Response {
        let request = try makeRequest(method, path, query: query, requiresAuth: requiresAuth, timeout: timeout)
        return try decode(try await perform(request, requiresAuth: requiresAuth))
    }

    /// 認証が必要なファイル(発言の音声等)をGETで取得し，レスポンスボディをそのまま返す．
    /// - Parameters:
    ///   - path: サーバーURLからの相対パス(例: "api/audio/{utterance_id}")
    ///   - timeout: 応答を待つ秒数
    /// - Returns: レスポンスボディ
    /// - Throws: `APIError`
    func data(_ path: String, timeout: TimeInterval = 60) async throws -> Data {
        let request = try makeRequest(.get, path, query: [], requiresAuth: true, timeout: timeout)
        return try await perform(request, requiresAuth: true)
    }

    /// JSONのリクエストボディを持つAPIを呼び出し，レスポンスをデコードして返す．
    /// - Parameters:
    ///   - method: HTTPメソッド
    ///   - path: サーバーURLからの相対パス(例: "api/auth/login")
    ///   - body: JSONとして送信するリクエストボディ
    ///   - requiresAuth: Authorizationヘッダを付与するかどうか
    ///   - timeout: 応答を待つ秒数
    /// - Returns: デコードしたレスポンス
    /// - Throws: `APIError`
    func send<Body: Encodable, Response: Decodable>(
        _ method: HTTPMethod, _ path: String, body: Body, requiresAuth: Bool = true, timeout: TimeInterval = 30
    ) async throws -> Response {
        var request = try makeRequest(method, path, query: [], requiresAuth: requiresAuth, timeout: timeout)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try decode(try await perform(request, requiresAuth: requiresAuth))
    }

    /// ファイルと文字列のフィールドを`multipart/form-data`で送信し，レスポンスをデコードして返す．
    /// - Parameters:
    ///   - path: サーバーURLからの相対パス(例: "api/upload")
    ///   - fields: 文字列のフィールド(名前と値)
    ///   - fileField: ファイルのフィールド名
    ///   - fileURL: 送信するファイル
    ///   - mimeType: ファイルのMIMEタイプ
    ///   - timeout: 応答を待つ秒数
    /// - Returns: デコードしたレスポンス
    /// - Throws: `APIError`．ファイルを読み込めない場合は`APIError.transport`．
    func upload<Response: Decodable>(
        _ path: String, fields: [(String, String)], fileField: String, fileURL: URL, mimeType: String,
        timeout: TimeInterval = 600
    ) async throws -> Response {
        var request = try makeRequest(.post, path, query: [], requiresAuth: true, timeout: timeout)
        let boundary = "EchoMind-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            throw APIError.transport(error)
        }
        var body = Data()
        for (name, value) in fields {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileURL.lastPathComponent)\"\r\nContent-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(fileData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return try decode(try await perform(request, requiresAuth: true))
    }

    /// サーバーURL・パス・認証情報からリクエストを組み立てる．
    /// - Parameters:
    ///   - method: HTTPメソッド
    ///   - path: サーバーURLからの相対パス
    ///   - query: URLのクエリパラメータ
    ///   - requiresAuth: Authorizationヘッダを付与するかどうか
    ///   - timeout: 応答を待つ秒数
    /// - Returns: 組み立てたリクエスト
    /// - Throws: サーバーURLが未設定の場合は`APIError.serverURLNotConfigured`，
    ///   トークンがない場合は`APIError.unauthorized`
    private func makeRequest(
        _ method: HTTPMethod, _ path: String, query: [URLQueryItem], requiresAuth: Bool, timeout: TimeInterval
    ) throws -> URLRequest {
        guard let baseURL = AppConfig.serverURL else { throw APIError.serverURLNotConfigured }

        var url = baseURL.appending(path: path)
        if !query.isEmpty {
            url.append(queryItems: query)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        if requiresAuth {
            guard let token = KeychainStore.load(account: Self.accessTokenAccount) else {
                throw APIError.unauthorized
            }
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    /// リクエストを送信し，成功(2xx)したレスポンスのボディを返す．
    /// - Parameters:
    ///   - request: 送信するリクエスト
    ///   - requiresAuth: 認証が必要なAPIかどうか(401を期限切れとして扱うかの判定に用いる)
    /// - Returns: レスポンスボディ
    /// - Throws: `APIError`
    private func perform(_ request: URLRequest, requiresAuth: Bool) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let statusCode = httpResponse.statusCode
        if (200..<300).contains(statusCode) {
            return data
        }
        // ログインAPI等の認証不要なAPIの401は「パスワードが違う」等の意味のため，期限切れとして扱わない
        if statusCode == 401 && requiresAuth {
            onUnauthorized?()
            throw APIError.unauthorized
        }
        throw APIError.server(statusCode: statusCode, detail: Self.errorDetail(from: data))
    }

    /// レスポンスボディをデコードする．
    /// - Parameter data: レスポンスボディ
    /// - Returns: デコードした値
    /// - Throws: `APIError.decoding`
    private func decode<Response: Decodable>(_ data: Data) throws -> Response {
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }

    /// FastAPIのエラーレスポンス(`{"detail": "..."}`)からメッセージを取り出す．
    /// - Parameter data: レスポンスボディ
    /// - Returns: `detail`が文字列の場合はその値．検証エラー(422)のように配列の場合はnil．
    private static func errorDetail(from data: Data) -> String? {
        struct ErrorBody: Decodable {
            let detail: String
        }
        return try? JSONDecoder().decode(ErrorBody.self, from: data).detail
    }
}

/// サーバーが返す日時文字列を解釈する名前空間．
///
/// サーバーはUTCの日時をISO8601形式で返す．Pythonの`isoformat()`由来の
/// "+00:00"表記・マイクロ秒(小数6桁)を含む形式と，"Z"表記・小数なしの形式の両方を受け付ける．
/// タイムゾーンの表記がない場合は，サーバーの規約に従いUTCとみなす．
nonisolated enum ServerDate {
    /// 日時文字列を解釈する．
    /// - Parameter text: ISO8601形式の日時文字列(例: "2026-11-11T09:00:00.123456+00:00")
    /// - Returns: 解釈した日時．解釈できない場合はnil．
    static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601) {
            return date
        }
        return try? Date(text + "Z", strategy: .iso8601)
    }
}
