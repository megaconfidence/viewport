// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AutoResizeWindow",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AutoResizeWindow", targets: ["AutoResizeWindow"])
    ],
    targets: [
        .executableTarget(
            name: "AutoResizeWindow",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
