// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FacePause",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "FacePause", targets: ["FacePause"])],
    targets: [
        .target(name: "FaceCore"),
        .executableTarget(name: "FacePause", dependencies: ["FaceCore"]),
        .testTarget(name: "FaceCoreTests", dependencies: ["FaceCore"])
    ],
    swiftLanguageModes: [.v5]
)
