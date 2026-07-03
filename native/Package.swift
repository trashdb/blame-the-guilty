// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BlameTheGuilty",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BlameTheGuilty",
            linkerSettings: [
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
