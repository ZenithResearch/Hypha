// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZenithMacOSClient",
    platforms: [.macOS("26.4")],
    products: [
        .library(name: "ZenithMacOSClientCore", targets: ["ZenithMacOSClientCore"]),
        .executable(name: "ZenithMacOSClient", targets: ["ZenithMacOSClient"])
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
            name: "ZenithMacOSClientCore",
            dependencies: ["MatrixRustSDK"]
        ),
        .executableTarget(
            name: "ZenithMacOSClient",
            dependencies: ["ZenithMacOSClientCore"]
        ),
        .testTarget(
            name: "ZenithMacOSClientCoreTests",
            dependencies: [
                "ZenithMacOSClientCore",
                "MatrixRustSDK"
            ]
        )
    ]
)
