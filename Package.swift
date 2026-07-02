// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "ZvecStudio",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ZvecStudioCore", targets: ["ZvecStudioCore"]),
        .executable(name: "ZvecStudio", targets: ["ZvecStudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/lurenyang418/zvec-swift.git", exact: "0.5.1")
    ],
    targets: [
        .target(
            name: "ZvecStudioCore",
            dependencies: [.product(name: "Zvec", package: "zvec-swift")]
        ),
        .executableTarget(
            name: "ZvecStudio",
            dependencies: ["ZvecStudioCore", .product(name: "Zvec", package: "zvec-swift")]
        ),
        .testTarget(
            name: "ZvecStudioCoreTests",
            dependencies: ["ZvecStudioCore", .product(name: "Zvec", package: "zvec-swift")]
        ),
    ],
    swiftLanguageModes: [.v6]
)
