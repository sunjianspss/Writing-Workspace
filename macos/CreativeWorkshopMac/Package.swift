// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CreativeWorkshopMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CreativeWorkshopMac", targets: ["CreativeWorkshopMac"])
    ],
    targets: [
        .target(
            name: "CreativeWorkshopCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CreativeWorkshopMac",
            dependencies: ["CreativeWorkshopCore"]
        ),
        .testTarget(
            name: "CreativeWorkshopMacTests",
            dependencies: ["CreativeWorkshopMac", "CreativeWorkshopCore"]
        ),
        .executableTarget(
            name: "CreativeWorkshopEval",
            dependencies: ["CreativeWorkshopCore"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "CreativeWorkshopEvalTests",
            dependencies: ["CreativeWorkshopEval", "CreativeWorkshopCore"]
        )
    ]
)
