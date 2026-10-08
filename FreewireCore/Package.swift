// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FreewireCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FreewireCore", targets: ["FreewireCore"]),
    ],
    targets: [
        .target(name: "FreewireCore"),
        .testTarget(name: "FreewireCoreTests", dependencies: ["FreewireCore"]),
    ]
)
