import AppCore
import DesignSystem
import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

struct PreviewComposer: View {
  let bot: PreviewBot
  let drafts: ComposerDrafts

  var body: some View {
    GlassEffectContainer {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        TextField(
          text: Binding(
            get: { drafts.text(for: bot) },
            set: { drafts.setText($0, for: bot) }
          ),
          prompt: Text("Message \(bot.name)", bundle: #bundle),
          axis: .vertical
        ) {
          Text("Message \(bot.name)", bundle: #bundle)
        }
        .textFieldStyle(.plain)
        .font(.body)
        .lineLimit(1...6)
        .frame(minHeight: DS.Layout.Composer.controlSize, alignment: .topLeading)
        .accessibilityLabel(Text("Local draft for \(bot.name)", bundle: #bundle))
        .accessibilityHint(Text("Saved on this device only. Nothing is sent.", bundle: #bundle))
        .accessibilityIdentifier("preview.composer.\(bot.rawValue)")

        PreviewComposerControls(bot: bot, drafts: drafts)
      }
      .padding(DS.Layout.Composer.padding)
      .designChrome(DS.Materials.composer)
    }
  }
}

private struct PreviewComposerControls: View {
  let bot: PreviewBot
  let drafts: ComposerDrafts
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  var body: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Space.s4))
      : AnyLayout(HStackLayout(spacing: DS.Space.s4))

    layout {
      PreviewDraftMenu(bot: bot, drafts: drafts)
      PreviewConnectionInfo()
      PreviewDraftActions(bot: bot, drafts: drafts)
    }
  }
}

private struct PreviewDraftMenu: View {
  let bot: PreviewBot
  let drafts: ComposerDrafts

  var body: some View {
    Menu {
      Button {
        let current = drafts.text(for: bot)
        let example =
          bot == .researcher
          ? String(localized: "Compare these design directions.", bundle: #bundle)
          : String(localized: "Help me plan tomorrow.", bundle: #bundle)
        drafts.setText(current.isEmpty ? example : current + "\n" + example, for: bot)
      } label: {
        Text("Insert example prompt", bundle: #bundle)
      }
      Button {
        #if os(macOS)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(drafts.text(for: bot), forType: .string)
        #else
          UIPasteboard.general.string = drafts.text(for: bot)
        #endif
      } label: {
        Text("Copy local draft", bundle: #bundle)
      }
      .disabled(drafts.text(for: bot).isEmpty)
    } label: {
      Image(systemName: "plus")
        .font(.body.weight(.medium))
        .frame(
          minWidth: DS.Layout.Composer.minHeight,
          minHeight: DS.Layout.Composer.minHeight
        )
        .background(DS.Colors.Surface.card, in: Circle())
    }
    #if os(macOS)
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
    #endif
    .accessibilityLabel(Text("Draft actions", bundle: #bundle))
    .accessibilityHint(
      Text(
        "Insert an example prompt or copy your local draft. No attachments are uploaded.",
        bundle: #bundle))
  }
}

private struct PreviewConnectionInfo: View {
  @State private var isPresented = false

  var body: some View {
    Button {
      isPresented.toggle()
    } label: {
      Label {
        Text("Not connected", bundle: #bundle)
      } icon: {
        Image(systemName: "circle.slash")
      }
      .font(DS.Typography.callout.weight(.medium))
      .padding(.horizontal, DS.Space.s4)
      .frame(minHeight: DS.Layout.Composer.controlSize)
      .background(DS.Colors.Surface.card, in: Capsule())
    }
    .buttonStyle(.plain)
    .foregroundStyle(DS.Colors.Text.secondary)
    .popover(isPresented: $isPresented) {
      Text(
        "This is a design preview. Your text is saved as a local draft. There is no model connection, message delivery or tool execution in this view.",
        bundle: #bundle
      )
      .font(.body)
      .padding(DS.Space.s8)
      .frame(idealWidth: DS.Layout.Sidebar.default)
      .presentationCompactAdaptation(.popover)
    }
  }
}

private struct PreviewDraftActions: View {
  let bot: PreviewBot
  let drafts: ComposerDrafts

  var body: some View {
    HStack(spacing: DS.Space.s4) {
      Spacer(minLength: DS.Space.s4)
      Button {
        drafts.setText("", for: bot)
      } label: {
        Label {
          Text("Clear draft", bundle: #bundle)
        } icon: {
          Image(systemName: "xmark.circle")
        }
        .labelStyle(.iconOnly)
        .frame(
          minWidth: DS.Layout.Composer.minHeight,
          minHeight: DS.Layout.Composer.minHeight
        )
      }
      .buttonStyle(.plain)
      .disabled(drafts.text(for: bot).isEmpty)
      .accessibilityIdentifier("preview.clearDraft")
      Image(systemName: "arrow.up")
        .font(.system(size: DS.Layout.Composer.controlSize, weight: .semibold))
        .foregroundStyle(DS.Colors.Text.disabled)
        .frame(
          width: DS.Layout.Composer.minHeight,
          height: DS.Layout.Composer.minHeight
        )
        .background(DS.Colors.Surface.card, in: Circle())
        .accessibilityLabel(Text("Sending unavailable in the design preview", bundle: #bundle))
    }
  }
}
