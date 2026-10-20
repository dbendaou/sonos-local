// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = [
    .library(name: "SonosKit", targets: ["SonosKit"]),
]

var targets: [Target] = [
    .target(name: "SonosKit", path: "Sources/SonosKit"),
    .testTarget(
        name: "SonosKitTests",
        dependencies: ["SonosKit"],
        path: "Tests/SonosKitTests"
    ),
]

#if os(macOS)
products.append(.executable(name: "SonosLocal", targets: ["SonosApp"]))
targets.append(
    .executableTarget(
        name: "SonosApp",
        dependencies: ["SonosKit"],
        path: "Sources/SonosApp",
        exclude: ["Info.plist", "SonosLocal.entitlements"],
        resources: [.process("Resources")],
        linkerSettings: [
            .unsafeFlags([
                "-Xlinker", "-sectcreate",
                "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist",
                "-Xlinker", "Sources/SonosApp/Info.plist",
            ]),
        ]
    )
)
#endif

// Minimum when this manifest is evaluated on a Mac. Linux builds of SonosKit
// keep the default so `swift test` still runs there. Swift 6+ otherwise
// targets macOS 12, which rejects the macOS 14 SwiftUI APIs this app uses.
var platforms: [SupportedPlatform]? = nil
#if os(macOS)
platforms = [.macOS(.v14)]
#endif

let package = Package(
    name: "SonosLocal",
    platforms: platforms,
    products: products,
    targets: targets
)
