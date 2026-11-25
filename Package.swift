// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CopyPaste",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CopyPaste",
            path: "Sources/CopyPaste",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
