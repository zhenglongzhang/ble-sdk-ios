// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZnhaasBleSDK",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "ZnhaasBleSDK",
            targets: ["ZnhaasBleSDK"]
        )
    ],
    targets: [
        .target(
            name: "ZnhaasBleSDK",
            path: "Sources/ZnhaasBleSDK"
        ),
        .testTarget(
            name: "ZnhaasBleSDKTests",
            dependencies: ["ZnhaasBleSDK"],
            path: "Tests/ZnhaasBleSDKTests"
        )
    ]
)

