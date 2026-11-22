import SwiftUI

/// Mac sheet sizing that never fixes a sheet's height. macOS applies no Dynamic Type to SwiftUI
/// text styles, so its largest text size is the display's "Larger Text" scaling: a 13-inch
/// MacBook Air then offers 1024 × 665 pt, about 600 pt for a sheet under the menu and title
/// bars. A fixed 700 pt sheet cannot fit there and cannot grow for longer content.
public enum DesignSheetMetrics {
  /// The smallest sheet height. Header, one list or form row and the action row stay visible;
  /// the sheet's own scrolling list or form carries the rest.
  public static let minimumHeight: CGFloat = 420
}

extension View {
  /// Opens a Mac sheet at `idealWidth` × the window's minimum height. It shrinks to
  /// `DesignSheetMetrics.minimumHeight` on small canvases and grows with its window.
  public func designSheetFrame(idealWidth: CGFloat) -> some View {
    frame(
      minWidth: idealWidth, idealWidth: idealWidth, maxWidth: .infinity,
      minHeight: DesignSheetMetrics.minimumHeight, idealHeight: DS.Layout.Window.minHeight,
      maxHeight: .infinity)
  }
}
