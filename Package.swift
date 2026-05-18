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
    ],
    targets: [
        .target(
            name: "SimpletonCore",
            dependencies: ["SwiftTerm"]
        ),
        .executableTarget(
            name: "Simpleton",
            dependencies: ["SimpletonCore", "SwiftTerm", .product(name: "Sparkle", package: "Sparkle")],
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("NaturalLanguage")]
        ),
        .testTarget(
            name: "SimpletonCoreTests",
            dependencies: ["SimpletonCore"]
        ),
    ]
)
