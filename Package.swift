// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MakerGlance",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MakerGlance", targets: ["MakerPulse"]), .executable(name: "MakerGlanceProbe", targets: ["MakerPulseProbe"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "MakerPulseCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "MakerPulse", dependencies: ["MakerPulseCore"]),
        .executableTarget(name: "MakerPulseProbe", dependencies: ["MakerPulseCore"]),
        .testTarget(name: "MakerPulseCoreTests", dependencies: ["MakerPulseCore"])
    ]
)
