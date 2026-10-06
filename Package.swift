// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "github-pr-richlinks",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GitHubPRRichLinks"),
        .executableTarget(
            name: "github-pr-richlinks",
            dependencies: ["GitHubPRRichLinks"],
            path: "Sources/github-pr-richlinks"
        ),
        .testTarget(
            name: "GitHubPRRichLinksTests",
            dependencies: ["GitHubPRRichLinks"]
        ),
    ]
)
