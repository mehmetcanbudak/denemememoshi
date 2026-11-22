/// The trusted host callback's effect knowledge, separate from whether its output is an error.
/// This is not the SDK's future interrupted-step settlement or a read-only outcome check.
public enum RuntimeToolEffectOutcome: Equatable, Sendable {
  /// The callback knows its effects completed; Pi must still commit the corresponding result.
  case completed
  /// The callback proves it performed no effect, or its transaction rolled back completely.
  case notApplied
  /// Effects may remain. No model continuation, automatic retry or Bypass may clear this.
  case unknown
}

/// A host callback may use this only when it can prove no effect occurred. Other thrown
/// errors after unsafe dispatch are conservatively unknown, regardless of their wording.
public enum RuntimeToolExecutionError: Error, Equatable, Sendable {
  case notApplied
}
