// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Dedupper",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DedupperCore", targets: ["DedupperCore"]),
        .executable(name: "Dedupper", targets: ["DedupperApp"])
    ],
    targets: [
        .target(name: "DedupperCore"),
        .executableTarget(name: "DedupperApp", dependencies: ["DedupperCore"]),
        .testTarget(name: "DedupperCoreTests", dependencies: ["DedupperCore"]),
        .testTarget(name: "DedupperAppTests", dependencies: ["DedupperApp", "DedupperCore"])
    ]
)
