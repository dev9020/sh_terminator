// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SHTerminator",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Единственная внешняя зависимость. Запинена точной версией, без диапазонов,
        // чтобы `swift package update` никогда не подтянул неожиданный код молча.
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
