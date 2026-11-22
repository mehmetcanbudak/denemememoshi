// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiClient",
  platforms: [.macOS("27.0")],
  products: [.library(name: "MemoshiClient", targets: ["MemoshiClient"])],
  dependencies: [
    .package(path: "../MemoshiProtocol"),
    .package(path: "../MemoshiIPC"),
    .package(path: "../MemoshiCore"),
  ],
  targets: [
    .target(
      name: "MemoshiClient",
      dependencies: [
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
        .product(name: "MemoshiStore", package: "MemoshiCore"),
      ]
    ),
    .testTarget(
      name: "MemoshiClientTests",
      dependencies: [
        "MemoshiClient",
        .product(name: "MemoshiTransport", package: "MemoshiIPC"),
        .product(name: "MemoshiProtocol", package: "MemoshiProtocol"),
      ]
    ),
  ]
)
