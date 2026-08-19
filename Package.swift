// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AltTab",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "AltTab",
            path: "Sources/AltTab",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
