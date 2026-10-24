// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SHTerminator",
    platforms: [.macOS(.v13)],
    dependencies: [
        // The only external dependency. Pinned to an exact version, no ranges,
        // so `swift package update` never silently pulls in unexpected code.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", exact: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "SHTerminator",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SHTerminator"
        ),
        .testTarget(
            name: "SHTerminatorTests",
            dependencies: ["SHTerminator"],
            path: "Tests/SHTerminatorTests"
        ),
    ]
)
