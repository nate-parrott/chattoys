// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ChatToys",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "ChatToys",
            targets: ["ChatToys"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
        .package(url: "https://github.com/cezheng/Fuzi", from: "3.1.3"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.1"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.17.0"),
        .package(url: "https://github.com/Flight-School/AnyCodable", from: "0.6.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "ChatToys",
            dependencies: ["SwiftSoup", .product(name: "GRDB", package: "GRDB.swift"), "Fuzi", "AnyCodable"]),
        .testTarget(
            name: "ChatToysTests",
            dependencies: ["ChatToys"]),
    ]
)
