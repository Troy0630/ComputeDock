// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ComputeDock",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ComputeDock", targets: ["ComputeDock"]), .executable(name: "ComputeDockAskPass", targets: ["ComputeDockAskPass"])],
    targets: [
        .executableTarget(name: "ComputeDock", resources: [.copy("Resources/collector.py")]),
        .executableTarget(name: "ComputeDockAskPass"),
        .testTarget(name: "ComputeDockTests", dependencies: ["ComputeDock"])
    ]
)
