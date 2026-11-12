import Foundation

/// サーバーの疎通確認(`GET /health`)を行う名前空間．
enum ServerHealth {
    /// `GET /health`のレスポンスボディ．
    private struct HealthResponse: Decodable {
        let status: String
    }

    /// 疎通確認で発生するエラー．
    enum CheckError: LocalizedError {
        case badStatusCode(Int)
        case unexpectedBody

        var errorDescription: String? {
            switch self {
            case .badStatusCode(let code):
                "サーバーがHTTP \(code)を返しました．"
            case .unexpectedBody:
                "EchoMindサーバーの応答ではありません．"
            }
        }
    }

    /// 指定したサーバーの`GET /health`を呼び出し，`{"status": "ok"}`が返ることを確認する．
    /// - Parameter baseURL: サーバーのURL(例: https://echomind.example.com)
    /// - Throws: 通信エラー，`CheckError`
    static func check(baseURL: URL) async throws {
        var request = URLRequest(url: baseURL.appending(path: "health"))
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            throw CheckError.badStatusCode(httpResponse.statusCode)
        }
        guard let body = try? JSONDecoder().decode(HealthResponse.self, from: data), body.status == "ok" else {
            throw CheckError.unexpectedBody
        }
    }
}
