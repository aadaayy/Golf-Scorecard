// swift-tools-version:5.9
// The app's scoring and course logic as a small package, so the logic tests
// can run anywhere Swift runs (including a cheap Linux machine), without Xcode.
// The app itself is built from GolfScorecard.xcodeproj.
import PackageDescription

let package = Package(
    name: "ScorecardCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ScorecardCore", targets: ["ScorecardCore"]),
    ],
    targets: [
        .target(name: "ScorecardCore", path: "GolfScorecard/Core"),
        .testTarget(
            name: "ScorecardCoreTests",
            dependencies: ["ScorecardCore"],
            path: "Tests/ScorecardCoreTests"
        ),
    ]
)
