import SwiftUI

/// All eight statuses and the three overlays, each live beside its Reduce Motion still form.
struct GalleryStatusPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .statuses, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryGroup(
        title: Text("Statuses", bundle: #bundle),
        note: Text(
          "Live avatar, then its Reduce Motion still form, then the status line.", bundle: #bundle)
      ) {
        ForEach(AvatarStatus.allCases) { status in
          GalleryStatusRow(bot: .scout(status))
        }
      }
      GalleryGroup(
        title: Text("Overlays", bundle: #bundle),
        note: Text(
          """
          Badge priority is in control, then offline, then status; both stop every loop. \
          Unread counts sit top-trailing from the md size.
          """,
          bundle: #bundle
        )
      ) {
        ForEach(GalleryStatusRow.overlayExamples) { bot in
          GalleryStatusRow(bot: bot)
        }
      }
    }
  }
}

private struct GalleryStatusRow: View {
  let bot: GallerySampleBot

  static let overlayExamples = [
    GallerySampleBot(
      id: "gallery.scout.inControl", name: "Scout", shape: .squircle, color: .teal,
      status: .paused, detail: nil, overlays: AvatarOverlays(takenOver: true)),
    GallerySampleBot(
      id: "gallery.scout.offline", name: "Scout", shape: .squircle, color: .teal,
      status: .working, detail: "reading pricing page", overlays: AvatarOverlays(offline: true)),
    GallerySampleBot(
      id: "gallery.scout.unread", name: "Scout", shape: .squircle, color: .teal,
      status: .hasNews, detail: "3 prices changed", overlays: AvatarOverlays(unreadCount: 4)),
    GallerySampleBot(
      id: "gallery.scout.unreadMany", name: "Scout", shape: .squircle, color: .teal,
      status: .idle, detail: "Watches competitor pricing",
      overlays: AvatarOverlays(unreadCount: 12)),
  ]

  var body: some View {
    HStack(spacing: DS.Space.s6) {
      BotAvatar(
        shape: bot.shape, color: bot.color, status: bot.status, overlays: bot.overlays,
        size: .lg, botID: bot.id)
      BotAvatar(
        shape: bot.shape, color: bot.color, status: bot.status, overlays: bot.overlays,
        size: .lg, botID: bot.id + ".still"
      )
      .galleryStillForm()
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        HStack(spacing: DS.Space.s3) {
          Text(bot.status.label)
            .font(DS.Typography.headline)
            .foregroundStyle(DS.Colors.Text.primary)
          Text(verbatim: bot.status.rawValue)
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.tertiary)
        }
        BotStatusLabel(bot.status, detail: bot.detail, overlays: bot.overlays)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(bot.accessibilityLabel)
  }
}

/// Twelve example bots in an avatar grid; a picker sets every status for budget review.
struct GalleryGridPage: View {
  let comparison: GalleryComparison
  @State private var mode = GalleryGridMode.mixed

