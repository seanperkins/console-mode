// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ConsoleMode",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "ConsoleMode", targets: ["ConsoleMode"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "1.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "ConsoleMode",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/ConsoleMode"
        ),
        .testTarget(
            name: "ConsoleModeTests",
            dependencies: ["ConsoleMode"],
            path: "Tests/ConsoleModeTests"
        ),
    ]
)