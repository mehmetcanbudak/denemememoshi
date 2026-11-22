#if os(macOS)
  import Darwin

  /// D137's open-writer warning: which original files some process still has open for writing
  /// just before an export. Best effort, never a guarantee: only processes of the current user
  /// can be inspected without privileges (others are invisible, not reported), a writable
  /// memory mapping is not seen, and a program can open the file again right after the check.
  /// It never refuses an export, and the whole check, scans included, ends within ``limit``.
  enum WorkingCopyOpenWriters {
    /// The whole check, scans and waiting for writers to close, ends within 2 s (plus the
    /// inspection of one process when the bound passes).
    static let limit: Duration = .seconds(2)
    /// How often a writer found open is looked for again.
    static let poll: Duration = .milliseconds(100)

    private struct FileKey: Hashable {
      let device: UInt32
      let inode: UInt64
    }

    /// The `paths` still open for writing when the check ends: at once when none is open,
    /// otherwise when every writer closed or `limit` passed. One scan of every process's
    /// descriptors covers all paths. A scan the bound cuts short names what it found so far
    /// (first scan) or changes nothing (a later scan).
    static func remaining(
      _ paths: [String], within limit: Duration = Self.limit, poll: Duration = Self.poll
    ) async -> [String] {
      await remaining(paths, within: limit, poll: poll, clock: ContinuousClock())
    }

    /// ``remaining(_:within:poll:)`` measured and waited on `clock`: its bound, each scan's
    /// deadline and each wait between scans.
    static func remaining<C: Clock>(
      _ paths: [String], within limit: Duration, poll: Duration, clock: C
    ) async -> [String] where C.Duration == Duration {
      let deadline = clock.now.advanced(by: limit)
      let keys = paths.map(key)
      var open = scan(Set(keys.compactMap { $0 }), until: deadline, on: clock).found
      while !open.isEmpty, clock.now.advanced(by: poll) < deadline {
        try? await clock.sleep(for: poll)
        let next = scan(open, until: deadline, on: clock)
        if next.complete { open = next.found }
      }
      return zip(paths, keys).compactMap { path, key in key.map(open.contains) == true ? path : nil
      }
    }

    /// Whether a process this user can inspect holds a descriptor with write access on the
    /// regular file now at `path` (same device and inode).
    static func isOpenForWriting(_ path: String) -> Bool {
      guard let key = key(path) else { return false }
      let clock = ContinuousClock()
      return !scan([key], until: clock.now.advanced(by: .seconds(60)), on: clock).found.isEmpty
    }

    private static func key(_ path: String) -> FileKey? {
      var info = stat()
      guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
      return FileKey(device: UInt32(bitPattern: info.st_dev), inode: info.st_ino)
    }

    /// One pass over every inspectable process's vnode descriptors.
    private static func scan<C: Clock>(
      _ keys: Set<FileKey>, until deadline: C.Instant, on clock: C
    ) -> (found: Set<FileKey>, complete: Bool) {
      guard !keys.isEmpty else { return ([], true) }
      let count = proc_listallpids(nil, 0)
      guard count > 0 else { return ([], true) }
      var pids = [pid_t](repeating: 0, count: Int(count) + 64)
      let listed = pids.withUnsafeMutableBytes { buffer in
        proc_listallpids(buffer.baseAddress, Int32(buffer.count))
      }
      var found: Set<FileKey> = []
      for pid in pids.prefix(max(0, Int(listed))) where pid > 0 {
        if clock.now >= deadline { return (found, false) }
        writes(pid, keys, into: &found)
        if found.count == keys.count { break }
      }
      return (found, true)
    }

    private static func writes(_ pid: pid_t, _ keys: Set<FileKey>, into found: inout Set<FileKey>) {
      let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
      guard size > 0 else { return }
      let stride = MemoryLayout<proc_fdinfo>.stride
      var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
      let filled = descriptors.withUnsafeMutableBytes { buffer in
        proc_pidinfo(pid, PROC_PIDLISTFDS, 0, buffer.baseAddress, Int32(buffer.count))
      }
      guard filled > 0 else { return }
      let length = Int32(MemoryLayout<vnode_fdinfo>.size)
      for descriptor in descriptors.prefix(Int(filled) / stride)
      where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
        var info = vnode_fdinfo()
        guard
          proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEINFO, &info, length) == length,
          info.pfi.fi_openflags & UInt32(FWRITE) != 0
        else { continue }
        let key = FileKey(device: info.pvi.vi_stat.vst_dev, inode: info.pvi.vi_stat.vst_ino)
        if keys.contains(key) { found.insert(key) }
      }
    }
  }
#endif
