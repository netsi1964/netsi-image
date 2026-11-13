import CoreSupport
import Foundation
import Security

public enum KeychainError: Error, Equatable, Sendable, CustomStringConvertible {
    case interactionNotAllowed
    case authFailed
    case duplicate
    case emptyKey
    case unexpected(Int32)

    public var description: String {
        switch self {
        case .interactionNotAllowed:
            return "Nøglebundtet er låst. Lås din Mac op og prøv igen."
        case .authFailed:
            return "Adgang til nøglebundtet blev afvist."
        case .duplicate:
            return "Der findes allerede en nøgle. Slet den først."
        case .emptyKey:
            return "Nøglen må ikke være tom."
        case .unexpected(let status):
            return "Nøglebundtet returnerede fejlen \(status)."
        }
    }
}

public protocol KeychainStoring: Sendable {
    func readKey() throws -> String?
    func saveKey(_ key: String) throws
    func deleteKey() throws
}

/// Minimal abstraction so tests never touch the real Keychain.
public protocol KeychainBackend: Sendable {
    func read(service: String, account: String) -> (status: OSStatus, data: Data?)
    func write(service: String, account: String, data: Data) -> OSStatus
    func delete(service: String, account: String) -> OSStatus
}

public struct SecurityBackend: KeychainBackend {
    public init() {}

    public func read(service: String, account: String) -> (status: OSStatus, data: Data?) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        return (status, item as? Data)
    }

    public func write(service: String, account: String, data: Data) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return errSecSuccess }
        if updateStatus == errSecItemNotFound {
            var create = query
            create.merge(attributes) { _, new in new }
            return SecItemAdd(create as CFDictionary, nil)
        }
        return updateStatus
    }

    public func delete(service: String, account: String) -> OSStatus {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}

public struct KeychainStore: KeychainStoring {
    public static let service = "dk.netsi.image.openrouter"
    public static let account = "api-key"

    private let backend: any KeychainBackend
    private let service: String
    private let account: String

    public init(
        backend: any KeychainBackend = SecurityBackend(),
        service: String = KeychainStore.service,
        account: String = KeychainStore.account
    ) {
        self.backend = backend
        self.service = service
        self.account = account
    }

    public func readKey() throws -> String? {
        let result = backend.read(service: service, account: account)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess else { throw Self.map(result.status) }
        guard let data = result.data, let key = String(data: data, encoding: .utf8), !key.isEmpty else {
            return nil
        }
        return key
    }

    public func saveKey(_ key: String) throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw KeychainError.emptyKey }
        let status = backend.write(service: service, account: account, data: Data(trimmed.utf8))
        guard status == errSecSuccess else { throw Self.map(status) }
    }

    public func deleteKey() throws {
        let status = backend.delete(service: service, account: account)
        guard status == errSecSuccess else { throw Self.map(status) }
    }

    static func map(_ status: OSStatus) -> KeychainError {
        switch status {
        case errSecInteractionNotAllowed: return .interactionNotAllowed
        case errSecAuthFailed, errSecUserCanceled: return .authFailed
        case errSecDuplicateItem: return .duplicate
        default: return .unexpected(status)
        }
    }
}

public struct KeyState: Sendable, Equatable {
    public var hasKey: Bool
    public var maskedSuffix: String?
    public var readOnly: Bool
    public var message: String?
    /// Total spend in USD, from OpenRouter's key endpoint.
    public var usageUSD: Decimal?
    /// The key's credit limit, when one is set.
    public var limitUSD: Decimal?
    /// What is left of the limit, when one is set.
    public var remainingUSD: Decimal?

    public init(
        hasKey: Bool,
        maskedSuffix: String? = nil,
        readOnly: Bool = false,
        message: String? = nil,
        usageUSD: Decimal? = nil,
        limitUSD: Decimal? = nil,
        remainingUSD: Decimal? = nil
    ) {
        self.hasKey = hasKey
        self.maskedSuffix = maskedSuffix
        self.readOnly = readOnly
        self.message = message
        self.usageUSD = usageUSD
        self.limitUSD = limitUSD
        self.remainingUSD = remainingUSD
    }

    public static func resolve(key: String?) -> KeyState {
        guard let key, !key.isEmpty else {
            return KeyState(hasKey: false, readOnly: true, message: "Ingen nøgle. Katalog, parametre og bibliotek virker stadig.")
        }
        return KeyState(hasKey: true, maskedSuffix: String(key.suffix(4)))
    }

    public static func resolve(error: KeychainError) -> KeyState {
        KeyState(hasKey: false, readOnly: true, message: error.description)
    }
}

public struct AppSettings: Sendable, Equatable, Codable {
    public var defaultModelId: String?
    public var streamingEnabled: Bool
    public var hideInactive: Bool
    public var showUncertain: Bool
    public var appearance: String
    public var libraryRootPath: String?
    public var concurrentJobs: Int

    public init(
        defaultModelId: String? = "openai/gpt-image-2",
        streamingEnabled: Bool = true,
        hideInactive: Bool = true,
        showUncertain: Bool = false,
        appearance: String = "system",
        libraryRootPath: String? = nil,
        concurrentJobs: Int = 2
    ) {
        self.defaultModelId = defaultModelId
        self.streamingEnabled = streamingEnabled
        self.hideInactive = hideInactive
        self.showUncertain = showUncertain
        self.appearance = appearance
        self.libraryRootPath = libraryRootPath
        self.concurrentJobs = concurrentJobs
    }
}

public final class SettingsStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "dk.netsi.image.settings"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return settings
    }

    public func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
