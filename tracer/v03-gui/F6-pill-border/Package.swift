// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "F6PillDemo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "F6PillDemo",
            path: "Sources",
            swiftSettings: []
        ),
    ]
)
