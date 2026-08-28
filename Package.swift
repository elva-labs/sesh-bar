// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "sesh-bar",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift", from: "1.0.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "AwseshCore",
            dependencies: [
                .product(name: "AWSSSO", package: "aws-sdk-swift"),
                .product(name: "AWSSSOOIDC", package: "aws-sdk-swift"),
            ],
            path: "Sources/AwseshCore"
        ),
        .executableTarget(
            name: "SeshBar",
            dependencies: [
                "AwseshCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/SeshBar"
        ),
        .testTarget(name: "AwseshCoreTests", dependencies: ["AwseshCore"], path: "Tests/AwseshCoreTests"),
    ]
)
