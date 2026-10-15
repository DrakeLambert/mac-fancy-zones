// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "mac-fancy-zones",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FancyZonesCore"),
        .executableTarget(name: "CoreChecks", dependencies: ["FancyZonesCore"]),
        .executableTarget(name: "MacFancyZones", dependencies: ["FancyZonesCore"]),
    ]
)
