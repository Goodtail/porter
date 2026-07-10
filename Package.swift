// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Porter",
    // Source strings are Korean; unsupported languages fall back to English.
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-update for direct (non-App-Store) distribution.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "Porter",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/Porter",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                // Sparkle.framework lives in Porter.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "PorterTests",
            dependencies: ["Porter"],
            path: "Tests/PorterTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
