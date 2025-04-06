// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "fuoco",
    platforms: [.iOS(.v17)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "Networking",
            targets: ["Networking"]
        ),
        .library(
            name: "Authentication",
            targets: ["Authentication"]
        ),
        .library(
            name: "Storage",
            targets: ["Storage"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/firebase/firebase-ios-sdk.git",
            from: "11.6.0"
        ),
        .package(
            url: "https://github.com/pointfreeco/swift-dependencies.git",
            from: "1.7.0"
        )
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Networking",
            dependencies: [
              .product(name: "FirebaseDatabase", package: "firebase-ios-sdk"),
              .product(name: "FirebaseFirestore", package: "firebase-ios-sdk"),
              .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
            ]
        ),
        .target(
            name: "Authentication",
            dependencies: [
              .product(name: "FirebaseAuth", package: "firebase-ios-sdk"),
              .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
        .target(
            name: "Storage",
            dependencies: [
              .product(name: "FirebaseStorage", package: "firebase-ios-sdk"),
              .product(name: "Dependencies", package: "swift-dependencies"),
            ]
        ),
    ]
)
