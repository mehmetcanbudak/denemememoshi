import CryptoKit
import Foundation

struct PyodidePayload: Sendable {
  struct Manifest: Sendable, Decodable {
    struct File: Sendable, Decodable {
      let path: String
      let bytes: Int
      let sha256: String
    }

    struct Package: Sendable, Decodable {
      let name: String
      let version: String
      let file: String
    }

    let schema: Int
    let pyodide: String
    let revision: String
    let python: String
    let coreArchiveSHA256: String
    let bundledBytes: Int
    let files: [File]
    let packages: [Package]
  }

  static let manifestDigest = "57f41131904edff72a507d8e38bd39d9c6a7749613d34e11630ed5545278a1f1"
  let resources: URL
  let manifest: Manifest
  static let hostFiles = ["host.html", "bridge.mjs", "worker.mjs", "cell-helpers.py"]
  let allowedPaths: Set<String>

  static func bundled() async throws -> PyodidePayload {
    guard !Task.isCancelled else { throw PyodideFailure.cancelled }
    guard let resources = Bundle.module.resourceURL else {
      throw PyodideFailure.bundleMissing
    }
    return try await loadAsync(resources: resources)
  }

  static func loadAsync(resources: URL) async throws -> PyodidePayload {
    guard !Task.isCancelled else { throw PyodideFailure.cancelled }
    let task = Task.detached(priority: .userInitiated) {
      try load(resources: resources)
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  static func load(resources: URL) throws -> PyodidePayload {
    guard !Task.isCancelled else { throw PyodideFailure.cancelled }
    let runtime = resources.appendingPathComponent("Runtime", isDirectory: true)
    let bytes: Data
    do { bytes = try Data(contentsOf: runtime.appendingPathComponent("manifest.json")) } catch {
      throw PyodideFailure.bundleMissing
    }
    guard hex(SHA256.hash(data: bytes)) == manifestDigest else {
      throw PyodideFailure.bundleIntegrity
    }
    let manifest: Manifest
    do { manifest = try JSONDecoder().decode(Manifest.self, from: bytes) } catch {
      throw PyodideFailure.bundleIntegrity
    }
    guard manifest.schema == 1, manifest.pyodide == "314.0.7",
      manifest.revision == "b1e4fcc2488962f6360a97f19b9982d6fdb5d16f",
      manifest.coreArchiveSHA256
        == "2abdcc2e35208af406e07724cffa85bc582ced97e9028383ecf5462541393f95",
      manifest.bundledBytes == manifest.files.reduce(0, { $0 + $1.bytes }),
      Set(manifest.files.map(\.path)).count == manifest.files.count,
      Set(manifest.packages.map(\.name)).isSuperset(of: ["numpy", "pandas", "scipy", "matplotlib"])
    else { throw PyodideFailure.bundleIntegrity }
    for file in manifest.files {
      guard !Task.isCancelled else { throw PyodideFailure.cancelled }
      _ = try PyodidePath.components(file.path)
      let url = runtime.appendingPathComponent(file.path)
      do {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var count = 0
        while let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty {
          guard !Task.isCancelled else { throw PyodideFailure.cancelled }
          count += chunk.count
          guard count <= file.bytes else { throw PyodideFailure.bundleIntegrity }
          hash.update(data: chunk)
        }
        guard count == file.bytes, hex(hash.finalize()) == file.sha256 else {
          throw PyodideFailure.bundleIntegrity
        }
      } catch PyodideFailure.cancelled {
        throw PyodideFailure.cancelled
      } catch { throw PyodideFailure.bundleIntegrity }
    }
    for hostFile in hostFiles {
      guard FileManager.default.fileExists(atPath: resources.appendingPathComponent(hostFile).path)
      else { throw PyodideFailure.bundleMissing }
    }
    var allowed = Set(manifest.files.map { "Runtime/" + $0.path })
    allowed.formUnion(hostFiles)
    allowed.insert("Runtime/manifest.json")
    return PyodidePayload(resources: resources, manifest: manifest, allowedPaths: allowed)
  }

  private static func hex(_ digest: SHA256.Digest) -> String {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
