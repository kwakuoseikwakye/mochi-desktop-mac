// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MochiMac",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MochiMac", targets: ["MochiMac"])],
    targets: [
        .target(name: "MochiCore"),
        .executableTarget(name: "MochiMac", dependencies: ["MochiCore"],
                          resources: [.copy("Resources")]),
        .testTarget(name: "MochiCoreTests", dependencies: ["MochiCore"])
    ]
)
