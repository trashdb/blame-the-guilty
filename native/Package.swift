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
                // Embed Info.plist in the binary so macOS can read CFBundleIdentifier
                // without a .app bundle (needed for TCC, Keychain, SMAppService).
                .unsafeFlags([
                    "-sectcreate", "__TEXT", "__info_plist",
                    "Sources/BlameTheGuilty/Info.plist"
                ])
            ]
        )
    ]
)
