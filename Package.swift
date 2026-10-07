// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "workNrelax",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "workNrelax", targets: ["workNrelax"]),
    ],
    targets: [
        .executableTarget(name: "workNrelax"),
        .testTarget(name: "workNrelaxTests", dependencies: ["workNrelax"]),
    ]
)
