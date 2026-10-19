// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PrompterCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PrompterCore", targets: ["PrompterCore"])],
    targets: [
        .target(name: "PrompterCore", sources: ["Models.swift", "Library.swift", "ScrollClock.swift", "CaptureLifecycle.swift", "WordCue.swift", "CodexTransfer.swift", "TakeExport.swift"]),
        .testTarget(name: "PrompterCoreTests", dependencies: ["PrompterCore"], sources: ["CoreTests.swift"])
    ]
)
