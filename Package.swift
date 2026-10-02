// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Anchor",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Anchor",
            path: "Sources/Anchor",
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
