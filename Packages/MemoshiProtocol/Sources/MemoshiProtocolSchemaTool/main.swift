import Foundation
import MemoshiProtocolSchema

// memoshi-protocol-schema: prints the protocol's JSON Schema, derived from the Swift types, as
// canonical JSON on standard output. scripts/protocol-schema.sh writes it to
// protocol/protocol.schema.json, or compares it with the committed file.
do {
  let text = try ProtocolSchema.canonicalText()
  FileHandle.standardOutput.write(Data(text.utf8))
} catch {
  FileHandle.standardError.write(Data("memoshi-protocol-schema: \(error)\n".utf8))
  exit(1)
}
