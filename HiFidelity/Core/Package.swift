// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTagLib",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "SwiftTagLib",
            targets: ["SwiftTagLib"]
        )
    ],
    targets: [
        .target(
            name: "SwiftTagLib",
            dependencies: ["SwiftTagLibObjC"],
            path: "Sources/SwiftTagLib"
        ),
        .target(
            name: "SwiftTagLibObjC",
            dependencies: ["TagLibBinary"],
            path: "Sources/SwiftTagLibObjC",
            publicHeadersPath: "include",
            cxxSettings: [
                .headerSearchPath("include"),
                .define("TAGLIB_STATIC", to: "1", .when(platforms: [.iOS, .macOS]))
            ]
        ),
        .binaryTarget(
            name: "TagLibBinary",
            path: "Binaries/TagLib.xcframework"
        )
    ]
)
