import AppKit
import SwiftUI

enum OLSTheme {
    static let background = Color(light: 0xF4F5F7, dark: 0x1C1D1F)
    static let surface = Color(light: 0xFFFFFF, dark: 0x2A2B2E)
    static let text = Color(light: 0x1A1C1E, dark: 0xF3F4F6)
    static let mutedText = Color(light: 0x5C6370, dark: 0xA0A6B0)
    static let border = Color(light: 0xD5D8DE, dark: 0x3E4248)
    static let accent = Color(light: 0x0F6B63, dark: 0x3DBEAF)
    static let success = Color(light: 0x1B7F4A, dark: 0x3DDC97)
    static let warning = Color(light: 0xA15C00, dark: 0xF0B429)
    static let error = Color(light: 0xB42318, dark: 0xF97066)
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let useDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = useDark ? dark : light
            let r = CGFloat((value >> 16) & 0xFF) / 255
            let g = CGFloat((value >> 8) & 0xFF) / 255
            let b = CGFloat(value & 0xFF) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }))
    }
}
