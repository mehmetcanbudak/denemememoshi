import Foundation
import NIOHTTP1

/// One client's masked credential: a random placeholder the sandbox sees in place of the value.
struct EgressMask: Sendable {
  let name: String
  let secretRef: String
  let placeholder: String
  let hosts: Set<String>
  let value: @Sendable () async throws -> String

  init(_ binding: EgressSecretBinding) {
    name = binding.name
    secretRef = binding.secretRef
    placeholder = "MEMOSHI_MASK_" + EgressRandom.hex(bytes: 16)
    hosts = binding.hosts
    value = binding.value
  }
}

enum EgressRandom {
  /// Lowercase hex of `bytes` random bytes from the system generator.
  static func hex(bytes: Int) -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<bytes).map { _ in
      let byte = UInt8.random(in: 0...255, using: &generator)
      let digits = Array("0123456789abcdef")
      return String([digits[Int(byte >> 4)], digits[Int(byte & 0x0f)]])
    }.joined()
  }
}

/// Placeholder detection and replacement in request headers (policy.md §13): raw header values
/// and `Basic` credentials, decoded and re-encoded. Bodies, paths and queries are never changed.
enum EgressHeaderMasks {
  /// The masks whose placeholder occurs in the request target or any header value, including
  /// inside decoded `Basic` credentials.
  static func present(in head: HTTPRequestHead, masks: [EgressMask]) -> [EgressMask] {
    present(in: head.headers, target: head.uri, masks: masks)
  }

  /// The masks whose placeholder occurs in these header values: with the headers the gateway
  /// will forward, the values `substitute` would replace.
  static func present(
    in headers: HTTPHeaders, target: String? = nil, masks: [EgressMask]
  ) -> [EgressMask] {
    guard !masks.isEmpty else { return [] }
    var texts = target.map { [$0] } ?? []
    for (_, value) in headers {
      texts.append(value)
      if let decoded = basicCredentials(value) { texts.append(decoded) }
    }
    return masks.filter { mask in texts.contains { $0.contains(mask.placeholder) } }
  }

  /// Replaces placeholders with their values in every header value.
  static func substitute(
    _ headers: inout HTTPHeaders, values: [(placeholder: String, value: String)]
  ) {
    guard !values.isEmpty else { return }
    var rewritten = HTTPHeaders()
    for (name, value) in headers {
      var result = value
      if var decoded = basicCredentials(value),
        values.contains(where: { decoded.contains($0.placeholder) })
      {
        for item in values {
          decoded = decoded.replacingOccurrences(of: item.placeholder, with: item.value)
        }
        result = "Basic " + Data(decoded.utf8).base64EncodedString()
      }
      for item in values {
        result = result.replacingOccurrences(of: item.placeholder, with: item.value)
      }
      rewritten.add(name: name, value: result)
    }
    headers = rewritten
  }

