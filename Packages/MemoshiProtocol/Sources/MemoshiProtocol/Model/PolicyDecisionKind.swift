/// The policy evaluator's decision (policy.md §2); unknown values never authorize work.
public enum PolicyDecisionKind: OpenEnum {
  case allow
  case ask
  case draft
  case deny
  case rewrite
  case unknown(String)

  /// Known decision wire names.
  public static let wireTable = OpenEnumTable<Self>([
    .allow: "allow", .ask: "ask", .draft: "draft", .deny: "deny", .rewrite: "rewrite",
  ])

  /// An unrecognized wire decision.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
