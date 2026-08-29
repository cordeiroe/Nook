// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TokenDeck",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenDeckCore", targets: ["TokenDeckCore"]),
        .executable(name: "tdprobe", targets: ["tdprobe"]),
        .executable(name: "tdauth", targets: ["tdauth"]),
        .executable(name: "TokenDeckApp", targets: ["TokenDeckApp"]),
    ],
    targets: [
        .target(
            name: "TokenDeckCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TokenDeckApp",
            dependencies: ["TokenDeckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "tdauth",
            dependencies: ["TokenDeckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "tdprobe",
            dependencies: ["TokenDeckCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
