import Darwin
import Foundation
import MemoshiDevice

/// The medium S2's durable state lived on and how slowly it synchronized. Context for reading
/// lease timings, never a gate: it does not change the batch status or reclassify any result.
package struct S2Storage: Codable, Sendable {
  /// The `--work-dir` that held every durable store, mailbox, journal and SQLite file.
  package var workDirectory: String
  /// `statfs`: the volume's mount point, source device and file system.
  package var mountPoint: String
  package var device: String
  package var fileSystem: String
  /// Foundation's volume flags; nil when the system did not report them.
  package var internalVolume: Bool?
  package var removableVolume: Bool?
  package var localVolume: Bool?
  /// Synchronization probes on that volume, before and after the scenarios.
  package var probes: [S2SyncProbe]

  /// Describes `directory`'s volume; a failure is reported in place of the volume facts.
  package static func describe(_ directory: URL) -> S2Storage {
    var storage = S2Storage(
      workDirectory: directory.path, mountPoint: "", device: "", fileSystem: "", probes: [])
    var info = statfs()
    if statfs(directory.path, &info) == 0 {
      storage.mountPoint = text(&info.f_mntonname)
      storage.device = text(&info.f_mntfromname)
      storage.fileSystem = text(&info.f_fstypename)
    } else {
      storage.mountPoint = "statfs failed: \(String(cString: strerror(errno)))"
    }
    let values = try? directory.resourceValues(forKeys: [
      .volumeIsInternalKey, .volumeIsRemovableKey, .volumeIsLocalKey,
    ])
    storage.internalVolume = values?.volumeIsInternal
    storage.removableVolume = values?.volumeIsRemovable
    storage.localVolume = values?.volumeIsLocal
    return storage
  }

  private static func text<T>(_ field: inout T) -> String {
    withUnsafeBytes(of: &field) { bytes in
      String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}

/// `samples` appends of `recordBytes` to a private file in the work directory, each followed by
/// `fsync`, `intervalMs` apart: the same durable-write shape as the authority and device journals.
package struct S2SyncProbe: Codable, Sendable {
  package var phase: String
  package var recordBytes: Int
  package var intervalMs: Int
  /// Latency of each `write` + `fsync` pair.
  package var latency: S2Distribution
  /// Pairs that took longer than one second.
  package var overOneSecond: Int
  /// The probe's own error, if it could not finish; the latencies cover the completed pairs.
  package var error: String?

  package static func measure(
    in directory: URL, phase: String, samples: Int = 100, recordBytes: Int = 512,
    intervalMs: Int = 10
  ) async -> S2SyncProbe {
    var latencies: [UInt64] = []
    var failure: String?
    let url = directory.appendingPathComponent("s2-sync-probe-\(UUID().uuidString).bin")
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_APPEND | O_CLOEXEC, 0o600)
    if descriptor < 0 {
      failure = "open: \(String(cString: strerror(errno)))"
    } else {
      defer {
        close(descriptor)
        unlink(url.path)
      }
      let record = [UInt8](repeating: 0x5A, count: recordBytes)
      for _ in 0..<samples {
        let start = DeviceClock.monotonicNanoseconds()
        let written = record.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
        guard written == recordBytes else {
          failure = "write: \(written < 0 ? String(cString: strerror(errno)) : "short \(written)")"
          break
        }
        guard fsync(descriptor) == 0 else {
          failure = "fsync: \(String(cString: strerror(errno)))"
          break
        }
        latencies.append(DeviceClock.monotonicNanoseconds() - start)
        try? await Task.sleep(for: .milliseconds(intervalMs))
      }
    }
    return S2SyncProbe(
      phase: phase, recordBytes: recordBytes, intervalMs: intervalMs,
      latency: S2Distribution(latencies),
      overOneSecond: latencies.filter { $0 > 1_000_000_000 }.count, error: failure)
  }
}
