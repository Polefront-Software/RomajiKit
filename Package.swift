// swift-tools-version: 6.0

import PackageDescription

// Japanese lyrics to romaji, on the device. No UI in here: the app draws
// what this package resolves. Builds for iOS, macOS, watchOS and tvOS,
// and on the macOS host, so `swift test` needs no simulator.
let package = Package(
    name: "RomajiKit",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .watchOS("26.0"),
        .tvOS("26.0"),
    ],
    products: [
        .library(name: "RomajiKit", targets: ["RomajiKit"]),
    ],
    dependencies: [
        // MeCab's engine (see NOTICE.md). Its IPAdic is the source of the
        // pack the app fetches (scripts/romaji-dictionary.sh), and what
        // the tests and the command-line tool read with.
        .package(url: "https://github.com/shinjukunian/Mecab-Swift.git", exact: "0.8.0"),
    ],
    targets: [
        .target(
            name: "RomajiKit",
            dependencies: [.product(name: "Mecab-Swift", package: "Mecab-Swift")],
            resources: [.process("Resources")]
        ),
        // Lines in, romaji out: for looking at what the engine does.
        .executableTarget(
            name: "romaji",
            dependencies: ["RomajiKit", .product(name: "IPADic", package: "Mecab-Swift")]
        ),
        .testTarget(
            name: "RomajiKitTests",
            dependencies: ["RomajiKit", .product(name: "IPADic", package: "Mecab-Swift")]
        ),
    ]
)
