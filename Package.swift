// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MRRDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MRRDock",
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
