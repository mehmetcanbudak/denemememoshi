import SwiftUI

/// Phase 0 native state/feedback specimens only; later reveal, shimmer, ticker, card-entrance,
/// roster and Metal passes are not enabled by visiting the gallery.
struct GalleryPrimitivePage: View {
  let comparison: GalleryComparison
  @State private var state = DesignWorkState.running
  @State private var showMessage = false
  @State private var showContext = false
  @State private var resolved = false
  @State private var expanded = false
  @State private var messageText = "This local example is settled. Its text stays selectable."
  @State private var messageIsStreaming = false
  @State private var messageAppendIndex = 0

  private static let messageChunks = [
    " Each press appends one fixed sample passage.",
    " Select this text while the example is still streaming.",
    " Settling keeps the same text and restores the complete sender announcement.",
  ]

  var body: some View {
    GalleryPage(section: .motion, comparison: comparison) {
      VStack(alignment: .leading, spacing: DS.Space.s4) {
        Picker(selection: $state) {
          ForEach(DesignWorkState.allCases) { state in Text(state.label).tag(state) }
        } label: {
          Text("Work state", bundle: #bundle)
        }
        .accessibilityIdentifier("gallery.workState")
        Toggle(isOn: $showMessage) {
          Text("Show example message", bundle: #bundle)
        }
        .accessibilityIdentifier("gallery.showMessage")
        Button {
          messageText = "This is a local streaming example."
          messageAppendIndex = 0
          messageIsStreaming = true
          showMessage = true
        } label: {
          Text("Start example stream", bundle: #bundle)
        }
        .accessibilityIdentifier("gallery.message.start")
        Button {
          messageText.append(Self.messageChunks[messageAppendIndex])
          messageAppendIndex += 1
        } label: {
          Text("Append example text", bundle: #bundle)
        }
        .disabled(!messageIsStreaming || messageAppendIndex == Self.messageChunks.count)
        .accessibilityIdentifier("gallery.message.append")
        Button {
          messageIsStreaming = false
        } label: {
          Text("Settle example message", bundle: #bundle)
        }
        .disabled(!messageIsStreaming)
        .accessibilityIdentifier("gallery.message.settle")
        Toggle(isOn: $showContext) {
          Text("Show contextual panel", bundle: #bundle)
        }
        .accessibilityIdentifier("gallery.showContext")
        Toggle(isOn: $resolved) {
          Text("Resolve example card", bundle: #bundle)
        }
        .accessibilityIdentifier("gallery.resolveCard")
      }
      .font(DS.Typography.body)
    } specimen: {
      GalleryNativeSpecimens(
        state: state, showMessage: showMessage, showContext: showContext,
        messageText: messageText, messageIsStreaming: messageIsStreaming,
        resolved: resolved, expanded: $expanded)
    }
  }
}

private struct GalleryNativeSpecimens: View {
  let state: DesignWorkState
  let showMessage: Bool
  let showContext: Bool
  let messageText: String
  let messageIsStreaming: Bool
  let resolved: Bool
  @Binding var expanded: Bool
  @State private var draft = ""
  @FocusState private var fieldFocused: Bool
  @State private var hovered = false
  @Environment(\.motionPolicy) private var policy

  var body: some View {
    GalleryGroup(
      title: Text("Progress and state", bundle: #bundle),
      note: Text(
        "Native progress plus a label; static under Reduce Motion, Low Power or hidden.",
        bundle: #bundle)
    ) {
      DesignStatusChip("Example tool", state: state)
      if state == .running {
        DesignProgressLabel(LocalizedStringResource("Example bot is thinking", bundle: #bundle))
      }
    }
    GalleryGroup(
      title: Text("Focus and pointer feedback", bundle: #bundle),
      note: Text(
        "Color and fill only. Tab into the field; focus never translates a control.",
        bundle: #bundle)
    ) {
      TextField(text: $draft, prompt: Text("Example local text", bundle: #bundle)) {
        Text("Example local text", bundle: #bundle)
      }
      .textFieldStyle(.roundedBorder)
      .focused($fieldFocused)
      .padding(DS.Space.s3)
      .background(
        fieldFocused || hovered ? DS.Colors.Surface.cardHover : DS.Colors.Surface.card,
        in: RoundedRectangle(cornerRadius: DS.Radius.md)
      )
      .onHover { hovered = $0 }
      .animation(DS.Motion.Recipes.composerFocus.animation(for: policy), value: fieldFocused)
      .animation(DS.Motion.Recipes.hoverFill.animation(for: policy), value: hovered)
      .accessibilityIdentifier("gallery.focusField")
    }
    GalleryGroup(
      title: Text("Message and context", bundle: #bundle),
      note: Text(
        "Start, append and settle the local message above. Text stays selectable in both states; no model, timer or reveal renderer runs.",
        bundle: #bundle
      )
    ) {
      MotionPresence(isPresented: showMessage, recipe: DS.Motion.Recipes.messageSend) {
        DesignMessage(
          sender: "Example Assistant", text: messageText, isStreaming: messageIsStreaming
        )
        .accessibilityIdentifier("gallery.message")
      }
      MotionPresence(isPresented: showContext, recipe: DS.Motion.Recipes.panelToggle) {
        DesignCard(LocalizedStringResource("Example context", bundle: #bundle)) {
          Text("This is an example panel, not a live resource.", bundle: #bundle)
          Button {
            fieldFocused = true
          } label: {
            Text("Focus example field", bundle: #bundle)
          }
          .accessibilityIdentifier("gallery.contextFocus")
        }
      }
    }
    GalleryGroup(title: Text("Card resolution and disclosure", bundle: #bundle)) {
      DesignCard(
        resolved
          ? LocalizedStringResource("Example receipt", bundle: #bundle)
          : LocalizedStringResource("Example question", bundle: #bundle)
      ) {
        (resolved
          ? Text("The example is resolved. No action was performed.", bundle: #bundle)
          : Text("Choose a local example state above.", bundle: #bundle))
          .contentTransition(.opacity)
        if !resolved {
          DisclosureGroup(isExpanded: $expanded) {
            Text(
              "All text here is original sample content. There is no tool or approval request.",
              bundle: #bundle
            )
            .fixedSize(horizontal: false, vertical: true)
          } label: {
            Text("Inspect example details", bundle: #bundle)
          }
          .animation(DS.Motion.Recipes.disclosureToggle.animation(for: policy), value: expanded)
          .accessibilityIdentifier("gallery.nativeDisclosure")
        }
      }
      .animation(DS.Motion.Recipes.cardResolve.animation(for: policy), value: resolved)
    }
    GalleryGroup(
      title: Text("Provisional recipe bindings", bundle: #bundle),
      note: Text(
        "Existing JSON values, not final adoption or a competitor-motion score.", bundle: #bundle)
    ) {
      ForEach(DS.Motion.Recipes.phase0) { recipe in
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          Text(verbatim: recipe.id).font(DS.Typography.callout.monospaced())
          Text(
            "Normal \((recipe.duration * 1000).formatted()) ms · Reduce Motion \((recipe.reducedDuration * 1000).formatted()) ms · \(recipe.budget)",
            bundle: #bundle
          )
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}
