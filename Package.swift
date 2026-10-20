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
        exclude: ["Info.plist"],
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

let package = Package(
    name: "SonosLocal",
    products: products,
    targets: targets
)
