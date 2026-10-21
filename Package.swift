// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DicyaninRealityMirror",
    platforms: [.visionOS("2.0"), .iOS("18.0"), .macOS("15.0")],
    products: [
        .library(name: "DicyaninRealityMirror", targets: ["DicyaninRealityMirror"])
    ],
    targets: [
        .target(name: "DicyaninRealityMirror", path: "Sources/DicyaninRealityMirror"),
        .testTarget(name: "DicyaninRealityMirrorTests", dependencies: ["DicyaninRealityMirror"],
                    path: "Tests/DicyaninRealityMirrorTests")
    ]
)
