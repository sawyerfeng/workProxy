// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WorkProxy",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "WorkProxy", targets: ["WorkProxy"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "WorkProxyCore"),
        .executableTarget(name: "WorkProxy", dependencies: ["WorkProxyCore", .product(name: "Sparkle", package: "Sparkle")],
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "WorkProxyCoreTests", dependencies: ["WorkProxyCore"]),
        .testTarget(name: "WorkProxyTests", dependencies: ["WorkProxy"])
    ]
)
