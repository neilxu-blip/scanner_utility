// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScannerUtility",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ScannerUtility", targets: ["ScannerUtility"]),
        .library(name: "ScannerCore", targets: ["ScannerCore"])
    ],
    targets: [
        .target(name: "ScannerCore"),
        .executableTarget(name: "ScannerUtility", dependencies: ["ScannerCore"]),
        .testTarget(name: "ScannerCoreTests", dependencies: ["ScannerCore"])
    ]
)
