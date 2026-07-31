// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "ProcessGuardian",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ProcessGuardian",
            path: "Sources/ProcessGuardian"
        )
    ]
)
