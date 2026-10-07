// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "workNrelax",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "workNrelax", targets: ["workNrelax"]),
    ],
    targets: [
        .executableTarget(
            name: "workNrelax",
            exclude: ["Resources/AppIcon.icns", "Resources/AppIcon-preview.png"]
        ),
        .testTarget(name: "workNrelaxTests", dependencies: ["workNrelax"]),
    ]
)
