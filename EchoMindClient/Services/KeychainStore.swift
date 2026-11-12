import Foundation
import Security

/// Keychainに文字列を保存・取得・削除する名前空間．
///
/// 保存した値は端末の初回のロック解除後であれば読み出せる設定とする
/// (画面ロック中のバックグラウンド送信でアクセストークンを使用するため)．
nonisolated enum KeychainStore {
    /// Keychainの項目を区別するサービス名．
    private static let service = "EchoMind"

    /// Keychainの操作で発生するエラー．
    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                "Keychainへの保存に失敗しました(OSStatus: \(status))．"
            }
        }
    }

    /// 文字列をKeychainに保存する．同じアカウント名の値が既にあれば上書きする．
    /// - Parameters:
    ///   - value: 保存する文字列
    ///   - account: 項目を識別するアカウント名(例: "accessToken")
    /// - Throws: `KeychainError`
    static func save(_ value: String, account: String) throws {
        delete(account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    /// Keychainから文字列を取得する．
    /// - Parameter account: 項目を識別するアカウント名
    /// - Returns: 保存されている文字列．存在しない場合はnil．
    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Keychainから項目を削除する．項目が存在しない場合は何もしない．
    /// - Parameter account: 項目を識別するアカウント名
    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
