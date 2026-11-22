# Sourced by the lint scripts; run from the repository root.

# Prints every Swift source in the repository, NUL-separated and sorted. Build output,
# SwiftPM checkouts and generated Xcode projects are skipped.
swift_sources() {
  find . \( -name .git -o -name .build -o -name build -o -name DerivedData -o -name .swiftpm \
    -o -name '*.xcodeproj' \) -prune -o -type f -name '*.swift' -print0 | sort -z
}
