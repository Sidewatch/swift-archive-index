// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ArchiveIndex",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ArchiveIndex", targets: ["ArchiveIndex"])
    ],
    targets: [
        .target(name: "ArchiveIndex", path: "Sources", swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "ArchiveIndexTests", dependencies: ["ArchiveIndex"], path: "Tests"),
    ]
)
