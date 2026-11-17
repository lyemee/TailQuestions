import Foundation
import Security

/// API 키는 macOS 키체인에 저장한다.
enum Keychain {
    private static let service = "com.lyemee.TailQuestions"
    private static let account = "anthropic-api-key"

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func load() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ key: String) {
        SecItemDelete(baseQuery as CFDictionary)
        guard !key.isEmpty else { return }
        var query = baseQuery
        query[kSecValueData as String] = Data(key.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }
}
