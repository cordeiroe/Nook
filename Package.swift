// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Nook",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "NookCore", targets: ["NookCore"]),
        .executable(name: "nookprobe", targets: ["nookprobe"]),
        .executable(name: "nookauth", targets: ["nookauth"]),
        .executable(name: "NookApp", targets: ["NookApp"]),
    ],
    targets: [
        .target(
            name: "NookCore",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "NookApp",
            dependencies: ["NookCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "nookauth",
            dependencies: ["NookCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "nookprobe",
            dependencies: ["NookCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
