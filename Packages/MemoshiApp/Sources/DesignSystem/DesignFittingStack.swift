import SwiftUI

/// Action rows: children side by side when they fit the offered width, otherwise one per line
/// at the leading edge, so no title wraps. One view tree for both arrangements; `ViewThatFits`
/// builds a copy of the children per arrangement, which the iOS accessibility audit reports as
/// Dynamic Type "partially unsupported" on each of its buttons.
public struct DesignFittingStack: Layout {
  private let spacing: CGFloat

  /// `spacing` separates the children in either arrangement.
  public init(spacing: CGFloat) {
    self.spacing = spacing
  }

  /// Whether children of these ideal widths fit one row in `available` points; an unspecified
  /// width always fits.
  static func fitsInRow(widths: [CGFloat], spacing: CGFloat, available: CGFloat?) -> Bool {
    guard let available else { return true }
    let row = widths.reduce(0, +) + spacing * CGFloat(max(widths.count - 1, 0))
    return row <= available
  }

  /// The children's ideal sizes, measured once per change of children.
  public struct Cache {
    var ideal: [CGSize]
  }

  /// Measures each child once at its ideal size.
  public func makeCache(subviews: Subviews) -> Cache {
    Cache(ideal: subviews.map { $0.sizeThatFits(.unspecified) })
  }

  /// Measures again when the children change.
  public func updateCache(_ cache: inout Cache, subviews: Subviews) {
    cache = makeCache(subviews: subviews)
  }

  /// A row as tall as its tallest child, or a column as wide as its widest.
  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache)
    -> CGSize
  {
    let gaps = spacing * CGFloat(max(subviews.count - 1, 0))
    let widths = cache.ideal.map(\.width)
    if Self.fitsInRow(widths: widths, spacing: spacing, available: proposal.width) {
      return CGSize(
        width: widths.reduce(0, +) + gaps,
        height: cache.ideal.map(\.height).max() ?? 0)
    }
    let sizes = columnSizes(proposal: proposal, subviews: subviews)
    return CGSize(
      width: sizes.map(\.width).max() ?? 0, height: sizes.map(\.height).reduce(0, +) + gaps)
  }

  /// Places a row centred vertically, or a column at the leading edge.
  public func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
  ) {
    let widths = cache.ideal.map(\.width)
    if Self.fitsInRow(widths: widths, spacing: spacing, available: bounds.width) {
      var x = bounds.minX
      for (subview, size) in zip(subviews, cache.ideal) {
        subview.place(
          at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      return
    }
    var y = bounds.minY
    let column = ProposedViewSize(width: bounds.width, height: nil)
    for subview in subviews {
      let size = subview.sizeThatFits(column)
      subview.place(
        at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
      y += size.height + spacing
    }
  }

  private func columnSizes(proposal: ProposedViewSize, subviews: Subviews) -> [CGSize] {
    let column = ProposedViewSize(width: proposal.width, height: nil)
    return subviews.map { $0.sizeThatFits(column) }
  }
}
