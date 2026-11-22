// swift-tools-version: 6.4
import PackageDescription

let package = Package(
  name: "MemoshiApp",
  defaultLocalization: "en",
  platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [
    .library(name: "AppCore", targets: ["AppCore"]),
    .library(name: "DesignSystem", targets: ["DesignSystem"]),
    .library(name: "ConversationFeature", targets: ["ConversationFeature"]),
    .library(name: "ShellFeature", targets: ["ShellFeature"]),
    .library(name: "PyodideSpike", targets: ["PyodideSpike"]),
    .library(name: "DevicePairingFeature", targets: ["DevicePairingFeature"]),
  ],
  // The typed protocol only: the shared approval and in-process chat projections call the engine
  // through MemoshiAPI, never through a transport, store or Pi module.
  dependencies: [.package(path: "../MemoshiProtocol")],
  targets: [
    // AppCore and ConversationFeature each carry their own English String Catalog, looked up
    // with `bundle: #bundle` like DesignSystem's.
    .target(
      name: "AppCore",
      dependencies: [.product(name: "MemoshiProtocol", package: "MemoshiProtocol")],
      resources: [.process("Resources")]
    ),
    // DesignSystem's own English String Catalog with plural rules; both apps load it from the
    // package's resource bundle (`#bundle`), so neither app catalog repeats its keys.
    .target(name: "DesignSystem", resources: [.process("Resources")]),
    .target(
      name: "ConversationFeature",
      dependencies: ["AppCore", "DesignSystem"],
      resources: [.process("Resources")]
    ),
    .target(
      name: "DevicePairingFeature",
      dependencies: ["AppCore", "DesignSystem"],
      resources: [.process("Resources")]
    ),
    .target(
      name: "ShellFeature",
      dependencies: ["AppCore", "DesignSystem"],
      resources: [.process("Resources")]
    ),
    // A root `Resources` directory makes a flat iOS resource bundle invalid for codesign.
    // Preserve Runtime as a subtree and copy the host files directly into the bundle.
    .target(
      name: "PyodideSpike",
      resources: [
        .copy("Resources/Runtime"), .copy("Resources/host.html"),
        .copy("Resources/bridge.mjs"), .copy("Resources/worker.mjs"),
        .copy("Resources/cell-helpers.py"),
      ]),
    .testTarget(name: "PyodideSpikeTests", dependencies: ["PyodideSpike"]),
    .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"]),
    .testTarget(name: "DesignSystemPerformanceTests", dependencies: ["DesignSystem"]),
    .testTarget(
      name: "MemoshiAppTests",
      dependencies: ["AppCore", .product(name: "MemoshiProtocol", package: "MemoshiProtocol")]
    ),
  ]
)