  private static func basicCredentials(_ value: String) -> String? {
    let parts = value.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2, parts[0].lowercased() == "basic",
      let data = Data(base64Encoded: String(parts[1]).trimmingCharacters(in: .whitespaces))
    else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// Masks echoed secret values in responses before they reach the sandbox: raw, hex, percent,
/// JSON-escaped and base64/base64url forms at every byte alignment. Every match is replaced by
/// `*` of the same length, so `Content-Length` and chunk framing stay valid. This is defense in
/// depth; an encoding it does not know defeats it (policy.md §13).
///
/// Forms live in one trie, so scanning costs a step per byte and per form still matching there,
/// whatever the number of forms. A stream holds back only bytes that may yet complete a form.
struct EgressEchoScrubber: Sendable {
  /// How many included values recognize each exact form.
  private var forms: [[UInt8]: Int] = [:]
  private var trie = EgressFormTrie()
  /// Stream bytes not yet released, with those inside a match marked, and the forms still
  /// matching at their end, earliest start first.
  private var pending: [UInt8] = []
  private var covered: [Bool] = []
  private var partial: [EgressFormTrie.Partial] = []

  init(values: [String]) {
    for value in values { include(value) }
  }

  /// Adds recognized forms of a newly released value without discarding older protections.
  mutating func include(_ value: String) {
    guard !value.isEmpty else { return }
    for form in Set(Self.forms(of: value)) where form.count >= 6 {
      forms[form, default: 0] += 1
      if forms[form] == 1 { trie.insert(form) }
    }
    rescan()
  }

  /// Drops what `include` added for a value that no longer needs protection, such as an ended
  /// call's token. A form another included value also recognizes stays.
  mutating func exclude(_ value: String) {
    for form in Set(Self.forms(of: value)) where form.count >= 6 {
      guard let count = forms[form] else { continue }
      forms[form] = count > 1 ? count - 1 : nil
      if count == 1 { trie.remove(form) }
    }
    rescan()
  }

  /// Takes a gateway's current protections and keeps this stream's own buffered response bytes.
  mutating func adoptProtections(from source: Self) {
    forms = source.forms
    trie = source.trie
    rescan()
  }

  var isEmpty: Bool { forms.isEmpty }

  /// Distinct recognized forms.
  var formCount: Int { forms.count }

  /// Appends response bytes and returns those that can no longer be part of a match.
  mutating func push(_ bytes: some Sequence<UInt8>) -> [UInt8] {
    guard !forms.isEmpty || !pending.isEmpty else { return Array(bytes) }
    let start = pending.count
    pending.append(contentsOf: bytes)
    covered.append(contentsOf: repeatElement(false, count: pending.count - start))
    _ = Self.scan(
      pending, start..<pending.count, trie: trie, forms: forms, exact: true, partial: &partial,
      covered: &covered)
    return release(partial.first?.start ?? pending.count)
  }

  /// Returns the retained tail at the end of the response.
  mutating func finish() -> [UInt8] {
    partial.removeAll()
    return release(pending.count)
  }

  /// A header or decision field with every recognized form masked. Header names and normalized
  /// destination metadata use ASCII-insensitive matching; body bytes remain case-sensitive.
  func scrub(_ text: String, ignoringASCIICase: Bool = false) -> String {
    guard !forms.isEmpty, text.utf8.count >= 6 else { return text }
    var bytes = Array(text.utf8)
    var covered = [Bool](repeating: false, count: bytes.count)
    var partial: [EgressFormTrie.Partial] = []
    guard
      Self.scan(
        bytes, 0..<bytes.count, trie: trie, forms: forms, exact: !ignoringASCIICase,
        partial: &partial, covered: &covered)
    else { return text }
    for index in bytes.indices where covered[index] { bytes[index] = UInt8(ascii: "*") }
    return String(decoding: bytes, as: UTF8.self)
  }

  /// Field names are dropped on a match, even when masking would leave the same `*` bytes.
  func containsRecognizedForm(in text: String, ignoringASCIICase: Bool = false) -> Bool {
    guard !forms.isEmpty, text.utf8.count >= 6 else { return false }
    let bytes = Array(text.utf8)
    var covered = [Bool](repeating: false, count: bytes.count)
    var partial: [EgressFormTrie.Partial] = []
    return Self.scan(
      bytes, 0..<bytes.count, trie: trie, forms: forms, exact: !ignoringASCIICase,
      partial: &partial, covered: &covered)
  }

  /// Hands out the first `count` pending bytes with their matches masked. The bytes kept stay
  /// unmasked, so a longer form that contains an already matched one can still complete.
  private mutating func release(_ count: Int) -> [UInt8] {
    var ready = Array(pending[..<count])
    for index in 0..<count where covered[index] { ready[index] = UInt8(ascii: "*") }
    pending.removeFirst(count)
    covered.removeFirst(count)
    for index in partial.indices { partial[index].start -= count }
    return ready
  }

  /// After the forms changed, the pending bytes are matched afresh against the current ones.
  private mutating func rescan() {
    partial.removeAll()
    guard !pending.isEmpty else { return }
    _ = Self.scan(
      pending, 0..<pending.count, trie: trie, forms: forms, exact: true, partial: &partial,
      covered: &covered)
  }

  /// Advances every form still matching through `range`, marks each completed form's bytes in
  /// `covered` and reports whether any completed. The trie is ASCII-case-folded; `exact`
  /// accepts a completed form only when its bytes equal a recognized form's.
  private static func scan(
    _ bytes: [UInt8], _ range: Range<Int>, trie: EgressFormTrie, forms: [[UInt8]: Int],
    exact: Bool, partial: inout [EgressFormTrie.Partial], covered: inout [Bool]
  ) -> Bool {
    var found = false
    for index in range {
      let byte = EgressFormTrie.folded(bytes[index])
      var kept = 0
      // The earliest verified start covers every later one ending at this byte.
      var matched = false
      for position in partial.indices {
        let node = trie.next(partial[position].node, byte)
        guard node >= 0 else { continue }
        let start = partial[position].start
        if !matched, trie.ends(node), !exact || forms[Array(bytes[start...index])] != nil {
          matched = true
          for offset in start...index { covered[offset] = true }
        }
        // A form with no longer form beyond it has nothing left to wait for.
        guard trie.continues(node) else { continue }
        partial[kept] = EgressFormTrie.Partial(node: node, start: start)
        kept += 1
      }
      partial.removeSubrange(kept...)
      let node = trie.next(EgressFormTrie.root, byte)
      if node >= 0 {
        if !matched, trie.ends(node), !exact || forms[[bytes[index]]] != nil {
          matched = true
          covered[index] = true
        }
        if trie.continues(node) {
          partial.append(EgressFormTrie.Partial(node: node, start: index))
        }
      }
      found = found || matched
    }
    return found
  }

  static func forms(of value: String) -> [[UInt8]] {
    let raw = Array(value.utf8)
    var result: [[UInt8]] = [raw]
    let hex = raw.flatMap { [Self.digits[Int($0 >> 4)], Self.digits[Int($0 & 0x0f)]] }
    result.append(hex)
    result.append(hex.map { $0 >= 0x61 ? $0 - 0x20 : $0 })
    var unreserved = CharacterSet.alphanumerics
    unreserved.insert(charactersIn: "-._~")
    if let percent = value.addingPercentEncoding(withAllowedCharacters: unreserved) {
      result.append(Array(percent.utf8))
      result.append(Array(Self.lowercasingPercentEscapes(percent).utf8))
    }
    for escapingSlash in [false, true] {
      for uppercase in [false, true] {
        result.append(Self.jsonEscaped(raw, escapingSlash: escapingSlash, uppercase: uppercase))
      }
    }
    result.append(
      value.utf16.flatMap { unit in
        [0x5c, 0x75] + [12, 8, 4, 0].map { Self.digits[Int(unit >> $0) & 0x0f] }
      })
    for prefix in 0..<3 {
      let encoded = Data(Array(repeating: 0, count: prefix) + raw).base64EncodedString()
      // Drop the characters that also encode the prefix or the trailing partial group.
      let skip = prefix == 0 ? 0 : 4
      let whole = ((prefix + raw.count) / 3) * 4
      guard whole > skip else { continue }
      let core = String(encoded.dropFirst(skip).prefix(whole - skip))
      result.append(Array(core.utf8))
      let url = core.replacingOccurrences(of: "+", with: "-").replacingOccurrences(
        of: "/", with: "_")
      result.append(Array(url.utf8))
    }
    return result
  }

  private static let digits = Array("0123456789abcdef".utf8)

  /// The value as a JSON string's content: the escapes every encoder must write (RFC 8259 §7),
  /// the optional `\/` some write, and other control characters as `\u00XX` in either hex case.
  private static func jsonEscaped(_ raw: [UInt8], escapingSlash: Bool, uppercase: Bool) -> [UInt8] {
    var result: [UInt8] = []
    for byte in raw {
      switch byte {
      case 0x22: result.append(contentsOf: "\\\"".utf8)
      case 0x5c: result.append(contentsOf: "\\\\".utf8)
      case 0x2f where escapingSlash: result.append(contentsOf: "\\/".utf8)
      case 0x08: result.append(contentsOf: "\\b".utf8)
      case 0x0c: result.append(contentsOf: "\\f".utf8)
      case 0x0a: result.append(contentsOf: "\\n".utf8)
      case 0x0d: result.append(contentsOf: "\\r".utf8)
      case 0x09: result.append(contentsOf: "\\t".utf8)
      case 0..<0x20:
        result.append(contentsOf: String(format: uppercase ? "\\u%04X" : "\\u%04x", byte).utf8)
      default: result.append(byte)
      }
    }
    return result
  }

  private static func lowercasingPercentEscapes(_ text: String) -> String {
    var output = ""
    var remaining = 0
    for character in text {
      if character == "%" {
        remaining = 2
        output.append(character)
      } else if remaining > 0 {
        remaining -= 1
        output.append(contentsOf: character.lowercased())
      } else {
        output.append(character)
      }
    }
    return output
  }
}

/// Recognized forms as a byte trie over their ASCII-lowercased bytes. Nodes are indices into
/// parallel arrays; a removed form's nodes are reused, so the trie does not grow with forms that
/// come and go.
struct EgressFormTrie: Sendable {
  /// A form still matching a text: the node reached and where in the text it began.
  struct Partial: Sendable {
    var node: Int32
    var start: Int
  }

  static let root: Int32 = 0

  /// The root's children by byte; every other node's children are a short sibling list.
  private var first = [Int32](repeating: -1, count: 256)
  private var byte: [UInt8] = [0]
  private var parent: [Int32] = [-1]
  private var child: [Int32] = [-1]
  private var sibling: [Int32] = [-1]
  /// Forms ending at each node; two forms differing only in ASCII case end at the same one.
  private var endings: [Int32] = [0]
  private var free: [Int32] = []

  static func folded(_ byte: UInt8) -> UInt8 {
    byte &- 65 < 26 ? byte | 0x20 : byte
  }

  /// The node `byte`, already folded, leads to from `node`, or -1.
  func next(_ node: Int32, _ byte: UInt8) -> Int32 {
    if node == Self.root { return first[Int(byte)] }
    var candidate = child[Int(node)]
    while candidate >= 0, self.byte[Int(candidate)] != byte { candidate = sibling[Int(candidate)] }
    return candidate
  }

  func ends(_ node: Int32) -> Bool { endings[Int(node)] > 0 }

  func continues(_ node: Int32) -> Bool { child[Int(node)] >= 0 }

  mutating func insert(_ form: [UInt8]) {
    var node = Self.root
    for raw in form {
      let byte = Self.folded(raw)
      let found = next(node, byte)
      node = found >= 0 ? found : add(byte, under: node)
    }
    endings[Int(node)] += 1
  }

  /// Removes one form `insert` added, and the nodes only it used.
  mutating func remove(_ form: [UInt8]) {
    var node = Self.root
    for raw in form {
      node = next(node, Self.folded(raw))
      guard node >= 0 else { return }
    }
    guard node != Self.root, endings[Int(node)] > 0 else { return }
    endings[Int(node)] -= 1
    while node != Self.root, endings[Int(node)] == 0, child[Int(node)] < 0 {
      let above = parent[Int(node)]
      unlink(node, from: above)
      free.append(node)
      node = above
    }
  }

  private mutating func add(_ byte: UInt8, under above: Int32) -> Int32 {
    let node: Int32
    if let reused = free.popLast() {
      node = reused
      self.byte[Int(node)] = byte
      parent[Int(node)] = above
      child[Int(node)] = -1
      sibling[Int(node)] = -1
    } else {
      node = Int32(self.byte.count)
      self.byte.append(byte)
      parent.append(above)
      child.append(-1)
      sibling.append(-1)
      endings.append(0)
    }
    if above == Self.root {
      first[Int(byte)] = node
    } else {
      sibling[Int(node)] = child[Int(above)]
      child[Int(above)] = node
    }
    return node
  }

  private mutating func unlink(_ node: Int32, from above: Int32) {
    if above == Self.root {
      first[Int(byte[Int(node)])] = -1
      return
    }
    if child[Int(above)] == node {
      child[Int(above)] = sibling[Int(node)]
      return
    }
    var previous = child[Int(above)]
    while previous >= 0, sibling[Int(previous)] != node { previous = sibling[Int(previous)] }
    if previous >= 0 { sibling[Int(previous)] = sibling[Int(node)] }
  }
}
