// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Pico",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "Pico", targets: ["Pico"])],
    targets: [
        .executableTarget(
            name: "Pico", path: "Sources/Pico",
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])]),
        .testTarget(name: "PicoTests", dependencies: ["Pico"], path: "Tests/PicoTests"),
    ]
)
