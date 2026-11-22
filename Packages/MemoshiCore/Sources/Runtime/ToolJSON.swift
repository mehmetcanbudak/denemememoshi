import Foundation
import MemoshiProtocol
import PiCore

/// Converts actual enum trees without a serialize/parse round trip or lossy integer coercion.
enum ToolJSON {
  static func sdk(_ value: MemoshiProtocol.JSONValue) throws -> PiCore.JSONValue {
    switch value {
    case .null: return .null
    case .bool(let value): return .bool(value)
    case .integer(let value):
      let number = Double(value)
      guard Int64(exactly: number) == value else { throw RuntimeToolError.invalidArguments }
      return .number(number)
    case .double(let value):
      guard value.isFinite else { throw RuntimeToolError.invalidArguments }
      return .number(value)
    case .string(let value): return .string(value)
    case .array(let values): return .array(try values.map(sdk))
    case .object(let values):
      var object = PiCore.JSONObject()
      object.reserveCapacity(values.count)
      for (key, value) in values { object[key] = try sdk(value) }
      return .object(object)
    }
  }

  static func application(_ value: PiCore.JSONValue) throws -> MemoshiProtocol.JSONValue {
    switch value {
    case .null: return .null
    case .bool(let value): return .bool(value)
    case .number(let value):
      guard value.isFinite else { throw RuntimeToolError.invalidArguments }
      if let integer = Int64(exactly: value) { return .integer(integer) }
      return .double(value)
    case .string(let value): return .string(value)
    case .stringUTF16(let value):
      guard let native = value.nativeString else { throw RuntimeToolError.invalidArguments }
      return .string(native)
    case .array(let values): return .array(try values.map(application))
    case .object(let values):
      var object: [String: MemoshiProtocol.JSONValue] = [:]
      object.reserveCapacity(values.count)
      for (key, value) in values {
        guard let native = key.nativeString else { throw RuntimeToolError.invalidArguments }
        object[native] = try application(value)
      }
      return .object(object)
    }
  }
}
