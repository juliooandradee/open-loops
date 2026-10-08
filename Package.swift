// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenLoops",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenLoops",
            path: "Sources/OpenLoops",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
