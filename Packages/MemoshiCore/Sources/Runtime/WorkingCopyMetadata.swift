import Darwin

extension WorkingCopyFS {
  /// The content-only engine cannot represent ACLs, file flags, user attributes or forks.
  /// Inspect only metadata on the already-proven descriptor; never clear or normalize it.
  /// macOS's automatically stamped provenance stays owned by the OS, not copied or edited.
  static func requireContentOnlyMetadata(_ descriptor: Int32, metadata: stat) throws {
    guard metadata.st_flags == 0 else { throw WorkingCopyFailure.unsupportedMetadata }
    try requireContentOnlyAttributes(descriptor)
    errno = 0
    if let acl = acl_get_fd_np(descriptor, ACL_TYPE_EXTENDED) {
      acl_free(UnsafeMutableRawPointer(acl))
      throw WorkingCopyFailure.unsupportedMetadata
    }
    // On an existing, fstat-proven descriptor, Darwin reports an absent extended ACL as
    // ENOENT. Unsupported filesystems, denied inspection and every other error refuse.
    let code = errno
    guard code == ENOENT else {
      throw WorkingCopyFailure.system(operation: "inspect extended ACL", code: code)
    }
  }

  private static func requireContentOnlyAttributes(_ descriptor: Int32) throws {
    let count = flistxattr(descriptor, nil, 0, XATTR_SHOWCOMPRESSION)
    guard count >= 0 else { throw failure("inspect extended attributes") }
    if count == 0 { return }
    // This is the sole OS-managed exception, observed on ordinary newly created files.
    // No application tag, FinderInfo, resource fork or unknown attribute is ignored.
    let provenance = "com.apple.provenance"
    let capacity = provenance.utf8.count + 1
    guard count == capacity else { throw WorkingCopyFailure.unsupportedMetadata }
    try withUnsafeTemporaryAllocation(of: UInt8.self, capacity: capacity) { bytes in
      let read = bytes.withMemoryRebound(to: CChar.self) { names in
        flistxattr(descriptor, names.baseAddress, names.count, XATTR_SHOWCOMPRESSION)
      }
      guard read >= 0 else { throw failure("read extended attribute names") }
      guard read == capacity, bytes[capacity - 1] == 0,
        bytes.dropLast().elementsEqual(provenance.utf8)
      else { throw WorkingCopyFailure.unsupportedMetadata }
    }
  }
}
