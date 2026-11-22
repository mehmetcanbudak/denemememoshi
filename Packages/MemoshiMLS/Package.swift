// swift-tools-version: 6.4
import PackageDescription

// Build the pinned native payload first with: bash scripts/build-memoshi-mls.sh
// Missing artifacts intentionally fail package resolution; there is no crypto fallback.
let package = Package(
  name: "MemoshiMLS",
  platforms: [.macOS("27.0"), .iOS("27.0")],
  products: [.library(name: "MemoshiMLS", targets: ["MemoshiMLS"])],
  targets: [
    .binaryTarget(
      name: "MemoshiMLSNativeFFI", path: "Artifacts/MemoshiMLSNativeFFI.xcframework"),
    .target(
      name: "MemoshiMLSNativeBindings", dependencies: ["MemoshiMLSNativeFFI"],
      path: "Sources/MemoshiMLSNativeBindings", exclude: ["NOTICE"],
      linkerSettings: [
        .linkedFramework("CryptoKit"), .linkedFramework("Foundation"),
        .linkedFramework("Security"),
      ]),
    .target(name: "MemoshiMLS", dependencies: ["MemoshiMLSNativeBindings"]),
    .testTarget(name: "MemoshiMLSTests", dependencies: ["MemoshiMLS"]),
  ]
)
