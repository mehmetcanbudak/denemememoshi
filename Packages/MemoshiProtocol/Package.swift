// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiProtocol",
  platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [
    .library(name: "MemoshiProtocol", targets: ["MemoshiProtocol"]),
    .library(name: "MemoshiProtocolSchema", targets: ["MemoshiProtocolSchema"]),
    .executable(name: "memoshi-protocol-schema", targets: ["MemoshiProtocolSchemaTool"]),
  ],
  dependencies: [
    // Test-only: a Swift-native JSON Schema Draft 2020-12 validator for the fixtures (MIT).
    .package(url: "https://github.com/ajevans99/swift-json-schema", exact: "0.14.2")
  ],
  targets: [
    // The wire types: the protocol's single source of truth (D78). No dependencies.
    .target(name: "MemoshiProtocol"),
    // Derives protocol.schema.json from the wire types.
    .target(name: "MemoshiProtocolSchema", dependencies: ["MemoshiProtocol"]),
    // `memoshi-protocol-schema`: prints the schema as canonical JSON.
    .executableTarget(
      name: "MemoshiProtocolSchemaTool",
      dependencies: ["MemoshiProtocolSchema"]
    ),
    .testTarget(
      name: "MemoshiProtocolTests",
      dependencies: [
        "MemoshiProtocol",
        "MemoshiProtocolSchema",
        .product(name: "JSONSchema", package: "swift-json-schema"),
      ]
    ),
  ]
)
