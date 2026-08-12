// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MarkReview",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MarkReview", targets: ["MarkReview"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-markdown.git", from: "0.4.0")
    ],
    targets: [
        .executableTarget(
            name: "MarkReview",
            dependencies: [
                .product(name: "Markdown", package: "swift-markdown")
            ],
            path: "Sources/MarkReview"
        ),
        .testTarget(
            name: "MarkReviewTests",
            dependencies: ["MarkReview"],
            path: "Tests/MarkReviewTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
