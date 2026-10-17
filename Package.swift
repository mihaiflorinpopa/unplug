// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unplug",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "unplug", targets: ["unplug"]),
        .executable(name: "UnplugApp", targets: ["UnplugApp"]),
        .library(name: "UnplugCore", targets: ["UnplugCore"]),
    ],
    targets: [
        .target(name: "UnplugCore"),
        .executableTarget(name: "unplug", dependencies: ["UnplugCore"]),
        .executableTarget(name: "UnplugApp", dependencies: ["UnplugCore"]),
        .testTarget(name: "UnplugCoreTests", dependencies: ["UnplugCore"]),
    ]
)
