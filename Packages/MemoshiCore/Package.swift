// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiCore",
  platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [
    .library(name: "MemoshiStore", targets: ["MemoshiStore"]),
    .library(name: "MemoshiRuntime", targets: ["MemoshiRuntime"]),
    .library(name: "MemoshiEgress", targets: ["MemoshiEgress"]),
  ],
  dependencies: [
    .package(path: "../MemoshiProtocol"),
    // Pi_Swift `slice-2.2` (D140), from the clean checkout that scripts/check-prerequisites.sh
    // creates at the commit pinned in scripts/lib/pi-swift-pin.sh and checks on every run.
    // A path, not a revision pin: SwiftPM refuses a revision pin on a package that has a local
    // package dependency, as slice-2.2 has (Vendor/SwiftBashParser).
    .package(path: "../../../Pi_Swift-slice-2.2"),
    .package(url: "https://github.com/apple/swift-nio", exact: "2.104.0"),
    .package(url: "https://github.com/apple/swift-nio-ssl", exact: "2.37.6"),
  ],
  targets: [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
      name: "MemoshiStore",
      dependencies: ["CSQLite", .product(name: "MemoshiProtocol", package: "MemoshiProtocol")],
      path: "Sources/Store",
      resources: [.copy("Migrations")]
    ),
    // The egress gateway for sandboxed computers (06 §4.8): loopback HTTP CONNECT/forward proxy,
    // per-computer lists, masked credentials and attributed decisions. No Pi import.
    .target(
      name: "MemoshiEgress",
      dependencies: [
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
      ],
      path: "Sources/Egress"
    ),
    .target(
      name: "MemoshiRuntime",
      dependencies: [
        "MemoshiStore", "MemoshiEgress",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "PiDurable", package: "Pi_Swift-slice-2.2"),
        .product(name: "PiAI", package: "Pi_Swift-slice-2.2"),
        .product(name: "PiCore", package: "Pi_Swift-slice-2.2"),
        .product(name: "Chord", package: "Pi_Swift-slice-2.2"),
        // Code Mode and the stdio MCP bridge exist only in an explicit development/qualification
        // composition (RuntimeExtensionComposition); the app and daemon compose none.
        .product(name: "PiCodeMode", package: "Pi_Swift-slice-2.2"),
        .product(name: "PiMCP", package: "Pi_Swift-slice-2.2"),
        // Conversation computers (S1.12): RemoteExecutionEnv to a Seatbelt-confined daemon, only
        // in an explicit development/qualification RuntimeEnvironmentComposition.
        .product(name: "PiEnv", package: "Pi_Swift-slice-2.2"),
      ],
      path: "Sources/Runtime",
      exclude: ["Qualification"]
    ),
    .testTarget(
      name: "MemoshiStoreTests",
      dependencies: ["MemoshiStore", "CSQLite"],
      resources: [.copy("Fixtures")]
    ),
    .testTarget(
      name: "MemoshiEgressTests",
      dependencies: [
        "MemoshiEgress",
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
      ]
    ),
    // Test-only fixture processes (an independent stdio MCP server and a killable Code Mode
    // runtime host). No product exports it, so neither the app nor memoshid links it.
    .executableTarget(
      name: "memoshi-runtime-fixture",
      dependencies: [
        "MemoshiRuntime", "MemoshiStore",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
      ],
      path: "Tests/RuntimeFixture"
    ),
    .testTarget(
      name: "MemoshiRuntimeTests",
      dependencies: [
        "MemoshiRuntime", "MemoshiStore", "MemoshiEgress", "CSQLite",
        .target(name: "memoshi-runtime-fixture", condition: .when(platforms: [.macOS])),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOSSL", package: "swift-nio-ssl"),
      ]
    ),
  ]
)
