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
        .package(url: "https://github.com/soto-project/soto.git", exact: "7.15.0"),
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
        // S3 client data layer. Isolates the Soto AWS SDK (S3 only) from SimpletonCore and the app;
        // reuses the swift-nio / async-http-client / swift-crypto tree already vendored by the SQL NIO
        // drivers, so no new C runtime is pulled in.
        .target(
            name: "SimpletonS3",
            dependencies: [
                "SimpletonCore",
                .product(name: "SotoS3", package: "soto"),
            ]
        ),
        // AMQP (RabbitMQ) management client. Talks to the RabbitMQ Management HTTP API over
        // URLSession/Foundation only — no AMQP client library, no third-party dependency.
        .target(
            name: "SimpletonAMQP",
            dependencies: ["SimpletonCore"]
        ),
        .executableTarget(
            name: "Simpleton",
            dependencies: [
                "SimpletonCore", "SimpletonSQL", "SimpletonS3", "SimpletonAMQP", "SwiftTerm",
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
            dependencies: ["SimpletonCore", "SimpletonSQL", "SimpletonS3", "SimpletonAMQP"],
            path: "Tests/CoreChecks"
        ),
    ]
)
