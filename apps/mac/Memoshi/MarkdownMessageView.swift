import AppKit
import Foundation
import SwiftUI

/// Splits Markdown chat messages into prose, headings, blockquotes, pipe tables, copyable code
/// blocks, and color-coded unified diff cards without breaking mid-stream (`CH-03`, `D115`).
enum MarkdownMessageParser {
  struct DiffLine: Equatable, Hashable, Sendable {
    enum Kind: Equatable, Hashable, Sendable {
      case added
      case removed
      case hunk
      case header
      case context
    }

    let kind: Kind
    let text: String
  }

  enum Block: Equatable, Sendable {
    case prose(String)
    case heading(level: Int, text: String)
    case quote(String)
    case code(language: String?, content: String)
    case diff(added: Int, removed: Int, raw: String, lines: [DiffLine])
    case table(headers: [String], rows: [[String]])
  }

  static func parse(_ source: String) -> [Block] {
    guard !source.isEmpty else { return [] }
    let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    var blocks: [Block] = []
    var proseLines: [Substring] = []
    var codeLines: [Substring] = []
    var inCodeBlock = false
    var currentLanguage: String?

    func flushProse() {
      guard !proseLines.isEmpty else { return }
      blocks.append(contentsOf: parseProseRegion(proseLines))
      proseLines.removeAll(keepingCapacity: true)
    }

    func flushCode() {
      let joined = codeLines.joined(separator: "\n")
      let langLower = currentLanguage?.lowercased()
      if langLower == "diff" || langLower == "patch" {
        blocks.append(parseDiffBlock(joined))
      } else {
        blocks.append(.code(language: currentLanguage, content: joined))
      }
      codeLines.removeAll(keepingCapacity: true)
      currentLanguage = nil
    }

    for line in lines {
      let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
      if trimmed.hasPrefix("```") {
        if inCodeBlock {
          flushCode()
          inCodeBlock = false
        } else {
          flushProse()
          let lang = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
          currentLanguage = lang.isEmpty ? nil : lang
          inCodeBlock = true
        }
      } else if inCodeBlock {
        codeLines.append(line)
      } else {
        proseLines.append(line)
      }
    }

    if inCodeBlock {
      flushCode()
    } else {
      flushProse()
    }
    return blocks
  }

  private static func parseDiffBlock(_ raw: String) -> Block {
    let rawLines = raw.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    var added = 0
    var removed = 0
    var parsed: [DiffLine] = []
    parsed.reserveCapacity(rawLines.count)

    for rawLine in rawLines {
      let text = String(rawLine)
      if text.hasPrefix("+++") || text.hasPrefix("---") || text.hasPrefix("diff --git")
        || text.hasPrefix("index ")
      {
        parsed.append(DiffLine(kind: .header, text: text))
      } else if text.hasPrefix("@@") {
        parsed.append(DiffLine(kind: .hunk, text: text))
      } else if text.hasPrefix("+") {
        added += 1
        parsed.append(DiffLine(kind: .added, text: text))
      } else if text.hasPrefix("-") {
        removed += 1
        parsed.append(DiffLine(kind: .removed, text: text))
      } else {
        parsed.append(DiffLine(kind: .context, text: text))
      }
    }
    return .diff(added: added, removed: removed, raw: raw, lines: parsed)
  }

  private static func parseProseRegion(_ lines: [Substring]) -> [Block] {
    var result: [Block] = []
    var buffer: [Substring] = []

    func flushBuffer() {
      let joined = buffer.joined(separator: "\n")
      if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        result.append(.prose(joined))
      }
      buffer.removeAll(keepingCapacity: true)
    }

