// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "TailQuestions",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "TailQuestions",
            path: "Sources/TailQuestions",
            linkerSettings: [.linkedFramework("Carbon")]
        )
    ]
)
