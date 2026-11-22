import CryptoKit
import Foundation

// Decisions behind the Mac Browser Review lab that need neither WebKit nor AppKit, kept here so
// they are tested. The lab itself stays a development review surface, not a bot tool.

// MARK: - Closed-window continuity

/// Statistics for one case of a background browser run, such as "detached in no window with every
/// app window closed". They are raw development measurements, not an S3 verdict.
public enum BrowserContinuity {
  /// One sample of a background run.
  public struct Sample: Equatable, Sendable {
    /// Seconds since the run started.
    public var elapsedSeconds: Double
    /// Whether every condition of the measured case held when the sample was taken.
    public var isInCase: Bool
    /// The page timer's rate since the previous reading, when one was measured.
    public var timerHz: Double?
    /// Whether both the image (`takeSnapshot`) and the DOM snapshot succeeded.
    public var snapshotsSucceeded: Bool

    /// Creates a sample from its measured values.
    public init(elapsedSeconds: Double, isInCase: Bool, timerHz: Double?, snapshotsSucceeded: Bool)
    {
      self.elapsedSeconds = elapsedSeconds
      self.isInCase = isInCase
      self.timerHz = timerHz
      self.snapshotsSucceeded = snapshotsSucceeded
    }
  }

  /// What the samples in one case show. Percentiles are nearest-rank; rate statistics are nil
  /// when no sample in the case measured a rate.
  public struct Summary: Codable, Equatable, Sendable {
    /// Samples taken while the case held.
    public var samples: Int
    /// Samples in the case that measured a timer rate.
    public var rates: Int
    /// Lowest measured rate, in hertz.
    public var minimumHz: Double?
    /// Median measured rate, in hertz.
    public var medianHz: Double?
    /// 95th-percentile measured rate, in hertz.
    public var p95Hz: Double?
    /// Highest measured rate, in hertz.
    public var maximumHz: Double?
    /// Samples in the case whose rate was below the threshold.
    public var samplesBelowThreshold: Int
    /// Samples in the case whose image and DOM snapshots both succeeded.
    public var snapshotSuccesses: Int
    /// The longest stretch, from its first to its last sample, of consecutive samples in the case
    /// with no interval longer than the allowed gap.
    public var longestCaseSpanSeconds: Double
    /// The longest such stretch in which every sample also measured a rate at or above the
    /// threshold and had both snapshots succeed.
    public var longestPassingSpanSeconds: Double
    /// The largest interval between consecutive samples of the run, in any case.
    public var largestGapSeconds: Double
  }

  /// Summarizes the samples of one run, in the order they were taken.
  public static func summarize(
    _ samples: [Sample], thresholdHz: Double, maximumGapSeconds: Double
  ) -> Summary {
    let inCase = samples.filter(\.isInCase)
    let rates = inCase.compactMap(\.timerHz)
    var caseSpan = SpanTracker()
    var passingSpan = SpanTracker()
    var largestGap = 0.0
    var previous: Sample?
    for sample in samples {
      let gap = previous.map { sample.elapsedSeconds - $0.elapsedSeconds }
      if let gap { largestGap = max(largestGap, gap) }
      let continues = gap.map { $0 <= maximumGapSeconds } ?? false
      caseSpan.add(sample.elapsedSeconds, included: sample.isInCase, continues: continues)
      let passes =
        sample.isInCase && sample.snapshotsSucceeded
        && (sample.timerHz.map { $0 >= thresholdHz } ?? false)
      passingSpan.add(sample.elapsedSeconds, included: passes, continues: continues)
      previous = sample
    }
    return Summary(
      samples: inCase.count, rates: rates.count, minimumHz: rates.min(),
      medianHz: nearestRank(rates, 0.5), p95Hz: nearestRank(rates, 0.95), maximumHz: rates.max(),
      samplesBelowThreshold: rates.filter { $0 < thresholdHz }.count,
      snapshotSuccesses: inCase.filter(\.snapshotsSucceeded).count,
      longestCaseSpanSeconds: caseSpan.longest, longestPassingSpanSeconds: passingSpan.longest,
      largestGapSeconds: largestGap)
  }

  /// The nearest-rank percentile: the smallest value with at least `fraction` of the values at or
  /// below it. Nil for no values.
  public static func nearestRank(_ values: [Double], _ fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    let sorted = values.sorted()
    let rank = Int((fraction * Double(sorted.count)).rounded(.up))
    return sorted[min(sorted.count, max(1, rank)) - 1]
  }

  /// Tracks runs of consecutive included samples. A sample continues the current run only if the
  /// previous sample was included too and the interval between them is allowed.
  private struct SpanTracker {
    var start: Double?
    var previousIncluded = false
    var longest = 0.0

    mutating func add(_ elapsed: Double, included: Bool, continues: Bool) {
      defer { previousIncluded = included }
      guard included else {
        start = nil
        return
      }
      if !(previousIncluded && continues) || start == nil { start = elapsed }
      if let start { longest = max(longest, elapsed - start) }
    }
  }
}

// MARK: - Sign-in Card fill decision

/// The rule a sign-in Card applies before filling: the credential's https origin, the page's
/// origin and the fields the Card showed must all still match (06 §8.5). Otherwise nothing fills.
public enum BrowserSignIn {
  /// Why a fill was refused. Raw values are stable export codes.
  public enum Refusal: String, Codable, Sendable, CaseIterable {
    /// The credential is not bound to an https origin.
    case insecureOrigin
    /// The page's origin, the Card's origin and the credential's origin are not all the same.
    case originMismatch
    /// The main frame committed a new document after the Card was offered.
    case pageChanged
    /// The form no longer shows the fields the Card showed.
    case fieldsChanged
  }