    var i = 0
    while i < lines.count {
      let line = lines[i]
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Pipe table: header row + separator row (`| --- | --- |`)
      if i + 1 < lines.count,
        let headers = parseTableRow(trimmed),
        isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces), expectedColumns: headers.count)
      {
        flushBuffer()
        var rows: [[String]] = []
        i += 2
        while i < lines.count {
          let rowTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
          guard let cells = parseTableRow(rowTrimmed) else { break }
          var padded = cells
          if padded.count < headers.count {
            padded.append(contentsOf: Array(repeating: "", count: headers.count - padded.count))
          } else if padded.count > headers.count {
            padded = Array(padded.prefix(headers.count))
          }
          rows.append(padded)
          i += 1
        }
        result.append(.table(headers: headers, rows: rows))
        continue
      }

      // ATX heading (`#` through `######`)
      if let (level, text) = parseHeading(trimmed) {
        flushBuffer()
        result.append(.heading(level: level, text: text))
        i += 1
        continue
      }

      // Blockquote (`> ...`)
      if trimmed.hasPrefix(">") {
        flushBuffer()
        var quoteLines: [String] = []
        while i < lines.count {
          let qTrim = lines[i].trimmingCharacters(in: .whitespaces)
          guard qTrim.hasPrefix(">") else { break }
          var content = qTrim.dropFirst()
          if content.first == " " { content = content.dropFirst() }
          quoteLines.append(String(content))
          i += 1
        }
        let joinedQuote = quoteLines.joined(separator: "\n")
        if !joinedQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          result.append(.quote(joinedQuote))
        }
        continue
      }

      buffer.append(line)
      i += 1
    }

    flushBuffer()
    return result
  }

  private static func parseHeading(_ trimmed: String) -> (Int, String)? {
    var hashes = 0
    for ch in trimmed {
      if ch == "#" { hashes += 1 } else { break }
    }
    guard (1...6).contains(hashes) else { return nil }
    let rest = trimmed.dropFirst(hashes)
    guard rest.first == " " else { return nil }
    let text = rest.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    return (hashes, text)
  }

  private static func parseTableRow(_ trimmed: String) -> [String]? {
    guard trimmed.contains("|") else { return nil }
    var working = trimmed
    if working.hasPrefix("|") { working.removeFirst() }
    if working.hasSuffix("|") { working.removeLast() }
    let cells = working.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
    guard cells.count >= 2 else { return nil }
    return cells
  }

  private static func isTableSeparator(_ trimmed: String, expectedColumns: Int) -> Bool {
    guard let cells = parseTableRow(trimmed), cells.count == expectedColumns else { return false }
    return cells.allSatisfy { cell in
      let cleaned = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
      return cleaned.count >= 2 && cleaned.allSatisfy { $0 == "-" }
    }
  }
}

/// Renders rich Markdown prose, headings, quotes, tables, copyable code blocks, and inline diff
/// cards inside live chat bubbles and Notes preview (`CH-03`, `D115`).
struct MarkdownMessageView: View {
  let text: String
  let isUser: Bool

  var body: some View {
    let blocks = MarkdownMessageParser.parse(text)
    if blocks.isEmpty {
      Text(verbatim: text)
        .font(.system(size: 13))
        .lineSpacing(2)
        .foregroundStyle(isUser ? WarmShellColors.onUserBubble : WarmShellColors.primaryText)
        .textSelection(.enabled)
    } else {
      VStack(alignment: .leading, spacing: 10) {
        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
          switch block {
          case .prose(let content):
            proseView(content)
          case .heading(let level, let title):
            headingView(level: level, title: title)
          case .quote(let content):
            quoteView(content)
          case .code(let language, let content):
            CodeBlockCardView(language: language, code: content)
          case .diff(let added, let removed, let raw, let lines):
            DiffBlockCardView(added: added, removed: removed, raw: raw, lines: lines)
          case .table(let headers, let rows):
            MarkdownTableCardView(headers: headers, rows: rows)
          }
        }
      }
    }
  }

  private func headingView(level: Int, title: String) -> some View {
    let size: CGFloat =
      switch level {
      case 1: 17
      case 2: 15
      case 3: 14
      default: 13.5
      }
    return inlineMarkdownText(title, font: .system(size: size, weight: .semibold))
      .padding(.top, level <= 2 ? 2 : 0)
  }

  private func quoteView(_ content: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
      RoundedRectangle(cornerRadius: 2)
        .fill(isUser ? WarmShellColors.onUserBubble.opacity(0.6) : WarmShellColors.badgeText)
        .frame(width: 3)
      inlineMarkdownText(content, font: .system(size: 12.5))
        .foregroundStyle(
          isUser ? WarmShellColors.onUserBubble.opacity(0.92) : WarmShellColors.mutedText)
    }
    .padding(.vertical, 2)
  }

  @ViewBuilder
  private func proseView(_ content: String) -> some View {
    inlineMarkdownText(content, font: .system(size: 13))
  }

  @ViewBuilder
  private func inlineMarkdownText(_ content: String, font: Font) -> some View {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    if let attributed = try? AttributedString(markdown: content, options: options) {
      Text(attributed)
        .font(font)
        .lineSpacing(2.5)
        .foregroundStyle(isUser ? WarmShellColors.onUserBubble : WarmShellColors.primaryText)
        .tint(isUser ? WarmShellColors.onUserBubble : WarmShellColors.badgeText)
        .textSelection(.enabled)
    } else {
      Text(verbatim: content)
        .font(font)
        .lineSpacing(2.5)
        .foregroundStyle(isUser ? WarmShellColors.onUserBubble : WarmShellColors.primaryText)
        .textSelection(.enabled)
    }
  }
}

