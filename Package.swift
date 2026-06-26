// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MakeTheChoiceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "MakeTheChoiceCore",
            targets: ["MakeTheChoiceCore"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "MakeTheChoiceCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "MakeTheChoiceCoreTests",
            dependencies: ["MakeTheChoiceCore"]
        )
    ]
)
