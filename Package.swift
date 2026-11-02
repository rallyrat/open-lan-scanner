// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenLANScanner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenLANScannerCore", targets: ["OpenLANScannerCore"]),
        .executable(name: "OpenLANScanner", targets: ["OpenLANScanner"]),
        // Dev-only sanitizer harness — not packaged into the app bundle.
        .executable(name: "OLSParserSanitizerHarness", targets: ["OLSParserSanitizerHarness"])
    ],
    targets: [
        .target(
            name: "OpenLANScannerCore",
            dependencies: [],
            path: "Sources/OpenLANScannerCore",
            resources: [
                .copy("Resources/OUI")
            ]
        ),
        .executableTarget(
            name: "OpenLANScanner",
            dependencies: ["OpenLANScannerCore"],
            path: "Sources/OpenLANScanner"
        ),
        // C-only ASan positive-control fixture (never linked into the app).
        .target(
            name: "OLSAsanPositiveControl",
            path: "Tools/AsanPositiveControl",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "OLSParserSanitizerHarness",
            dependencies: ["OpenLANScannerCore", "OLSAsanPositiveControl"],
            path: "Tools/ParserSanitizerHarness",
            exclude: ["README.md"]
        ),
        .testTarget(
            name: "OpenLANScannerCoreTests",
            dependencies: ["OpenLANScannerCore"],
            path: "Tests/OpenLANScannerCoreTests"
        )
    ]
)
