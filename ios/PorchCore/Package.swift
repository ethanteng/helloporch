// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PorchCore",
    platforms: [.iOS(.v15)],
    products: [.library(name: "PorchCore", targets: ["PorchCore"])],
    targets: [
        .target(name: "PorchCore"),
        .testTarget(name: "PorchCoreTests", dependencies: ["PorchCore"])
    ]
)
