import AppKit
import SwiftUI

enum OLSTheme {
    // MARK: - Color tokens (adaptive light/dark)

    static let background = Color(light: 0xF4F5F7, dark: 0x1C1D1F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2B2E)
    static let text = Color(light: 0x1A1C1E, dark: 0xF3F4F6)
    static let mutedText = Color(light: 0x5C6370, dark: 0xA0A6B0)
    static let border = Color(light: 0xD5D8DE, dark: 0x3E4248)
    static let accent = Color(light: 0x0F6B63, dark: 0x3DBEAF)
    static let onAccent = Color(light: 0xFFFFFF, dark: 0x062E2A)
    static let success = Color(light: 0x1B7F4A, dark: 0x3DDC97)
    static let warning = Color(light: 0xA15C00, dark: 0xF0B429)
    static let error = Color(light: 0xB42318, dark: 0xF97066)
    static let offline = Color(light: 0x8B919A, dark: 0x6B7280)

    // MARK: - Layout tokens (points)

    /// Outer content insets for panes and sheets.
    static let contentInset: CGFloat = 16
    /// Tight gaps between related controls in a group.
    static let controlGap: CGFloat = 8
    /// Spacing between related content blocks.
    static let relatedGap: CGFloat = 12
    /// Spacing between distinct toolbar groups.
    static let toolbarGroupGap: CGFloat = 16
    /// Vertical spacing between inspector sections.
    static let inspectorSectionGap: CGFloat = 20
    /// Default results-table row height.
    static let tableRowHeight: CGFloat = 28
    /// Compact results-table row height.
    static let tableRowHeightCompact: CGFloat = 22
    /// Default table body text size.
    static let tableFontSize: CGFloat = 13
    /// Compact table body text size.
    static let tableFontSizeCompact: CGFloat = 12
    /// Inspector pane width.
    static let inspectorMinWidth: CGFloat = 300
    static let inspectorIdealWidth: CGFloat = 320
    static let inspectorMaxWidth: CGFloat = 360
    /// Default / minimum window sizes after toolbar adaptability work.
    static let windowMinWidth: CGFloat = 920
    static let windowMinHeight: CGFloat = 560
    static let windowDefaultWidth: CGFloat = 1120
    static let windowDefaultHeight: CGFloat = 700

    // MARK: - AppKit status colors (dynamic for table cells)

    static var statusRespondedNSColor: NSColor {
        NSColor(name: nil, dynamicProvider: { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            // Slightly desaturated on dark so selected/alternating rows stay readable.
            return dark
                ? NSColor(srgbRed: 0.35, green: 0.82, blue: 0.58, alpha: 1)
                : NSColor(srgbRed: 0.106, green: 0.498, blue: 0.290, alpha: 1)
        })
    }

    static var statusNoResponseNSColor: NSColor { .secondaryLabelColor }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let useDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = useDark ? dark : light
            let r = CGFloat((value >> 16) & 0xFF) / 255
            let g = CGFloat((value >> 8) & 0xFF) / 255
            let b = CGFloat(value >> 0 & 0xFF) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }))
    }
}
