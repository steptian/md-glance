// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "md-glance",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "md-glance",
            targets: ["md-glance"]
        ),
        .executable(
            name: "md-glanceCLI",
            targets: ["md-glanceCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "md-glance",
            dependencies: [
                "md-glanceCore",
            ],
            path: "md-glance/App",
            resources: [
                .process("HELP.md")
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),
        .target(
            name: "md-glanceCore",
            dependencies: [
                .product(name: "Ink", package: "Ink"),
            ],
            path: "md-glance/Renderer",
            resources: [
                .copy("Resources")
            ]
        ),
        .target(
            name: "FileWatcher",
            path: "md-glance/FileWatcher"
        ),
        .executableTarget(
            name: "md-glanceCLI",
            dependencies: ["md-glanceCore"],
            path: "md-glanceCLI",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Foundation"),
            ]
        ),
    ]
)
