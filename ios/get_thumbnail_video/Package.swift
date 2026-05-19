// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "get_thumbnail_video",
    platforms: [
        .iOS("12.0"),
    ],
    products: [
        .library(
            name: "get-thumbnail-video",
            targets: ["get_thumbnail_video"]
        ),
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(
            url: "https://github.com/SDWebImage/libwebp-Xcode",
            from: "1.3.2"
        ),
    ],
    targets: [
        .target(
            name: "get_thumbnail_video",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "libwebp", package: "libwebp-Xcode"),
            ],
            path: ".",
            sources: ["Classes"],
            resources: [
                .process("Resources"),
            ],
            publicHeadersPath: "Classes",
            cSettings: [
                .headerSearchPath("Classes"),
            ]
        ),
    ]
)
