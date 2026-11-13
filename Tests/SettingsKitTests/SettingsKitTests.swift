import Foundation
import Security
import Testing

@testable import SettingsKit

final class FakeKeychain: KeychainBackend, @unchecked Sendable {
    var storage: [String: Data] = [:]
    var nextStatus: OSStatus?
    private let lock = NSLock()

    func read(service: String, account: String) -> (status: OSStatus, data: Data?) {
        lock.lock(); defer { lock.unlock() }
        if let status = nextStatus { return (status, nil) }
        let key = "\(service)|\(account)"
        guard let data = storage[key] else { return (errSecItemNotFound, nil) }
        return (errSecSuccess, data)
    }

    func write(service: String, account: String, data: Data) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        if let status = nextStatus { return status }
        storage["\(service)|\(account)"] = data
        return errSecSuccess
    }

    func delete(service: String, account: String) -> OSStatus {
        lock.lock(); defer { lock.unlock() }
        if let status = nextStatus { return status }
        storage.removeValue(forKey: "\(service)|\(account)")
        return errSecSuccess
    }
}

@Suite("Keychain")
struct KeychainTests {
    @Test("Round-trips a key and deletes it")
    func roundTrip() throws {
        let backend = FakeKeychain()
        let store = KeychainStore(backend: backend)

        #expect(try store.readKey() == nil)
        try store.saveKey("  sk-or-test-1234  ")
        #expect(try store.readKey() == "sk-or-test-1234")

        try store.deleteKey()
        #expect(try store.readKey() == nil)
    }

    @Test("Rejects an empty key")
    func emptyKey() {
        let store = KeychainStore(backend: FakeKeychain())
        #expect(throws: KeychainError.emptyKey) {
            try store.saveKey("   ")
        }
    }

    @Test("Locked or denied Keychain degrades to guidance")
    func lockedKeychain() {
        let backend = FakeKeychain()
        backend.nextStatus = errSecInteractionNotAllowed
        let store = KeychainStore(backend: backend)

        do {
            _ = try store.readKey()
            Issue.record("Expected an error")
        } catch let error as KeychainError {
            #expect(error == .interactionNotAllowed)
            let state = KeyState.resolve(error: error)
            #expect(state.readOnly)
            #expect(state.message?.contains("låst") == true)
        } catch {
            Issue.record("Wrong error: \(error)")
        }

        backend.nextStatus = errSecAuthFailed
        do {
            _ = try store.readKey()
            Issue.record("Expected an error")
        } catch let error as KeychainError {
            #expect(error == .authFailed)
        } catch {
            Issue.record("Wrong error: \(error)")
        }
    }

    @Test("Key state never exposes the full key")
    func maskedState() {
        let state = KeyState.resolve(key: "sk-or-v1-abcdefgh1234")
        #expect(state.hasKey)
        #expect(state.maskedSuffix == "1234")
        #expect(state.readOnly == false)

        let missing = KeyState.resolve(key: nil)
        #expect(!missing.hasKey)
        #expect(missing.readOnly)
    }
}

@Suite("Settings")
struct SettingsStoreTests {
    @Test("Round-trips settings through UserDefaults")
    func roundTrip() {
        let suite = "dk.netsi.image.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = SettingsStore(defaults: defaults)
        var settings = store.load()
        #expect(settings.streamingEnabled)

        settings.streamingEnabled = false
        settings.showUncertain = true
        settings.libraryRootPath = "/tmp/library"
        store.save(settings)

        let reloaded = SettingsStore(defaults: defaults).load()
        #expect(reloaded == settings)
    }
}
