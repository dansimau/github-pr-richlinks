// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "github-pr-richlinks",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "github-pr-richlinks",
            path: "Sources/github-pr-richlinks"
        ),
    ]
)
