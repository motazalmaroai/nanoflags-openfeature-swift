// swift-tools-version:5.9
//
// NanoFlags provider for the official OpenFeature Swift SDK (github.com/open-feature/swift-sdk).
//
// A separate package because the OpenFeature Swift SDK requires iOS 15 / tvOS 15 / watchOS 8 and Combine
// (Apple platforms only), while the NanoFlags package supports iOS 14 and Linux. A product of the NanoFlags
// package could not depend on it: SwiftPM refuses a dependency whose minimum platform is higher than the
// depending package's. OpenFeature 0.7.0 needs a Swift 6.1 compiler (Xcode 16.3 or later).
import Foundation
import PackageDescription

// In the source tree the NanoFlags package is the parent directory; published on its own, the provider
// depends on the NanoFlags repository by URL.
let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let core = here.deletingLastPathComponent()
let local = FileManager.default.fileExists(atPath: core.appendingPathComponent("Sources/NanoFlags").path)
let nanoflags: Package.Dependency = local
    ? .package(path: core.path)
    : .package(url: "https://github.com/motazalmaroai/nanoflags-swift.git", from: "0.1.0")
let nanoflagsPackage = local ? core.lastPathComponent : "nanoflags-swift"

let package = Package(
    name: "NanoFlagsOpenFeature",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(name: "NanoFlagsOpenFeature", targets: ["NanoFlagsOpenFeature"]),
    ],
    dependencies: [
        nanoflags,
        .package(url: "https://github.com/open-feature/swift-sdk.git", .upToNextMinor(from: "0.7.0")),
    ],
    targets: [
        .target(
            name: "NanoFlagsOpenFeature",
            dependencies: [
                .product(name: "NanoFlags", package: nanoflagsPackage),
                .product(name: "OpenFeature", package: "swift-sdk"),
            ]
        ),
        .testTarget(name: "NanoFlagsOpenFeatureTests", dependencies: ["NanoFlagsOpenFeature"]),
    ]
)
