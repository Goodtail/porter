// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Porter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Porter",
            path: "Sources/Porter",
            swiftSettings: [
                .swiftLanguageMode(.v5)
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
