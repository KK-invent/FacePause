import Foundation
import Security
import FaceCore

@MainActor enum KeychainStore {
    private static let service = "local.facepause.credentials"
    private static let account = "facephys"
    // Only memory, never UserDefaults or a plaintext credentials file.
    private static var cached: Credentials?
    private static var authorizationBlocked = false
    private static var deepSeekCached: String?
    private static var deepSeekBlocked = false
    private static var deepSeekQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "deepseek"]
    }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }
    static func load(interactive: Bool = false) throws -> Credentials? {
        if let cached { return cached }
        if authorizationBlocked && !interactive { throw accessRequired() }
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        // Launches and scheduled work must never open an authentication dialog.
        q[kSecUseAuthenticationUI as String] = interactive ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        // kSecUseAuthenticationUI does not cover the file-based login keychain's ACL dialog,
        // so background reads also disable this process's keychain interaction for the call.
        let status = interactive ? SecItemCopyMatching(q as CFDictionary, &item) : withoutKeychainUI { SecItemCopyMatching(q as CFDictionary, &item) }
        if status == errSecItemNotFound { authorizationBlocked = false; return nil }
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
            authorizationBlocked = true
            throw accessRequired()
        }
        guard status == errSecSuccess, let data = item as? Data else {
            throw FaceError.message("钥匙串暂时不可用（\(status)），请在设置中检查授权。")
        }
        let credentials = try JSONDecoder().decode(Credentials.self, from: data)
        cached = credentials; authorizationBlocked = false
        return credentials
    }
    static func authorize() throws -> Credentials? {
        authorizationBlocked = false
        return try load(interactive: true)
    }
    static func clearMemoryCache() {
        cached = nil; authorizationBlocked = false
        deepSeekCached = nil; deepSeekBlocked = false
    }
    private static func withoutKeychainUI(_ body: () -> OSStatus) -> OSStatus {
        var previous = DarwinBoolean(true)
        SecKeychainGetUserInteractionAllowed(&previous)
        SecKeychainSetUserInteractionAllowed(false)
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return body()
    }
    private static func accessRequired() -> FaceError {
        .message("钥匙串需要首次授权或解锁。请到设置点击“授权钥匙串访问”，在系统窗口选择“始终允许”；后台不会反复弹窗。")
    }
    static func save(_ credentials: Credentials) throws {
        guard credentials.valid else { throw FaceError.message("Key ID 和 Secret 都需要填写。") }
        let data = try JSONEncoder().encode(credentials)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var q = query; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FaceError.message("钥匙串保存失败（\(status)）。") }
        cached = credentials; authorizationBlocked = false
    }
    static func loadDeepSeek(interactive: Bool = false) throws -> String? {
        if let deepSeekCached { return deepSeekCached }
        if deepSeekBlocked && !interactive { throw deepSeekAccessRequired() }
        var q = deepSeekQuery
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        q[kSecUseAuthenticationUI as String] = interactive ? kSecUseAuthenticationUIAllow : kSecUseAuthenticationUIFail
        var item: CFTypeRef?
        let status = interactive ? SecItemCopyMatching(q as CFDictionary, &item)
            : withoutKeychainUI { SecItemCopyMatching(q as CFDictionary, &item) }
        if status == errSecItemNotFound { deepSeekBlocked = false; return nil }
        if [errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled].contains(status) {
            deepSeekBlocked = true
            throw deepSeekAccessRequired()
        }
        guard status == errSecSuccess, let data = item as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            throw FaceError.message("DeepSeek 钥匙串读取失败（\(status)）。")
        }
        deepSeekCached = key; deepSeekBlocked = false
        return key
    }
    static func saveDeepSeek(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.hasPrefix("sk-"), key.count >= 20, key.count <= 256,
              key.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw FaceError.message("请填写有效的 DeepSeek API Key。")
        }
        let data = Data(key.utf8)
        var status = SecItemUpdate(deepSeekQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = deepSeekQuery; q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(q as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw FaceError.message("DeepSeek Key 保存失败（\(status)）。") }
        deepSeekCached = key; deepSeekBlocked = false
    }
    private static func deepSeekAccessRequired() -> FaceError {
        .message("DeepSeek 钥匙串需要授权或解锁，请在设置中点击“授权 DeepSeek 钥匙串访问”。")
    }
}
