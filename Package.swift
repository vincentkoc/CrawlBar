// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CrawlBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CrawlBarCore", targets: ["CrawlBarCore"]),
        .executable(name: "CrawlBar", targets: ["CrawlBar"]),
        .executable(name: "crawlbar", targets: ["CrawlBarCLI"]),
    ],
    targets: [
        .target(
            name: "CrawlBarCore",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "CrawlBar",
            dependencies: ["CrawlBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .executableTarget(
            name: "CrawlBarCLI",
            dependencies: ["CrawlBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
        .testTarget(
            name: "CrawlBarTests",
            dependencies: ["CrawlBarCore"],
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency"),
            ]),
    ])
