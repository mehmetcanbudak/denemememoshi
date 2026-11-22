import Darwin
import Foundation

/// Fresh, disjoint roots, resolved before either is created. Existing inputs are never removed.
package struct QualificationPaths: Sendable {
  package let work: URL
  package let output: URL

  package init(work: URL, output: URL) throws {
    func absent(_ url: URL) throws {
      var information = stat()
      let result = lstat(url.path, &information)
      guard result == -1, errno == ENOENT else {
        throw DriverError.invalid("Input already exists or cannot be inspected: \(url.path)")
      }
    }
    try absent(work)
    try absent(output)
    let work = work.standardizedFileURL.resolvingSymlinksInPath()
    let output = output.standardizedFileURL.resolvingSymlinksInPath()
    try absent(work)
    try absent(output)
    // `resolvingSymlinksInPath` leaves a path that does not exist yet as written, so `/tmp/w`
    // and `/private/tmp/w/out` would look disjoint. Compare through each root's deepest
    // existing ancestor instead.
    func comparable(_ url: URL) throws -> String {
      var ancestor = url
      var missing: [String] = []
      var resolved = realpath(ancestor.path, nil)
      while resolved == nil, ancestor.path != "/" {
        missing.append(ancestor.lastPathComponent)
        ancestor.deleteLastPathComponent()
        resolved = realpath(ancestor.path, nil)
      }
      guard let resolved else {
        throw DriverError.invalid("Input ancestor cannot be resolved: \(url.path)")
      }
      defer { free(resolved) }
      // Conservatively reject case aliases even on a case-sensitive volume. These roots are
      // destructive-cleanup boundaries, not names whose case distinction must be preserved.
      return missing.reversed().reduce(URL(fileURLWithPath: String(cString: resolved))) {
        $0.appendingPathComponent($1)
      }.path.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
    let workKey = try comparable(work)
    let outputKey = try comparable(output)
    guard workKey != outputKey,
      !workKey.hasPrefix(outputKey + "/"), !outputKey.hasPrefix(workKey + "/")
    else { throw DriverError.invalid("Work and output roots must not overlap") }
    self.work = work
    self.output = output
  }

  /// mkdir, rather than an existence check followed by a possibly non-exclusive creation.
  package static func create(_ url: URL) throws {
    guard mkdir(url.path, 0o700) == 0 else {
      throw DriverError.invalid("Cannot exclusively create \(url.path) (errno \(errno))")
    }
  }
}
