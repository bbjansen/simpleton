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
    ],
    targets: [
        .target(
            name: "SimpletonCore",
            dependencies: ["SwiftTerm"]
        ),
        .executableTarget(
            name: "Simpleton",
            dependencies: ["SimpletonCore", "SwiftTerm"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "SimpletonCoreTests",
            dependencies: ["SimpletonCore"]
        ),
    ]
)
