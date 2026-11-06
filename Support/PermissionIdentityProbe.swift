// Separate synthetic keychain used only to verify continuity across two signed
// binaries. Never reads the user's FacePhys credential or login passwords.
import Foundation
import Security

func check(_ status: OSStatus, _ stage: String) {
    guard status == errSecSuccess else { fputs("\(stage): \(status)\n", stderr); exit(1) }
}
let args = CommandLine.arguments
guard args.count == 3 else { exit(2) }
var keychain: SecKeychain?
if args[1] == "write" {
    var secret = [UInt8](repeating: 0, count: 32)
    check(SecRandomCopyBytes(kSecRandomDefault, secret.count, &secret), "Generate fixture password")
    check(secret.withUnsafeBytes { SecKeychainCreate(args[2], UInt32($0.count), $0.baseAddress, false, nil, &keychain) }, "Create fixture keychain")
    let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "facepause-signing-continuity-test", kSecAttrAccount as String: "fixture",
        kSecValueData as String: Data("synthetic-fixture-only".utf8), kSecUseKeychain as String: keychain!]
    check(SecItemAdd(item as CFDictionary, nil), "Write fixture")
    print("A: synthetic keychain item created")
} else {
    check(SecKeychainOpen(args[2], &keychain), "Open fixture keychain")
    let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "facepause-signing-continuity-test", kSecAttrAccount as String: "fixture",
        kSecMatchSearchList as String: [keychain!] as CFArray,
        kSecReturnData as String: true, kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    var value: CFTypeRef?
    check(SecItemCopyMatching(query as CFDictionary, &value), "Read without interaction")
    guard (value as? Data) == Data("synthetic-fixture-only".utf8) else { exit(3) }
    #if PROBE_B
    print("B: different binary read item silently using the same signing identity")
    #else
    print("A: read item silently after relaunch")
    #endif
}
