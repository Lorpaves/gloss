// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HyMTKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "HyMTKit", targets: ["HyMTKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/huggingface/swift-transformers.git", from: "1.4.0")
    ],
    targets: [
        // llama.cpp b11960 (2026-10-28): ios-arm64 + macos-arm64_x86_64 slices, no iOS Simulator slice.
        .binaryTarget(
            name: "llama",
            url: "https://github.com/ggml-org/llama.cpp/releases/download/b11960/llama-b11960-xcframework.zip",
            checksum: "feba05e0b7cb5e682ae3354abb455bf9723ae2cc95c69e24d073264e6a34d759"
        ),
        .target(
            name: "HyMTKit",
            dependencies: [
                "llama",
                .product(name: "Tokenizers", package: "swift-transformers")
            ]
        ),
        .testTarget(
            name: "HyMTKitTests",
            dependencies: ["HyMTKit"]
        )
    ]
)
