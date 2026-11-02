import Foundation

public protocol PreferencesStoring: Sendable {
    func load() -> ScanPreferences
    func save(_ preferences: ScanPreferences)
}

public final class UserDefaultsPreferencesStore: PreferencesStoring, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "scanPreferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> ScanPreferences {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode(ScanPreferences.self, from: data)
        else {
            return ScanPreferences()
        }
        return decoded
    }

    public func save(_ preferences: ScanPreferences) {
        if let data = try? JSONEncoder().encode(preferences) {
            defaults.set(data, forKey: key)
        }
    }
}
