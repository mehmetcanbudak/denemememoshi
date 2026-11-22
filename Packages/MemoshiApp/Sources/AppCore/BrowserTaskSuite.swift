import CryptoKit
import Foundation

/// A user-selected S3 recipe. Decoding a recipe does not authorize it or run any step.
/// The native review screen shows every site and enabled effect before explicit approval.
public struct BrowserTaskSuite: Decodable, Sendable {
  /// Stable export-safe recipe identity, restricted to ASCII identifier characters.
  public let id: String
  /// Exact sites and permissions requested by this suite.
  public let sites: [BrowserAuthorization.Site]
  /// Independently scored tasks, run once without retrying uncertain actions.
  public let tasks: [TaskRecipe]

  /// One explicit workflow on one selected site.
  public struct TaskRecipe: Decodable, Sendable {
    /// Content-free identifier.
    public let id: String
    /// Exact approved origin.
    public let site: String
    /// Steps in execution order.
    public let steps: [Step]
  }

  /// Accessible selectors are data, never executable JavaScript or instructions.
  public struct Selector: Decodable, Sendable {
    /// Exact accessible role from a fresh snapshot.
    public let role: String
    /// Exact accessible name; zero or multiple matches fail closed.
    public let name: String
    /// Exact frame origin, when a subframe is intended. Nil means main frame only.
    public let frameOrigin: String?
  }

  /// A bounded operation and its expected result. Text remains in memory, never in reports.
  public struct Step: Decodable, Sendable {
    /// Allowed native browser operations; no arbitrary script/eval escape hatch.
    public enum Operation: String, Decodable, Sendable {
      case navigate, snapshot, click, type, select, expect, download, signIn
    }
    /// Which operation to run.
    public let operation: Operation
    /// Exact URL for navigation, constrained to a suite-approved origin.
    public let url: String?
    /// A selector into a newly captured snapshot.
    public let selector: Selector?
    /// Noncredential input or an expected visible value.
    public let text: String?
    /// Native input requested on Mac. False uses the shared DOM path.
    public let nativeInput: Bool?
    /// Stable expected refusal code, for denial-path recipes only.
    public let expectedDenial: String?
  }

  /// Refuses malformed/oversized recipes before any page, account or network is touched.
  public static func decode(_ data: Data) throws -> BrowserTaskSuite {
    guard data.count <= 1_000_000 else { throw ValidationError.invalidSuite }
    let suite = try JSONDecoder().decode(Self.self, from: data)
    guard identifier(suite.id), (1...30).contains(suite.sites.count),
      (1...40).contains(suite.tasks.count),
      Set(suite.sites.map(\.origin)).count == suite.sites.count,
      Set(suite.tasks.map(\.id)).count == suite.tasks.count
    else { throw ValidationError.invalidSuite }
    for site in suite.sites {
      guard
        let validated = try? BrowserAuthorization.Site(
          origin: site.origin,
          interact: site.interact, signIn: site.signIn, ownedFixture: site.ownedFixture),
        validated == site
      else { throw ValidationError.invalidSuite }
      if !site.ownedFixture {
        guard let host = URL(string: site.origin)?.host(), !host.hasSuffix(".invalid"),
          host != "localhost", host.contains("."), host.last?.isNumber == false,
          !host.contains(":"), !host.hasSuffix(".local")
        else { throw ValidationError.invalidSuite }
      }
    }
    for task in suite.tasks {
      guard identifier(task.id), suite.sites.contains(where: { $0.origin == task.site }),
        (1...50).contains(task.steps.count), let final = task.steps.last,
        final.operation == .expect || final.operation == .download || final.operation == .signIn
          || final.expectedDenial != nil
      else { throw ValidationError.invalidSuite }
      for step in task.steps {
        if let denial = step.expectedDenial, !identifier(denial) {
          throw ValidationError.invalidSuite
        }
        if let selector = step.selector {
          guard (1...120).contains(selector.role.count), selector.name.count <= 500,
            selector.frameOrigin.map({ origin in suite.sites.contains { $0.origin == origin } })
              ?? true
          else { throw ValidationError.invalidSuite }
        }
        switch step.operation {
        case .navigate:
          guard let text = step.url, let url = URL(string: text), text.utf8.count <= 2048,
            let origin = BrowserAuthorization.origin(of: url),
            suite.sites.contains(where: { $0.origin == origin })
          else { throw ValidationError.invalidSuite }
        case .click, .download, .select, .type:
          guard step.selector != nil else { throw ValidationError.invalidSuite }
        case .expect:
          guard step.selector != nil || step.text != nil else { throw ValidationError.invalidSuite }
        case .snapshot, .signIn: break
        }
        if let text = step.text, text.utf8.count > 20_000 { throw ValidationError.invalidSuite }
      }
    }
    return suite
  }

