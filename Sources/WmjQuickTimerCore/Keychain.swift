import Foundation
import Security

/// Minimal generic-password storage for the API tokens. Both tokens live in a
/// single item: macOS prompts once per keychain item after the app's signature
/// changes, so two items meant two prompts.
public enum Keychain {
    static let service = "com.moosylvania.WmjQuickTimer"
    private static let account = "tokens"

    public struct Tokens: Codable, Sendable {
        public var company: String
        public var user: String
        public init(company: String, user: String) {
            self.company = company
            self.user = user
        }
    }

    public static func tokens() -> Tokens? {
        if let json = get(account), let data = json.data(using: .utf8),
           let tokens = try? JSONDecoder().decode(Tokens.self, from: data) {
            return tokens
        }
        // One-time migration from the old per-token items.
        guard let company = get("companyToken"), let user = get("userToken") else { return nil }
        let tokens = Tokens(company: company, user: user)
        save(tokens)
        delete("companyToken")
        delete("userToken")
        return tokens
    }

    public static func save(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        set(String(decoding: data, as: UTF8.self), account: account)
    }

    public static func set(_ value: String, account: String) {
        delete(account)
        guard !value.isEmpty else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    public static func get(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
