// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "NetsiImage",
    platforms: [.macOS(.v27)],
    products: [
        .library(name: "CoreSupport", targets: ["CoreSupport"]),
        .library(name: "CatalogCore", targets: ["CatalogCore"]),
        .library(name: "ParameterEngine", targets: ["ParameterEngine"]),
        .library(name: "RequestKit", targets: ["RequestKit"]),
        .library(name: "GenerationKit", targets: ["GenerationKit"]),
        .library(name: "LibraryKit", targets: ["LibraryKit"]),
        .library(name: "SettingsKit", targets: ["SettingsKit"]),
        .library(name: "NetsiImageUI", targets: ["NetsiImageUI"]),
        .executable(name: "NetsiImage", targets: ["NetsiImageApp"]),
    ],
    targets: [
        .target(name: "CoreSupport"),

        .target(
            name: "CatalogCore",
            dependencies: ["CoreSupport"],
            resources: [.copy("Resources/openrouter-image-ui-catalog.json")]
        ),
        .target(name: "ParameterEngine", dependencies: ["CoreSupport", "CatalogCore"]),
        .target(name: "RequestKit", dependencies: ["CoreSupport", "CatalogCore", "ParameterEngine"]),
        .target(name: "GenerationKit", dependencies: ["CoreSupport", "CatalogCore", "ParameterEngine", "RequestKit"]),
        .target(name: "LibraryKit", dependencies: ["CoreSupport", "CatalogCore", "GenerationKit"]),
        .target(name: "SettingsKit", dependencies: ["CoreSupport"]),

        .target(
            name: "NetsiImageUI",
            dependencies: [
                "CoreSupport", "CatalogCore", "ParameterEngine", "RequestKit",
                "GenerationKit", "LibraryKit", "SettingsKit",
            ]
        ),
        .executableTarget(
            name: "NetsiImageApp",
            dependencies: [
                "NetsiImageUI", "CoreSupport", "CatalogCore", "ParameterEngine",
                "GenerationKit", "LibraryKit", "SettingsKit",
            ]
        ),

        .testTarget(name: "CoreSupportTests", dependencies: ["CoreSupport"]),
        .testTarget(name: "CatalogCoreTests", dependencies: ["CoreSupport", "CatalogCore"]),
        .testTarget(name: "ParameterEngineTests", dependencies: ["CoreSupport", "CatalogCore", "ParameterEngine"]),
        .testTarget(name: "RequestKitTests", dependencies: ["CoreSupport", "CatalogCore", "ParameterEngine", "RequestKit"]),
        .testTarget(name: "GenerationKitTests", dependencies: ["CoreSupport", "CatalogCore", "ParameterEngine", "RequestKit", "GenerationKit"]),
        .testTarget(name: "LibraryKitTests", dependencies: ["CoreSupport", "CatalogCore", "LibraryKit"]),
        .testTarget(name: "SettingsKitTests", dependencies: ["SettingsKit"]),
    ]
)
