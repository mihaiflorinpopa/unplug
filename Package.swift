// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Unplug",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "unplug", targets: ["unplug"]),
        .executable(name: "UnplugApp", targets: ["UnplugApp"]),
        .library(name: "UnplugCore", targets: ["UnplugCore"]),
    ],
    dependencies: [
        // Auto-updates for the menu bar app.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(name: "UnplugCore"),
        .executableTarget(name: "unplug", dependencies: ["UnplugCore"]),
        .executableTarget(
            name: "UnplugApp",
            dependencies: ["UnplugCore", .product(name: "Sparkle", package: "Sparkle")],
            // Sparkle.framework is copied into Unplug.app/Contents/Frameworks.
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "UnplugCoreTests", dependencies: ["UnplugCore"]),
    ]
)
