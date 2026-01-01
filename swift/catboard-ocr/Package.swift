// swift-tools-version:5.7
import PackageDescription

let package = Package(
    name: "catboard-ocr",
    platforms: [
        .macOS(.v10_15)
    ],
    targets: [
        .executableTarget(
            name: "catboard-ocr",
            path: "Sources"
        )
    ]
)
