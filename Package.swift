// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "sesh-bar",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "AwseshCore", path: "Sources/AwseshCore"),
        .testTarget(name: "AwseshCoreTests", dependencies: ["AwseshCore"], path: "Tests/AwseshCoreTests"),
    ]
)
