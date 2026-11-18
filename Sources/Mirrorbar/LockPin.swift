import Foundation
import Security

/// The phone's lock-screen PIN, kept in the Mac's login keychain (never in
/// UserDefaults or the log). Only the toolbar's unlock button reads it.
enum LockPin {
    private static let service = "io.github.liangjh0712.mirrorbar"
    private static let account = "lock-screen-pin"

    /// Digits and letters only: `input text` on the phone takes them as typed.
    static func isValid(_ pin: String) -> Bool {
        pin.range(of: #"^[A-Za-z0-9]{4,32}$"#, options: .regularExpression) != nil
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static var isSet: Bool {
        var q = query
        q[kSecReturnAttributes as String] = true
        return SecItemCopyMatching(q as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ pin: String) -> Bool {
        guard isValid(pin) else { return false }
        SecItemDelete(query as CFDictionary)
        var q = query
        q[kSecValueData as String] = Data(pin.utf8)
        q[kSecAttrLabel as String] = "Mirrorbar 手机锁屏密码"
        q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }
}