private struct CodeBlockCardView: View {
  let language: String?
  let code: String
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(verbatim: language?.isEmpty == false ? language! : "code")
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(code, forType: .string)
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 10.5, weight: .semibold))
            Text(copied ? "Copied" : "Copy")
              .font(.system(size: 11, weight: .medium))
          }
          .foregroundStyle(copied ? WarmShellColors.badgeText : WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
        .help("Copy code block")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(WarmShellColors.pill.opacity(0.45))

      Divider().overlay(WarmShellColors.cardBorder)

      ScrollView(.horizontal, showsIndicators: true) {
        Text(verbatim: code)
          .font(.system(size: 12, design: .monospaced))
          .foregroundStyle(WarmShellColors.primaryText)
          .textSelection(.enabled)
          .padding(12)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .background(WarmShellColors.codeBlockBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .environment(\.layoutDirection, .leftToRight)
  }
}

private struct DiffBlockCardView: View {
  let added: Int
  let removed: Int
  let raw: String
  let lines: [MarkdownMessageParser.DiffLine]
  @State private var copied = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Label("diff", systemImage: "plus.forwardslash.minus")
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(WarmShellColors.mutedText)
        if added > 0 {
          Text("+\(added)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(red: 0.14, green: 0.60, blue: 0.30))
        }
        if removed > 0 {
          Text("-\(removed)")
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color(red: 0.80, green: 0.22, blue: 0.22))
        }
        Spacer()
        Button {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(raw, forType: .string)
          copied = true
          Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
          }
        } label: {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 10.5, weight: .semibold))
            Text(copied ? "Copied" : "Copy Patch")
              .font(.system(size: 11, weight: .medium))
          }
          .foregroundStyle(copied ? WarmShellColors.badgeText : WarmShellColors.mutedText)
        }
        .buttonStyle(.plain)
        .help("Copy unified diff")
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(WarmShellColors.pill.opacity(0.45))

      Divider().overlay(WarmShellColors.cardBorder)

      ScrollView(.horizontal, showsIndicators: true) {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
            Text(verbatim: line.text.isEmpty ? " " : line.text)
              .font(.system(size: 12, design: .monospaced))
              .foregroundStyle(foreground(for: line.kind))
              .padding(.horizontal, 12)
              .padding(.vertical, 2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(background(for: line.kind))
              .textSelection(.enabled)
          }
        }
        .padding(.vertical, 6)
      }
    }
    .background(WarmShellColors.codeBlockBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .environment(\.layoutDirection, .leftToRight)
  }

  private func foreground(for kind: MarkdownMessageParser.DiffLine.Kind) -> Color {
    switch kind {
    case .added: Color(red: 0.14, green: 0.56, blue: 0.28)
    case .removed: Color(red: 0.78, green: 0.20, blue: 0.20)
    case .hunk: WarmShellColors.badgeText
    case .header: WarmShellColors.mutedText
    case .context: WarmShellColors.primaryText
    }
  }

  private func background(for kind: MarkdownMessageParser.DiffLine.Kind) -> Color {
    switch kind {
    case .added: Color.green.opacity(0.11)
    case .removed: Color.red.opacity(0.11)
    case .hunk: WarmShellColors.badgeFill.opacity(0.5)
    case .header, .context: Color.clear
    }
  }
}

private struct MarkdownTableCardView: View {
  let headers: [String]
  let rows: [[String]]

  var body: some View {
    ScrollView(.horizontal, showsIndicators: true) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(spacing: 0) {
          ForEach(Array(headers.enumerated()), id: \.offset) { idx, cell in
            Text(verbatim: cell)
              .font(.system(size: 12, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
              .padding(.horizontal, 10)
              .padding(.vertical, 7)
              .frame(minWidth: 96, alignment: .leading)
            if idx < headers.count - 1 {
              Divider().overlay(WarmShellColors.cardBorder)
            }
          }
        }
        .background(WarmShellColors.pill.opacity(0.45))

        ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
          Divider().overlay(WarmShellColors.cardBorder)
          HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { idx, cell in
              Text(verbatim: cell)
                .font(.system(size: 12))
                .foregroundStyle(WarmShellColors.primaryText)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(minWidth: 96, alignment: .leading)
              if idx < row.count - 1 {
                Divider().overlay(WarmShellColors.cardBorder)
              }
            }
          }
          .background(rowIndex.isMultiple(of: 2) ? Color.clear : WarmShellColors.pill.opacity(0.16))
        }
      }
    }
    .background(WarmShellColors.codeBlockBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}
