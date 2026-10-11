// swift-tools-version: 5.9
// LosttyRemote: SSH and tmux-over-SSH for Lostty Mobile, shared by the Mac
// debug window and the iPhone app. No GhosttyKit dependency.
import PackageDescription

let package = Package(
    name: "LosttyRemote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LosttyRemote", targets: ["LosttyRemote"]),
    ],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel", exact: "0.12.1"),
    ],
    targets: [
        .target(
            name: "LosttyRemote",
            dependencies: [.product(name: "Citadel", package: "Citadel")]
        ),
        .testTarget(
            name: "LosttyRemoteTests",
            dependencies: [
                "LosttyRemote",
                .product(name: "Citadel", package: "Citadel"),
            ]
        ),
    ]
)
