// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiIPC",
  platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [
    .library(name: "MemoshiTransport", targets: ["MemoshiTransport"]),
    // Explicit S2 development composition; no production Pi store/lease cutover.
    .library(name: "MemoshiDevice", targets: ["MemoshiDevice"]),
    .library(name: "MemoshiDeviceApple", targets: ["MemoshiDeviceApple"]),
  ],
  dependencies: [
    .package(path: "../MemoshiProtocol"),
    .package(path: "../MemoshiMLS"),
    .package(url: "https://github.com/apple/swift-nio", exact: "2.104.0"),
  ],
  targets: [
    .target(
      name: "CMemoshiSecurity",
      linkerSettings: [.linkedFramework("Security"), .linkedLibrary("bsm")]
    ),
    .target(
      name: "MemoshiTransport",
      dependencies: [
        "CMemoshiSecurity",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
        .product(name: "NIOHTTP1", package: "swift-nio"),
        .product(name: "NIOWebSocket", package: "swift-nio"),
        .product(name: "NIOFoundationCompat", package: "swift-nio"),
      ]
    ),
    .target(
      name: "MemoshiDevice",
      dependencies: [
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiMLS", package: "MemoshiMLS"),
        .product(name: "NIOCore", package: "swift-nio"),
        .product(name: "NIOPosix", package: "swift-nio"),
      ]
    ),
    .target(
      name: "MemoshiDeviceApple",
      dependencies: [
        "MemoshiDevice",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiMLS", package: "MemoshiMLS"),
      ]
    ),
    .testTarget(
      name: "MemoshiTransportTests",
      dependencies: [
        "MemoshiTransport",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "NIOEmbedded", package: "swift-nio"),
      ]
    ),
    .testTarget(
      name: "MemoshiDeviceTests",
      dependencies: [
        "MemoshiDevice",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
      ]
    ),
    .testTarget(
      name: "MemoshiDeviceAppleTests",
      dependencies: [
        "MemoshiDeviceApple", "MemoshiDevice",
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiMLS", package: "MemoshiMLS"),
      ]
    ),
  ]
)
