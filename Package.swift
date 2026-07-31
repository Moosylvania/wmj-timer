// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WmjQuickTimer",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "WmjQuickTimerCore"),
        .executableTarget(name: "WmjQuickTimer", dependencies: ["WmjQuickTimerCore"]),
        .testTarget(name: "WmjQuickTimerCoreTests", dependencies: ["WmjQuickTimerCore"]),
    ]
)
