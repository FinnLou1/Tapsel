// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tapsel",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Tapsel",
            path: "Sources/Tapsel"
        )
    ]
)