  var body: some View {
    GalleryPage(section: .grid, comparison: comparison) {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        Picker(selection: $mode) {
          Text("Mixed examples", bundle: #bundle).tag(GalleryGridMode.mixed)
          ForEach(AvatarStatus.allCases) { status in
            Text(status.label).tag(GalleryGridMode.uniform(status))
          }
        } label: {
          Text("Statuses", bundle: #bundle)
        }
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityIdentifier("gallery.grid.statuses")
        Text(
          """
          Up to \(DS.Avatar.Concurrency.maxAnimatingPerWindow) avatars animate per window, \
          highest priority first; the rest hold their still pose and badge.
          """,
          bundle: #bundle
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .fixedSize(horizontal: false, vertical: true)
      }
    } specimen: {
      GalleryAvatarGrid(bots: mode.bots)
    }
  }
}

enum GalleryGridMode: Hashable {
  case mixed
  case uniform(AvatarStatus)

  var bots: [GallerySampleBot] {
    switch self {
    case .mixed: GallerySampleBot.roster
    case .uniform(let status): GallerySampleBot.roster.map { $0.with(status: status) }
    }
  }
}

private struct GalleryAvatarGrid: View {
  let bots: [GallerySampleBot]

  var body: some View {
    let grid = DS.Layout.AvatarGrid.self
    LazyVGrid(
      columns: Array(
        repeating: GridItem(.fixed(grid.tileSize), spacing: grid.gap), count: Int(grid.columns)),
      alignment: .leading, spacing: grid.gap
    ) {
      ForEach(bots) { bot in
        VStack(spacing: DS.Space.s2) {
          BotAvatar(
            shape: bot.shape, color: bot.color, status: bot.status, overlays: bot.overlays,
            size: .lg, botID: bot.id)
          Text(verbatim: bot.name)
            .font(DS.Typography.subheadline)
            .foregroundStyle(DS.Colors.Text.primary)
            .lineLimit(1)
        }
        .frame(width: grid.tileSize, height: grid.tileSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bot.accessibilityLabel)
      }
    }
  }
}

/// One example bot whose status, overlays, shape, color and size the reviewer changes.
struct GalleryPlaygroundPage: View {
  let comparison: GalleryComparison
  @State private var shape = AvatarShape.squircle
  @State private var color = AvatarColor.teal
  @State private var status = AvatarStatus.idle
  @State private var takenOver = false
  @State private var offline = false
  @State private var unreadCount = 0
  @State private var size = AvatarSize.xl

  var body: some View {
    let bot = GallerySampleBot(
      id: "gallery.playground", name: "Scout", shape: shape, color: color, status: status,
      detail: GallerySampleBot.scoutDetails[status],
      overlays: AvatarOverlays(takenOver: takenOver, offline: offline, unreadCount: unreadCount))
    GalleryPage(section: .playground, comparison: comparison) {
      GalleryPlaygroundControls(
        shape: $shape, color: $color, status: $status, takenOver: $takenOver,
        offline: $offline, unreadCount: $unreadCount, size: $size)
    } specimen: {
      GalleryPlaygroundPreview(bot: bot, size: size)
    }
  }
}

private struct GalleryPlaygroundControls: View {
  @Binding var shape: AvatarShape
  @Binding var color: AvatarColor
  @Binding var status: AvatarStatus
  @Binding var takenOver: Bool
  @Binding var offline: Bool
  @Binding var unreadCount: Int
  @Binding var size: AvatarSize

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      Grid(alignment: .leading, horizontalSpacing: DS.Space.s6, verticalSpacing: DS.Space.s4) {
        GridRow {
          Text("Status", bundle: #bundle)
          Picker(selection: $status) {
            ForEach(AvatarStatus.allCases) { option in
              Text(option.label).tag(option)
            }
          } label: {
            Text("Status", bundle: #bundle)
          }
          .labelsHidden()
          .fixedSize()
          .accessibilityIdentifier("gallery.playground.status")
        }
        GridRow {
          Text("Shape", bundle: #bundle)
          Picker(selection: $shape) {
            ForEach(AvatarShape.allCases, id: \.self) { option in
              Text(verbatim: option.rawValue).tag(option)
            }
          } label: {
            Text("Shape", bundle: #bundle)
          }
          .labelsHidden()
          .fixedSize()
        }
        GridRow {
          Text("Color", bundle: #bundle)
          Picker(selection: $color) {
            ForEach(AvatarColor.allCases, id: \.self) { option in
              Text(verbatim: option.rawValue).tag(option)
            }
          } label: {
            Text("Color", bundle: #bundle)
          }
          .labelsHidden()
          .fixedSize()
        }
        GridRow {
          Text("Size", bundle: #bundle)
          Picker(selection: $size) {
            ForEach(AvatarSize.allCases, id: \.self) { option in
              Text(verbatim: option.rawValue).tag(option)
            }
          } label: {
            Text("Size", bundle: #bundle)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
        GridRow {
          Text("Overlays", bundle: #bundle)
          HStack(spacing: DS.Space.s6) {
            Toggle(isOn: $takenOver) {
              Text("In control", bundle: #bundle)
            }
            Toggle(isOn: $offline) {
              Text("Computer offline", bundle: #bundle)
            }
          }
        }
        GridRow {
          Text("Unread", bundle: #bundle)
          Stepper(value: $unreadCount, in: 0...99) {
            Text(unreadCount, format: .number)
              .monospacedDigit()
          }
          .fixedSize()
        }
      }
      .font(DS.Typography.body)
      Text(
        """
        A status change plays its entry motion once: needs-you hops, has-news cheers (once a \
        minute per bot), error shakes, leaving asleep wakes and paused fades to its muted fill. \
        Reduce Motion, the xs size, hidden windows and off-screen scrolling skip them.
        """,
        bundle: #bundle
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
  }
}

private struct GalleryPlaygroundPreview: View {
  let bot: GallerySampleBot
  let size: AvatarSize
  /// Each comparison column is its own example bot, so per-bot rate limits do not hide motion.
  @State private var instance = UUID().uuidString

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s6) {
      HStack(alignment: .bottom, spacing: DS.Space.s8) {
        GalleryLabeledAvatar(title: Text("Live", bundle: #bundle)) {
          BotAvatar(
            shape: bot.shape, color: bot.color, status: bot.status, overlays: bot.overlays,
            size: size, botID: "\(bot.id).\(instance)")
        }
        GalleryLabeledAvatar(title: Text("Reduce Motion form", bundle: #bundle)) {
          BotAvatar(
            shape: bot.shape, color: bot.color, status: bot.status, overlays: bot.overlays,
            size: size, botID: "\(bot.id).\(instance).still"
          )
          .galleryStillForm()
        }
      }
      BotStatusLabel(bot.status, detail: bot.detail, overlays: bot.overlays)
      GalleryGroup(title: Text("VoiceOver", bundle: #bundle)) {
        bot.accessibilityLabel
          .font(DS.Typography.body)
          .foregroundStyle(DS.Colors.Text.primary)
      }
    }
  }
}

private struct GalleryLabeledAvatar<Avatar: View>: View {
  let title: Text
  @ViewBuilder let avatar: () -> Avatar

  var body: some View {
    VStack(spacing: DS.Space.s3) {
      avatar()
      title
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
    }
  }
}

/// Every silhouette, every palette color with its muted fill, and every size.
struct GalleryShapesPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .shapes, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryShapeSpecimens()
    }
  }
}

private struct GalleryShapeSpecimens: View {
  var body: some View {
    let grid = DS.Layout.AvatarGrid.self
    GalleryGroup(
      title: Text("Shapes", bundle: #bundle),
      note: Text(
        "Original silhouettes sharing one eye mark; shapes never mirror.", bundle: #bundle)
    ) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: grid.tileSize), spacing: grid.gap)],
        alignment: .leading, spacing: grid.gap
      ) {
        ForEach(AvatarShape.allCases, id: \.self) { shape in
          VStack(spacing: DS.Space.s2) {
            BotAvatar(shape: shape, color: .slate, size: .lg, botID: "gallery.shape.\(shape)")
            Text(verbatim: shape.rawValue)
              .font(DS.Typography.subheadline.monospaced())
              .foregroundStyle(DS.Colors.Text.secondary)
          }
          .frame(width: grid.tileSize, height: grid.tileSize)
          .accessibilityElement(children: .combine)
        }
      }
    }
    GalleryGroup(
      title: Text("Colors", bundle: #bundle),
      note: Text(
        "Fill, then the muted paused fill; the name uses the color's text variant.",
        bundle: #bundle)
    ) {
      LazyVGrid(
        columns: [GridItem(.adaptive(minimum: grid.tileSize * 2), spacing: grid.gap)],
        alignment: .leading, spacing: grid.gap
      ) {
        ForEach(AvatarColor.allCases, id: \.self) { color in
          HStack(spacing: DS.Space.s3) {
            BotAvatar(shape: .circle, color: color, size: .md, botID: "gallery.color.\(color)")
            BotAvatar(
              shape: .circle, color: color, status: .paused, size: .md,
              botID: "gallery.muted.\(color)")
            Text(verbatim: color.rawValue)
              .font(DS.Typography.callout.monospaced())
              .foregroundStyle(color.text)
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
    GalleryGroup(
      title: Text("Sizes", bundle: #bundle),
      note: Text("Badges from md; loops from sm, capped per size; xs never moves.", bundle: #bundle)
    ) {
      HStack(alignment: .bottom, spacing: DS.Space.s6) {
        ForEach(AvatarSize.allCases, id: \.self) { size in
          VStack(spacing: DS.Space.s3) {
            BotAvatar(
              shape: .squircle, color: .teal, status: .working,
              overlays: AvatarOverlays(unreadCount: 3), size: size, botID: "gallery.size.\(size)")
            Text(verbatim: "\(size.rawValue) · \(Double(size.points).formatted()) pt")
              .font(DS.Typography.callout.monospacedDigit())
              .foregroundStyle(DS.Colors.Text.secondary)
          }
          .accessibilityElement(children: .combine)
        }
      }
    }
  }
}

/// The existing design-preview identity components under the same review settings.
struct GalleryComponentsPage: View {
  let comparison: GalleryComparison

  var body: some View {
    GalleryPage(section: .components, comparison: comparison) {
      EmptyView()
    } specimen: {
      GalleryComponentSpecimens()
    }
  }
}

private struct GalleryComponentSpecimens: View {
  private static let previewSymbols = ["sparkle", "magnifyingglass", "cloud.sun"]

  var body: some View {
    GalleryGroup(
      title: Text("Floating identity", bundle: #bundle),
      note: Text(
        "Material chrome with a raised-surface fallback; examples, not connected.",
        bundle: #bundle)
    ) {
      FloatingBotIdentity(name: "Memoshi", symbol: "sparkle")
      FloatingBotIdentity(name: "Scout", symbol: "magnifyingglass")
    }
    GalleryGroup(
      title: Text("Preview symbol identities", bundle: #bundle),
      note: Text(
        "The design-preview shell's current original SF Symbol compositions.", bundle: #bundle)
    ) {
      HStack(spacing: DS.Space.s6) {
        ForEach(Self.previewSymbols, id: \.self) { symbol in
          BotAvatar(symbol: symbol)
        }
      }
    }
    GalleryGroup(
      title: Text("Status lines", bundle: #bundle),
      note: Text(
        "Glyph and text together; idle has no badge and shows its job line.", bundle: #bundle)
    ) {
      ForEach(AvatarStatus.allCases) { status in
        BotStatusLabel(status, detail: GallerySampleBot.scoutDetails[status])
      }
    }
    GalleryGroup(title: Text("Preview notice", bundle: #bundle)) {
      DesignPreviewNotice()
    }
  }
}
