// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenLANScanner",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenLANScannerCore", targets: ["OpenLANScannerCore"]),
        .executable(name: "OpenLANScanner", targets: ["OpenLANScanner"])
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
        .testTarget(
            name: "OpenLANScannerCoreTests",
            dependencies: ["OpenLANScannerCore"],
            path: "Tests/OpenLANScannerCoreTests"
        )
    ]
)
