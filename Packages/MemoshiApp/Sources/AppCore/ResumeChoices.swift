import MemoshiProtocol

extension Card {
  /// What a pending Resume card (D51) offers now, in its order: Run again, Skip, Mark as done,
  /// or Skip and Mark as done once the engine has ended the interrupted call. Empty for any
  /// other card.
  public var resumeChoices: [ResumeAction] {
    guard kind == .resume, status == .pending, case .object(let fields) = payload,
      case .array(let values)? = fields["actions"]
    else { return [] }
    return values.compactMap { value -> ResumeAction? in
      guard case .string(let raw) = value else { return nil }
      let action = ResumeAction(rawValue: raw)
      return action.isKnown ? action : nil
    }
  }
}
