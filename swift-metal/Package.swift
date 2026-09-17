// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GanzFlicker",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GanzFlicker",
            path: "Sources/GanzFlicker"
        )
    ]
)