  /// Hash of the selected bytes, for comparing reports without retaining the recipe's contents.
  public static func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func identifier(_ text: String) -> Bool {
    (1...80).contains(text.utf8.count)
      && text.utf8.allSatisfy {
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
          || $0 == 45 || $0 == 95 || $0 == 46
      }
  }

  /// Recipe validation errors contain none of the imported text.
  public enum ValidationError: Error, Sendable { case invalidSuite }
}

/// Durable, page-text-free results. Loading an interrupted run never replays its actions.
public struct BrowserTaskRun: Codable, Sendable, Identifiable {
  /// Run lifetime. A persisted running record is changed to interrupted on app reopen.
  public enum State: String, Codable, Sendable { case running, completed, cancelled, interrupted }
  /// One attempted step; a successful API call alone is not an assertion of task success.
  public struct StepResult: Codable, Sendable {
    /// Task identity from the validated suite.
    public let taskID: String
    /// Zero-based step index.
    public let index: Int
    /// Operation code.
    public let operation: String
    /// Whether the declared assertion/refusal was satisfied.
    public let succeeded: Bool
    /// Stable sanitized error/refusal code, or nil.
    public let code: String?
    /// Measured monotonic duration.
    public let durationMs: Double

    /// Creates a result without page/input/account text.
    public init(
      taskID: String, index: Int, operation: String, succeeded: Bool, code: String?,
      durationMs: Double
    ) {
      self.taskID = taskID
      self.index = index
      self.operation = operation
      self.succeeded = succeeded
      self.code = code
      self.durationMs = durationMs
    }
  }

  /// Fresh run identity.
  public let id: UUID
  /// Recipe identity and byte digest only.
  public let suiteID: String
  /// SHA-256 of the selected recipe bytes.
  public let suiteDigest: String
  /// Selected real/public origin count, never including owned fixtures.
  public let realSiteCount: Int
  /// Number of independently scored tasks.
  public let taskCount: Int
  /// Run start.
  public let startedAt: Date
  /// Run settlement, nil while active.
  public var endedAt: Date?
  /// Current lifetime state.
  public var state: State
  /// Tasks whose every step and final assertion succeeded.
  public var successfulTasks: [String]
  /// Every attempted step, in execution order.
  public var steps: [StepResult]

  /// Starts an evidence record, without implying any site/task gate passes.
  public init(suite: BrowserTaskSuite, digest: String) {
    id = UUID()
    suiteID = suite.id
    suiteDigest = digest
    realSiteCount = suite.sites.filter { !$0.ownedFixture }.count
    taskCount = suite.tasks.count
    startedAt = Date()
    endedAt = nil
    state = .running
    successfulTasks = []
    steps = []
  }

  /// Marks a reopened in-flight record as uncertain. It never authorizes resuming or replaying
  /// its action; the native host may display/export the record only.
  public mutating func interruptIfRunning(at date: Date = Date()) {
    guard state == .running else { return }
    state = .interrupted
    endedAt = date
    for index in steps.indices where steps[index].code == "inFlight" {
      let step = steps[index]
      steps[index] = StepResult(
        taskID: step.taskID, index: step.index, operation: step.operation,
        succeeded: false, code: "interruptedOutcomeUnknown", durationMs: step.durationMs)
    }
  }
}
