// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PorchCore",
    platforms: [.iOS(.v15), .macOS(.v10_15)],
    products: [.library(name: "PorchCore", targets: ["PorchCore"])],
    dependencies: [.package(url: "https://github.com/PhoneNumberKit/PhoneNumberKit", exact: "5.0.9")],
    targets: [
        .target(name: "PorchCore", dependencies: [.product(name: "PhoneNumberKit", package: "PhoneNumberKit")]),
        .testTarget(name: "PorchCoreTests", dependencies: ["PorchCore"])
    ]
)
