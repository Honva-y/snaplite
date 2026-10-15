// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SnapLite",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Stitching", path: "Sources/Stitching"),
        .executableTarget(
            name: "SnapLite",
            dependencies: ["Stitching"],
            path: "Sources/SnapLite",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .executableTarget(name: "stitch-check", dependencies: ["Stitching"], path: "Sources/StitchCheck"),
    ]
)
