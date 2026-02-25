// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "localclaw-mac-installer",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "localclaw-mac-installer", targets: ["localclaw-mac-installer"])
    ],
    targets: [
        .executableTarget(
            name: "localclaw-mac-installer",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "localclaw-mac-installerTests",
            dependencies: ["localclaw-mac-installer"]
        )
    ]
)
