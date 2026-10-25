// swift-tools-version: 6.2
import PackageDescription

// ReaderCore is the app's portable, dependency-free logic: what a catalog offers, which books the
// app can open, and (later) the reading position it syncs. It builds on Apple platforms and on
// Linux, so its tests run without Xcode (tools/swift.sh test, and CI's `core` job). Its tests'
// fixtures (`Tests/Fixtures`) stand in for a reader's server: CI never talks to a real one.
let package = Package(
    name: "ReaderCore",
    platforms: [.iOS("26.0"), .macOS("15.0")],
    products: [
        .library(name: "ReaderCore", targets: ["ReaderCore"]),
    ],
    targets: [
        .target(name: "ReaderCore"),
        .testTarget(name: "ReaderCoreTests", dependencies: ["ReaderCore"]),
    ],
    swiftLanguageModes: [.v6]
)
