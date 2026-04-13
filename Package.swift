// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoiceDictation",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "VoiceDictation",
            path: "Sources/VoiceDictation",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreGraphics"),
            ]
        )
    ]
)
