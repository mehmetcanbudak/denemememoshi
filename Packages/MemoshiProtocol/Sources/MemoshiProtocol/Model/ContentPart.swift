/// One piece of a message's content: text, a mention, or an attachment reference
/// (protocol.md §5.3 `Part`). On the wire it is an object tagged by `type`.
public enum ContentPart: Hashable, Sendable {
  case text(TextPart)
  case mention(MentionPart)
  case attachment(AttachmentPart)
  /// A part type this build does not know, kept whole.
  case unknown(type: String, raw: JSONValue)
}

extension ContentPart: Codable, WireShaped {
  private enum TagKey: String, CodingKey {
    case type
  }

  /// The parts by their `type` tag.
  public static var wireShape: WireShape {
    .union(
      discriminator: "type",
      variants: [
        WireVariant(tag: "text", fields: [TextPart.self]),
        WireVariant(tag: "mention", fields: [MentionPart.self]),
        WireVariant(tag: "attachment", fields: [AttachmentPart.self]),
      ])
  }

  /// Decodes a part by its `type`. An unknown type becomes `.unknown` unless decoding is strict.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: TagKey.self)
    let type = try container.decode(String.self, forKey: .type)
    switch type {
    case "text": self = .text(try TextPart(from: decoder))
    case "mention": self = .mention(try MentionPart(from: decoder))
    case "attachment": self = .attachment(try AttachmentPart(from: decoder))
    default:
      if decoder.isStrictProtocolDecoding {
        throw DecodingError.dataCorruptedError(
          forKey: .type, in: container, debugDescription: "Unknown content part type \(type)")
      }
      self = .unknown(type: type, raw: try JSONValue(from: decoder))
    }
  }

  /// Encodes the part's fields beside its `type`.
  public func encode(to encoder: any Encoder) throws {
    let tag: String
    switch self {
    case .text(let part):
      tag = "text"
      try part.encode(to: encoder)
    case .mention(let part):
      tag = "mention"
      try part.encode(to: encoder)
    case .attachment(let part):
      tag = "attachment"
      try part.encode(to: encoder)
    case .unknown(_, let raw):
      try raw.encode(to: encoder)
      return
    }
    var container = encoder.container(keyedBy: TagKey.self)
    try container.encode(tag, forKey: .type)
  }
}

/// Plain text.
public struct TextPart: Codable, Hashable, Sendable {
  /// The text.
  public var text: String

  /// Creates a text part.
  public init(text: String) {
    self.text = text
  }
}

/// A mention of a bot, project, file or other object.
public struct MentionPart: Codable, Hashable, Sendable {
  /// What is mentioned.
  public var kind: MentionKind
  /// The mentioned object's ID, or a path for a file.
  public var id: String
  /// The text shown for the mention.
  public var label: String

  /// Creates a mention.
  public init(kind: MentionKind, id: String, label: String) {
    self.kind = kind
    self.id = id
    self.label = label
  }
}

/// A reference to an attachment registered with `attachments.register`.
public struct AttachmentPart: Codable, Hashable, Sendable {
  /// The reference `attachments.register` returned.
  public var attachmentRef: String
  /// The file name.
  public var name: String
  /// The MIME type.
  public var mimeType: String
  /// The size in bytes.
  public var sizeBytes: Int64

  /// Creates an attachment reference.
  public init(attachmentRef: String, name: String, mimeType: String, sizeBytes: Int64) {
    self.attachmentRef = attachmentRef
    self.name = name
    self.mimeType = mimeType
    self.sizeBytes = sizeBytes
  }
}

/// What a mention names.
public enum MentionKind: OpenEnum {
  case bot
  case project
  case file
  case task
  case card
  case memory
  case unknown(String)

  /// The known values.
  public static let wireTable = OpenEnumTable<Self>([
    .bot: "bot", .project: "project", .file: "file", .task: "task", .card: "card",
    .memory: "memory",
  ])

  /// The unrecognized wire value, if any.
  public var unknownRawValue: String? {
    if case .unknown(let raw) = self { raw } else { nil }
  }
}
