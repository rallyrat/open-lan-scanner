import Foundation

/// Locates OpenLANScannerCore packaged resources without touching `Bundle.module`.
///
/// SwiftPM's generated `Bundle.module` accessor can `fatalError` when the app is launched
/// from a DMG/release layout that does not match the build-time candidate paths. Launch
/// must survive that and fall back to the embedded OUI map.
enum BundledResources {
    static let resourceBundleName = "OpenLANScanner_OpenLANScannerCore"

    /// URL of the bundled `oui-sample.csv`, if present on disk.
    static func ouiSampleCSVURL() -> URL? {
        let fileManager = FileManager.default
        for root in resourceRoots() {
            for relative in [
                "OUI/oui-sample.csv",
                "Contents/Resources/OUI/oui-sample.csv",
                "oui-sample.csv",
                "Contents/Resources/oui-sample.csv"
            ] {
                let url = root.appendingPathComponent(relative)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }

        // Last resort: ask any successfully constructed bundle (never Bundle.module).
        for bundle in loadableResourceBundles() {
            if let url = bundle.url(forResource: "oui-sample", withExtension: "csv", subdirectory: "OUI")
                ?? bundle.url(forResource: "oui-sample", withExtension: "csv") {
                return url
            }
        }
        return nil
    }

    private static func resourceRoots() -> [URL] {
        var roots: [URL] = []
        let main = Bundle.main

        if let resources = main.resourceURL {
            roots.append(resources.appendingPathComponent("\(resourceBundleName).bundle"))
            roots.append(resources) // direct OUI/ copy into app Resources
        }
        // Packager also places the SPM bundle next to the executable.
        if let macOS = main.executableURL?.deletingLastPathComponent() {
            roots.append(macOS.appendingPathComponent("\(resourceBundleName).bundle"))
        }
        return roots
    }

    private static func loadableResourceBundles() -> [Bundle] {
        resourceRoots().compactMap { Bundle(url: $0) }
    }
}
