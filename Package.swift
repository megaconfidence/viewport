// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Viewport",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Viewport", targets: ["Viewport"])
    ],
    targets: [
        .executableTarget(
            name: "Viewport",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
