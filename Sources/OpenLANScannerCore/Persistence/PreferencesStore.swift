import Foundation

public protocol PreferencesStoring: Sendable {
    func load() -> ScanPreferences
    func save(_ preferences: ScanPreferences)
    func saveThrowing(_ preferences: ScanPreferences) throws
}

public enum PreferencesStoreError: LocalizedError {
    case encodeFailed
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .encodeFailed:
            return "Could not encode preferences."
        case .writeFailed(let detail):
            return "Could not write preferences: \(detail)"
        }
    }
}

public final class UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "scanPreferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ScanPreferences {
        guard let data = defaults.data(forKey: key) else {
            return ScanPreferences()
        }
        do {
            let decoded = try JSONDecoder().decode(ScanPreferences.self, from: data)
            return ScanPreferences.validated(decoded)
        } catch {
            // Keep defaults rather than crashing on malformed stored prefs.
            return ScanPreferences()
        }
    }

    public func save(_ preferences: ScanPreferences) {
        try? saveThrowing(preferences)
    }

    public func saveThrowing(_ preferences: ScanPreferences) throws {
        var normalized = preferences
        normalized.normalize()
        guard let data = try? JSONEncoder().encode(normalized) else {
            throw PreferencesStoreError.encodeFailed
        }
        defaults.set(data, forKey: key)
    }
}
