// swift-tools-version:5.9
import PackageDescription

// Info.plist wordt in het programma ingebakken, zodat ook `swift run`
// toegang heeft tot http:// en het lokale netwerk (Home Assistant).
let infoPlist = Context.packageDirectory + "/Resources/Info.plist"

let package = Package(
    name: "DockStudio",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DockStudio",
            path: "Sources/DockStudio",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist", "-Xlinker", infoPlist])
            ]
        )
    ]
)
