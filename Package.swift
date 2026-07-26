// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacDiskInspector",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DiskInspectorCore", targets: ["DiskInspectorCore"]),
        .executable(name: "MacDiskInspector", targets: ["MacDiskInspectorApp"]),
        .executable(name: "DiskInspectorCoreVerification", targets: ["DiskInspectorCoreVerification"]),
        .executable(name: "DiskInspectorBenchmark", targets: ["DiskInspectorBenchmark"])
    ],
    targets: [
        .target(
            name: "DiskInspectorCore",
            path: "Sources/DiskInspectorCore"
        ),
        .executableTarget(
            name: "MacDiskInspectorApp",
            dependencies: ["DiskInspectorCore"],
            path: "Sources/MacDiskInspectorApp"
        ),
        .executableTarget(
            name: "DiskInspectorCoreVerification",
            dependencies: ["DiskInspectorCore"],
            path: "Sources/DiskInspectorCoreVerification"
        ),
        .executableTarget(
            name: "DiskInspectorBenchmark",
            dependencies: ["DiskInspectorCore"],
            path: "Sources/DiskInspectorBenchmark"
        ),
        .testTarget(
            name: "DiskInspectorCoreTests",
            dependencies: ["DiskInspectorCore"],
            path: "Tests/DiskInspectorCoreTests"
        ),
        .testTarget(
            name: "MacDiskInspectorAppTests",
            dependencies: ["MacDiskInspectorApp"],
            path: "Tests/MacDiskInspectorAppTests"
        )
    ]
)
