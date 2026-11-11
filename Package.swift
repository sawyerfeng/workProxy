// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkProxy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WorkProxy", targets: ["WorkProxy"])],
    targets: [
        .target(name: "WorkProxyCore"),
        .executableTarget(name: "WorkProxy", dependencies: ["WorkProxyCore"]),
        .testTarget(name: "WorkProxyCoreTests", dependencies: ["WorkProxyCore"]),
        .testTarget(name: "WorkProxyTests", dependencies: ["WorkProxy"])
    ]
)