  /// What a Card showed when it was offered.
  public struct CardBinding: Equatable, Sendable {
    /// The page origin the Card was offered for.
    public let origin: String
    /// The main frame's commit count when the Card was offered.
    public let commit: Int
    /// An identity for the user-name field, stable while the form is unchanged.
    public let usernameField: String
    /// An identity for the password field, stable while the form is unchanged.
    public let passwordField: String

    /// Creates the binding a Card keeps until it fills or is dismissed.
    public init(origin: String, commit: Int, usernameField: String, passwordField: String) {
      self.origin = origin
      self.commit = commit
      self.usernameField = usernameField
      self.passwordField = passwordField
    }
  }

  /// What the page shows when the fill is requested.
  public struct PageState: Equatable, Sendable {
    /// The page's origin, or nil when it has none the Card can use.
    public let origin: String?
    /// The main frame's current commit count.
    public let commit: Int
    /// The user-name field the page shows now, if any.
    public let usernameField: String?
    /// The password field the page shows now, if any.
    public let passwordField: String?

    /// Creates the page state read just before filling.
    public init(origin: String?, commit: Int, usernameField: String?, passwordField: String?) {
      self.origin = origin
      self.commit = commit
      self.usernameField = usernameField
      self.passwordField = passwordField
    }
  }

  /// Nil when the fill may proceed; otherwise the first reason it must not.
  public static func refusal(card: CardBinding, credentialOrigin: String, page: PageState)
    -> Refusal?
  {
    guard
      BrowserAuthorization.canonicalOrigin(credentialOrigin, requireHTTPS: true) == credentialOrigin
    else {
      return .insecureOrigin
    }
    guard card.origin == credentialOrigin, page.origin == card.origin else {
      return .originMismatch
    }
    guard page.commit == card.commit else { return .pageChanged }
    guard page.usernameField == card.usernameField, page.passwordField == card.passwordField
    else { return .fieldsChanged }
    return nil
  }
}

// MARK: - Canary credential

/// A synthetic sign-in credential for the development review Card. It stands in for a Keychain
/// broker item and is never a real login. Descriptions redact both values.
public struct BrowserReviewCanary: Equatable, Sendable {
  /// Why a harness canary file was refused.
  public enum ParseError: Error, Equatable, Sendable {
    /// The file is not a JSON object with string `origin`, `username` and `password`.
    case malformed
    /// The canary is bound to another origin.
    case wrongOrigin
    /// A value is too short, too long or contains control characters.
    case invalidValue
  }

  /// Every generated canary starts with this prefix, shared with the qualification harness.
  public static let prefix = "mqcanary_"

  /// The https origin this canary may fill.
  public let origin: String
  /// The synthetic user name.
  public let username: String
  /// The synthetic password.
  public let password: String

  /// Draws a fresh canary pair from the system generator. `/` and `+` make encoded forms differ
  /// from the raw value, so scanners check them meaningfully.
  public static func generate(origin: String) -> BrowserReviewCanary {
    var generator = SystemRandomNumberGenerator()
    let alphabet = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    func block(_ count: Int) -> String {
      String((0..<count).map { _ in alphabet[Int.random(in: 0..<62, using: &generator)] })
    }
    return BrowserReviewCanary(
      origin: origin, username: prefix + "user_" + block(20) + "/" + block(6) + "+" + block(6),
      password: prefix + "pass_" + block(24) + "/" + block(8) + "+" + block(8))
  }

  /// Parses a harness canary file: a JSON object with `origin`, `username` and `password`.
  public static func parse(_ data: Data, expectedOrigin: String) throws -> BrowserReviewCanary {
    guard data.count <= 4_096,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let origin = object["origin"] as? String, let username = object["username"] as? String,
      let password = object["password"] as? String
    else { throw ParseError.malformed }
    guard origin == expectedOrigin else { throw ParseError.wrongOrigin }
    guard isAcceptable(username), isAcceptable(password) else { throw ParseError.invalidValue }
    return BrowserReviewCanary(origin: origin, username: username, password: password)
  }

  /// Lowercase hexadecimal SHA-256 of the UTF-8 text, as a page computes it with SubtleCrypto.
  public static func sha256Hex(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }

  /// A short, nonsecret digest prefix that identifies the user name in reports.
  public var usernameFingerprint: String { String(Self.sha256Hex(username).prefix(12)) }

  /// A short, nonsecret digest prefix that identifies the password in reports.
  public var passwordFingerprint: String { String(Self.sha256Hex(password).prefix(12)) }

  private static func isAcceptable(_ value: String) -> Bool {
    (8...256).contains(value.count)
      && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
  }
}

extension BrowserReviewCanary: CustomStringConvertible, CustomDebugStringConvertible,
  CustomReflectable
{
  /// The origin and fingerprints only.
  public var description: String {
    "BrowserReviewCanary(origin: \(origin), user: \(usernameFingerprint), "
      + "password: \(passwordFingerprint))"
  }

  /// The same redacted form as `description`.
  public var debugDescription: String { description }

  /// A mirror without the secret values.
  public var customMirror: Mirror {
    Mirror(
      self,
      children: [
        "origin": origin, "usernameFingerprint": usernameFingerprint,
        "passwordFingerprint": passwordFingerprint,
      ])
  }
}
