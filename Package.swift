// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Simpleton",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SimpletonCore", targets: ["SimpletonCore"]),
        .executable(name: "Simpleton", targets: ["Simpleton"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
        .package(url: "https://github.com/vapor/postgres-nio.git", exact: "1.33.1"),
        .package(url: "https://github.com/vapor/mysql-nio.git", exact: "1.9.1"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "SimpletonCore",
            dependencies: ["SwiftTerm"]
        ),
        // SQL client data layer. Isolates the heavy NIO drivers from SimpletonCore and the app.
        .target(
            name: "SimpletonSQL",
            dependencies: [
                "SimpletonCore",
                .product(name: "PostgresNIO", package: "postgres-nio"),
                .product(name: "MySQLNIO", package: "mysql-nio"),
            ]
        ),
        // SFTP client data layer. Isolates the SwiftNIO-SSH / Citadel stack from SimpletonCore and the app.
        .target(
            name: "SimpletonSFTP",
            dependencies: [
                "SimpletonCore",
                .product(name: "Citadel", package: "Citadel"),
            ]
        ),
        .executableTarget(
            name: "Simpleton",
            dependencies: [
                "SimpletonCore", "SimpletonSQL", "SimpletonSFTP", "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("NaturalLanguage")]
        ),
        .testTarget(
            name: "SimpletonCoreTests",
            dependencies: ["SimpletonCore"]
        ),
        // No-Xcode check runner: XCTest/swift-testing are unavailable on this machine,
        // so runnable checks live in a plain executable target (see Tests/CoreChecks).
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["SimpletonCore", "SimpletonSQL", "SimpletonSFTP"],
            path: "Tests/CoreChecks"
        ),
    ]
)
