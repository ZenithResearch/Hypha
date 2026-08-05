// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Hypha",
    platforms: [.macOS("26.4")],
    products: [
        .library(name: "HyphaCore", targets: ["HyphaCore"]),
        .executable(name: "Hypha", targets: ["Hypha"])
    ],
    dependencies: [],
    targets: [
        .binaryTarget(
            name: "MatrixSDKFFI",
            path: "Vendor/MatrixRustSDK/MatrixSDKFFI.xcframework.zip"
        ),
        .target(
            name: "MatrixRustSDK",
            dependencies: ["MatrixSDKFFI"],
            path: "Vendor/MatrixRustSDK/Sources/MatrixRustSDK"
        ),
        .target(
            name: "HyphaCore",
            dependencies: ["MatrixRustSDK"]
        ),
        .executableTarget(
            name: "Hypha",
            dependencies: ["HyphaCore"]
        ),
        .testTarget(
            name: "HyphaCoreTests",
            dependencies: [
                "HyphaCore",
                "MatrixRustSDK"
            ]
        )
    ]
)
