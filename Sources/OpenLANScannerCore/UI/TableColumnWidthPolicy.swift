import Foundation

/// Shared rules for results-table column width persistence.
/// Prevents `lastColumnOnly` fill widths (often 700+) from poisoning the next launch.
public enum TableColumnWidthPolicy {
    public static let maxPersisted: Double = 260
    public static let minimum: Double = 56

    public static func resolved(saved: Double, defaultWidth: Double) -> Double {
        guard saved >= minimum, saved <= maxPersisted else { return defaultWidth }
        return saved
    }

    public static func shouldPersist(_ width: Double) -> Bool {
        width >= minimum && width <= maxPersisted
    }
}
