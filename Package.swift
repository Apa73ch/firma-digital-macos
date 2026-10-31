// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FirmaDigitalMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "FirmaDigital", targets: ["FirmaDigital"]),
        .executable(name: "firmar-cli", targets: ["firmar-cli"]),
    ],
    targets: [
        .target(
            name: "FirmaCore",
            linkerSettings: [.linkedLibrary("xml2"), .linkedFramework("Security")]
        ),
        .executableTarget(name: "FirmaDigital", dependencies: ["FirmaCore"]),
        .executableTarget(name: "firmar-cli", dependencies: ["FirmaCore"]),
    ]
)
