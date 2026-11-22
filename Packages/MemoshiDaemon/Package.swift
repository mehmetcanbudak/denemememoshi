// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiDaemon",
  platforms: [.macOS("27.0")],
  // Only MemoshiDaemon is a product. The P0-15 qualification targets below are never exported,
  // so the app and memoshid cannot link them (Sources/MemoshiQualification/README.md).
  products: [.library(name: "MemoshiDaemon", targets: ["MemoshiDaemon"])],
  dependencies: [
    .package(path: "../MemoshiCore"),
    .package(path: "../MemoshiProtocol"),
    .package(path: "../MemoshiIPC"),
    // Only the replay qualification driver links the client.
    .package(path: "../MemoshiClient"),
    // The exact pin MemoshiIPC and MemoshiCore already resolve; only the qualification harness
    // uses it directly, for its loopback effect ledger and controlled model provider.
    .package(url: "https://github.com/apple/swift-nio", exact: "2.104.0"),
  ],
  targets: [
    .target(
      name: "MemoshiDaemon",
      dependencies: [
        .product(name: "MemoshiStore", package: "MemoshiCore"),
        .product(name: "MemoshiRuntime", package: "MemoshiCore"),
        .product(name: "MemoshiEgress", package: "MemoshiCore"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
      ]
    ),
    // Non-shipping qualification harnesses, development evidence only: P0-15 crash/chaos at the
    // runtime-host level and the S2 device-layer prototype runs. No product exports them.
    .target(
      name: "MemoshiQualification",
      dependencies: [
        .product(name: "MemoshiStore", package: "MemoshiCore"),
        .product(name: "MemoshiRuntime", package: "MemoshiCore"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiDevice", package: "MemoshiIPC"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
      ],
      exclude: ["README.md"]
    ),
    .executableTarget(
      name: "memoshi-qualification",
      dependencies: ["MemoshiQualification"]
    ),
    // Signed replay qualification (scripts/run-replay-qualification.sh): a hash chain shared by
    // both executables, a helper signed as memoshid and a driver signed as the Mac app.
    .target(
      name: "MemoshiReplayKit",
      dependencies: [.product(name: "MemoshiProtocol", package: "MemoshiProtocol")]
    ),
    .executableTarget(
      name: "memoshi-replay-daemon",
      dependencies: [
        "MemoshiDaemon", "MemoshiReplayKit",
        .product(name: "MemoshiStore", package: "MemoshiCore"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
      ]
    ),
    .executableTarget(
      name: "memoshi-replay-client",
      dependencies: [
        "MemoshiReplayKit",
        .product(name: "MemoshiClient", package: "MemoshiClient"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
      ]
    ),
    .testTarget(
      name: "MemoshiDaemonTests",
      dependencies: [
        "MemoshiDaemon",
        .product(name: "MemoshiStore", package: "MemoshiCore"),
        .product(name: "MemoshiRuntime", package: "MemoshiCore"),
        .product(name: "MemoshiEgress", package: "MemoshiCore"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
      ]
    ),
    .testTarget(
      name: "MemoshiReplayKitTests",
      dependencies: [
        "MemoshiReplayKit",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
      ]
    ),
    .testTarget(
      name: "MemoshiQualificationTests",
      dependencies: [
        "MemoshiQualification",
        .product(name: "MemoshiStore", package: "MemoshiCore"),
        .product(name: "MemoshiDevice", package: "MemoshiIPC"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
      ]
    ),
  ]
)
