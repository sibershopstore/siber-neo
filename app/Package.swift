// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SiberNeo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "SiberNeo",
            path: "Sources/SiberNeo",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("IOBluetooth"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMediaIO"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("EventKit"),
                .linkedFramework("SystemConfiguration"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
