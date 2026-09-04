// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MRRDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "MRRDock",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "MRRDock",
            exclude: ["Info.plist"],
            resources: [.copy("Resources/AppIcon.icns")]
        ),
        .testTarget(
            name: "MRRDockTests",
            dependencies: ["MRRDock"],
            path: "Tests"
        ),
    ]
)
