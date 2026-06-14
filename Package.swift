// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Lumen",
            path: "Sources/Lumen",
            swiftSettings: [
                // Mixed @MainActor AppKit/SwiftUI + plain Mach sampling code.
                // Swift 5 language mode keeps concurrency checking pragmatic.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
