import AppKit
import WebKit

/// Synthesized `NSEvent`s sent straight to one web view, as Noodle's `BrowserPointer` does: no
/// event is posted to the window server, so no other window or app receives them. Whether WebKit
/// delivers them to pages as trusted input (`event.isTrusted`) is what S3.2 measures; a view in
/// no window cannot receive them at all.
@MainActor
enum BrowserInputSynthesizer {
  private struct KeyStroke {
    let code: UInt16
    let shift: Bool
    let base: String
  }

  /// US ANSI virtual key codes, so `event.code` matches the character on that layout. Other
  /// characters are still sent with their own `characters`; the outcome reads the value back.
  private static let keyRows: [(base: Character, shifted: Character?, code: UInt16)] = [
    ("a", "A", 0), ("s", "S", 1), ("d", "D", 2), ("f", "F", 3), ("h", "H", 4), ("g", "G", 5),
    ("z", "Z", 6), ("x", "X", 7), ("c", "C", 8), ("v", "V", 9), ("b", "B", 11), ("q", "Q", 12),
    ("w", "W", 13), ("e", "E", 14), ("r", "R", 15), ("y", "Y", 16), ("t", "T", 17),
    ("1", "!", 18), ("2", "@", 19), ("3", "#", 20), ("4", "$", 21), ("6", "^", 22),
    ("5", "%", 23), ("=", "+", 24), ("9", "(", 25), ("7", "&", 26), ("-", "_", 27),
    ("8", "*", 28), ("0", ")", 29), ("]", "}", 30), ("o", "O", 31), ("u", "U", 32),
    ("[", "{", 33), ("i", "I", 34), ("p", "P", 35), ("l", "L", 37), ("j", "J", 38),
    ("'", "\"", 39), ("k", "K", 40), (";", ":", 41), ("\\", "|", 42), (",", "<", 43),
    ("/", "?", 44), ("n", "N", 45), ("m", "M", 46), (".", ">", 47), ("`", "~", 50),
    (" ", nil, 49),
  ]

  private static let strokes: [Character: KeyStroke] = {
    var table: [Character: KeyStroke] = [:]
    for row in keyRows {
      table[row.base] = KeyStroke(code: row.code, shift: false, base: String(row.base))
      if let shifted = row.shifted {
        table[shifted] = KeyStroke(code: row.code, shift: true, base: String(row.base))
      }
    }
    return table
  }()

  /// Backspace (`kVK_Delete`).
  private static let deleteStroke = KeyStroke(code: 51, shift: false, base: "\u{7F}")

  /// Clicks the centre point the isolated world reported, in CSS pixels from the viewport's
  /// top-left corner.
  static func click(at point: CGPoint, viewport: CGSize, in webView: WKWebView) throws {
    guard let window = webView.window else { throw BrowserActionError.nativeInputNeedsWindow }
    let location = try windowLocation(of: point, viewport: viewport, in: webView)
    let time = ProcessInfo.processInfo.systemUptime
    guard
      let down = NSEvent.mouseEvent(
        with: .leftMouseDown, location: location, modifierFlags: [], timestamp: time,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 1),
      let up = NSEvent.mouseEvent(
        with: .leftMouseUp, location: location, modifierFlags: [], timestamp: time + 0.05,
        windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
        pressure: 0)
    else { throw BrowserActionError.eventSynthesisFailed }
    webView.mouseDown(with: down)
    webView.mouseUp(with: up)
  }

  /// Selects the focused field's contents through WebKit's editing command, then presses
  /// Backspace.
  static func selectAllAndDelete(in webView: WKWebView) throws {
    guard let window = webView.window else { throw BrowserActionError.nativeInputNeedsWindow }
    webView.selectAll(nil)
    try press(deleteStroke, characters: deleteStroke.base, in: webView, window: window)
  }

  /// Sends one key down and up per character to the web view's focused element.
  static func type(_ text: String, in webView: WKWebView) throws {
    guard let window = webView.window else { throw BrowserActionError.nativeInputNeedsWindow }
    for character in text {
      let characters = String(character)
      let stroke = strokes[character] ?? KeyStroke(code: 0, shift: false, base: characters)
      try press(stroke, characters: characters, in: webView, window: window)
    }
  }

  private static func press(
    _ stroke: KeyStroke, characters: String, in webView: WKWebView, window: NSWindow
  ) throws {
    let time = ProcessInfo.processInfo.systemUptime
    let flags: NSEvent.ModifierFlags = stroke.shift ? .shift : []
    guard
      let down = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags, timestamp: time,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: stroke.base, isARepeat: false, keyCode: stroke.code),
      let up = NSEvent.keyEvent(
        with: .keyUp, location: .zero, modifierFlags: flags, timestamp: time + 0.01,
        windowNumber: window.windowNumber, context: nil, characters: characters,
        charactersIgnoringModifiers: stroke.base, isARepeat: false, keyCode: stroke.code)
    else { throw BrowserActionError.eventSynthesisFailed }
    webView.keyDown(with: down)
    webView.keyUp(with: up)
  }

  /// Maps a CSS-pixel viewport point to window coordinates using the view's actual scale.
  private static func windowLocation(of point: CGPoint, viewport: CGSize, in webView: WKWebView)
    throws -> NSPoint
  {
    let bounds = webView.bounds
    guard viewport.width > 0, viewport.height > 0, bounds.width > 0 else {
      throw BrowserActionError.unsupportedScale
    }
    let scale = bounds.width / viewport.width
    guard scale > 0.25, scale < 4 else { throw BrowserActionError.unsupportedScale }
    let x = point.x * scale
    let y = point.y * scale
    let viewPoint = NSPoint(x: x, y: webView.isFlipped ? y : bounds.height - y)
    return webView.convert(viewPoint, to: nil)
  }
}
