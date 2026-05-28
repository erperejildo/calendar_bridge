// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "calendar-bridge",
    platforms: [
        .iOS("13.0"),
        .macOS("11.0")
    ],
    products: [
        .library(name: "calendar-bridge", targets: ["calendar-bridge"])
    ],
    targets: [
        .target(
            name: "calendar-bridge",
            path: "Sources/calendar_bridge",
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
