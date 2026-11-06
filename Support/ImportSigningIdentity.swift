// Local signing setup helper. Private material arrives only over stdin and is
// imported directly into the login keychain. No credentials are printed/saved.
import Foundation
import Security

func check(_ status: OSStatus, _ stage: String) {
    guard status == errSecSuccess else {
        fputs("\(stage) failed (\(status))\n", stderr); exit(1)
    }
}
struct Input: Decodable { let p12: String; let passphrase: String }
let input = try JSONDecoder().decode(Input.self, from: FileHandle.standardInput.readDataToEndOfFile())
guard let bytes = Data(base64Encoded: input.p12) else { exit(2) }
var keychain: SecKeychain?
let login = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Keychains/login.keychain-db").path
check(SecKeychainOpen(login, &keychain), "Open login keychain")
var application: SecTrustedApplication?
check(SecTrustedApplicationCreateFromPath("/usr/bin/codesign", &application), "Identify codesign")
var access: SecAccess?
check(SecAccessCreate("FacePause Local Signing" as CFString, [application!] as CFArray, &access), "Create signing-key access")
let options: [String: Any] = [
    kSecImportExportPassphrase as String: input.passphrase,
    kSecImportExportKeychain as String: keychain!,
    kSecImportExportAccess as String: access!
]
var items: CFArray?
check(SecPKCS12Import(bytes as CFData, options as CFDictionary, &items), "Import signing identity")
print("Local signing identity imported; no system trust settings changed.")
