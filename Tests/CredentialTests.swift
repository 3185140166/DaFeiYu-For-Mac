import Foundation
import Security
import LocalAuthentication

enum TestLanguage { case simplifiedChinese, traditionalChinese, english }
@MainActor final class LocalizationManager {
    static let shared = LocalizationManager()
    var resolved: TestLanguage = .english
}

@main struct CredentialTests {
    @MainActor static func main() throws {
        var reads = 0
        var status: OSStatus = errSecSuccess
        var writeStatus: OSStatus = errSecSuccess
        var data = Data("fixture-one".utf8)
        var interactive = false
        let operations = ChatKeychainOperations(
            read: { query, result in
                reads += 1
                if let context = query[kSecUseAuthenticationContext as String] as? LAContext {
                    precondition(context.interactionNotAllowed, "Ordinary reads must not prompt")
                    interactive = false
                } else { interactive = true }
                result = data as CFData
                return status
            },
            update: { _, value in if writeStatus == errSecSuccess { data = value }; return writeStatus },
            add: { _ in errSecSuccess },
            delete: { _ in writeStatus })
        let vault = ChatCredentialVault(operations: operations)
        let first = try vault.read(endpoint: "one")
        precondition(first == "fixture-one" && reads == 1 && !interactive)
        _ = try vault.read(endpoint: "one")
        precondition(reads == 1, "Cached reads should not touch Keychain")
        _ = try vault.read(endpoint: "two")
        precondition(reads == 2, "Endpoints must not share credentials")
        precondition(vault.matches("fixture-one", endpoint: "one"))
        vault.clear()
        status = errSecInteractionNotAllowed
        do { _ = try vault.read(endpoint: "one"); fatalError("Unexpected access") }
        catch { precondition((error as NSError).code == Int(errSecInteractionNotAllowed)) }
        status = errSecSuccess
        _ = try vault.read(endpoint: "one", allowInteraction: true)
        precondition(interactive && reads == 4, "An authorization failure must remain retryable")
        try vault.save("fixture-two", endpoint: "one")
        let beforeRead = reads
        let updated = try vault.read(endpoint: "one")
        precondition(updated == "fixture-two" && reads == beforeRead)
        precondition(!vault.matches("fixture-one", endpoint: "one"), "Stale balance results must be discarded")
        writeStatus = errSecAuthFailed
        do { try vault.save("fixture-three", endpoint: "one"); fatalError("Save should fail") }
        catch { precondition((error as NSError).code == Int(errSecAuthFailed)) }
        precondition(!vault.matches("fixture-two", endpoint: "one"), "Failed writes invalidate cached credentials")
        writeStatus = errSecSuccess
        try vault.save("", endpoint: "one")
        precondition(!vault.matches("fixture-two", endpoint: "one"))
        vault.clear()
        status = errSecItemNotFound
        let missing = try vault.read(endpoint: "missing")
        precondition(missing.isEmpty)
        status = errSecSuccess
        let recovered = try vault.read(endpoint: "missing")
        precondition(!recovered.isEmpty, "Missing items must not be cached")
        vault.clear()
        data = Data([0xff])
        do { _ = try vault.read(endpoint: "invalid"); fatalError("Invalid UTF-8 accepted") }
        catch { precondition((error as NSError).code == Int(errSecDecode)) }
        print("PASS: silent reads, explicit authorization, per-endpoint memory cache, save/delete invalidation, retry after failure, lock clearing, invalid data")
    }
}
