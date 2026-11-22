import DesignSystem
import SwiftUI

/// The S3 browser lab: persistent profiles, explicit review permissions, task recipes and typed
/// evidence. Normal bot tools remain disconnected; this is not a Phase 1 browser cutover.
struct BrowserReviewView: View {
  @Environment(BrowserReviewLab.self) private var lab: BrowserReviewLab?

  var body: some View {
    if let lab {
      BrowserReviewContent(lab: lab)
    } else {
      ContentUnavailableView(
        "Browser Review Unavailable", systemImage: "exclamationmark.triangle",
        description: Text("This window needs the app's browser review owner."))
    }
  }
}

private struct BrowserReviewContent: View {
  let lab: BrowserReviewLab
  @State private var selectedElementID: String?

  var body: some View {
    HSplitView {
      BrowserProfileList(lab: lab)
        .frame(
          minWidth: DS.Layout.Sidebar.min, idealWidth: DS.Layout.Sidebar.default,
          maxWidth: DS.Layout.Sidebar.max)
      BrowserMainColumn(lab: lab)
        .frame(minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity)
      BrowserInspector(lab: lab, selectedElementID: $selectedElementID)
        .frame(
          minWidth: DS.Layout.Inspector.min, idealWidth: DS.Layout.Inspector.default,
          maxWidth: DS.Layout.Inspector.max)
    }
    .frame(minWidth: DS.Layout.Window.minWidth, minHeight: DS.Layout.Window.minHeight)
    .background(DS.Colors.Surface.window)
    .onAppear { lab.reviewViewAppeared() }
    .onDisappear { lab.reviewViewDisappeared() }
    .onChange(of: lab.selectedProfileID) { selectedElementID = nil }
    .onChange(of: lab.selectedLane?.snapshot?.id) { selectedElementID = nil }
  }
}

private struct BrowserProfileList: View {
  @Bindable var lab: BrowserReviewLab
  @State private var removal: BrowserReviewProfile?

  var body: some View {
    VStack(spacing: DS.Space.s0) {
      List(selection: $lab.selectedProfileID) {
        Section("Review Profiles") {
          ForEach(lab.profiles) { profile in
            BrowserProfileRow(
              profile: profile, session: lab.sessions[profile.id],
              isRemoving: lab.pendingRemovals.contains(profile.id)
            )
            .tag(profile.id)
            .contextMenu { menu(for: profile) }
          }
        }
      }
      .listStyle(.sidebar)
      .accessibilityIdentifier("browserReview.profiles")
      Divider()
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        Button("New Review Profile", systemImage: "plus") { lab.createProfile() }
          .disabled(!lab.canEditProfiles)
          .help(
            "Creates an isolated WebKit store for review. It never uses Safari's data or another profile's sign-ins."
          )
          .accessibilityIdentifier("browserReview.newProfile")
        if let problem = lab.registryProblem {
          Text(verbatim: problem)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
        Text(
          "Only profiles created here are opened or removed. Other WebKit stores are left untouched."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
        .accessibilityIdentifier("browserReview.otherStores")
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DS.Space.s5)
    }
    .confirmationDialog(
      "Remove Review Profile?", item: $removal, titleVisibility: .visible
    ) { profile in
      Button("Remove", role: .destructive) { lab.remove(profile) }
      Button("Cancel", role: .cancel) {}
    } message: { profile in
      Text(
        "This deletes \(profile.name)'s WebKit store: its cookies, storage and caches. No other store is touched."
      )
    }
  }

  @ViewBuilder
  private func menu(for profile: BrowserReviewProfile) -> some View {
    if let session = lab.sessions[profile.id] {
      Button("Close Browser") { lab.close(session) }
    } else {
      Button("Open Browser") { lab.open(profile) }
        .disabled(lab.pendingRemovals.contains(profile.id))
    }
    Divider()
    Button("Remove Profile…", role: .destructive) { removal = profile }
      .disabled(!lab.canEditProfiles || lab.pendingRemovals.contains(profile.id))
  }

}

private struct BrowserProfileRow: View {
  let profile: BrowserReviewProfile
  let session: BrowserSession?
  let isRemoving: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      Text(verbatim: profile.name)
        .font(.body.weight(.medium))
      Text(verbatim: profile.shortID)
        .font(DS.Typography.callout.monospaced())
        .foregroundStyle(DS.Colors.Text.secondary)
      Text(status)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
    }
    .padding(.vertical, DS.Space.s1)
    .accessibilityElement(children: .combine)
  }

  private var status: String {
    if isRemoving { return String(localized: "Removing…") }
    if let session { return String(localized: "Open · \(session.placement.title)") }
    return profile.probe == nil
      ? String(localized: "Closed") : String(localized: "Closed · isolation probe set")
  }
}

private struct BrowserMainColumn: View {
  let lab: BrowserReviewLab

  var body: some View {
    VStack(spacing: DS.Space.s0) {
      BrowserBoundaryStrip()
      Divider()
      if let profile = lab.selectedProfile {
        if let session = lab.sessions[profile.id] {
          BrowserSessionPane(lab: lab, session: session)
            .id(profile.id)
        } else {
          ContentUnavailableView {
            Label(profile.name, systemImage: "safari")
          } description: {
            Text(
              "Closed. Opening creates this profile's web view with its own persistent WebKit store. Nothing loads until you navigate."
            )
          } actions: {
            Button("Open Browser") { lab.open(profile) }
              .designDefaultAction()
              .disabled(lab.pendingRemovals.contains(profile.id))
              .accessibilityIdentifier("browserReview.open")
          }
        }
      } else {
        ContentUnavailableView {
          Label("No Review Profile", systemImage: "person.crop.rectangle.stack")
        } description: {
          Text(
            "Create an isolated review profile to start. It never uses Safari's data or another profile's sign-ins."
          )
        } actions: {
          Button("New Review Profile") { lab.createProfile() }
            .disabled(!lab.canEditProfiles)
        }
      }
    }
  }
}

private struct BrowserBoundaryStrip: View {
  var body: some View {
    HStack(spacing: DS.Space.s4) {
      Label("Review Lab", systemImage: "testtube.2")
      Text(
        "Offline by default. Authorize exact test sites in Proof before loading network pages; public sites use the authenticated gateway, loopback fixtures use explicit direct mode. No sends, purchases or automatic account use."
      )
      .foregroundStyle(DS.Colors.Text.secondary)
      // The security policy wraps; it is never truncated (A20).
      .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: DS.Space.s0)
    }
    .font(DS.Typography.callout)
    .padding(.horizontal, DS.Space.s6)
    .padding(.vertical, DS.Space.s3)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.content)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.boundary")
  }
}

private struct BrowserSessionPane: View {
  let lab: BrowserReviewLab
  let session: BrowserSession
  @State private var address = ""
  @State private var addressProblem: String?
  @FocusState private var isAddressFocused: Bool
  @Environment(\.designAnnouncer) private var announcer

  /// The page the bot works in now: its separate profile while one is open (D136).
  private var page: BrowserSession { session.lane }

  var body: some View {
    VStack(spacing: DS.Space.s0) {
      navigationBar
      statusLine
      if session.separate != nil { separateProfileNote }
      if session.control == .user { controlBanner }
      Divider()
      liveArea
    }
    .onAppear { address = page.pageURL?.absoluteString ?? "" }
    .onChange(of: page.pageURL) { _, url in
      if !isAddressFocused { address = url?.absoluteString ?? "" }
    }
    .onChange(of: address) { addressProblem = nil }
  }

  private var navigationBar: some View {
    HStack(spacing: DS.Space.s3) {
      Button("Back", systemImage: "chevron.backward") { page.goBack() }
        .labelStyle(.iconOnly)
        .disabled(!page.canGoBack)
        .keyboardShortcut("[", modifiers: .command)
      Button("Forward", systemImage: "chevron.forward") { page.goForward() }
        .labelStyle(.iconOnly)
        .disabled(!page.canGoForward)
        .keyboardShortcut("]", modifiers: .command)
      if page.isLoading {
        Button("Stop Loading", systemImage: "xmark") { page.stopLoading() }
          .labelStyle(.iconOnly)
          .keyboardShortcut(".", modifiers: .command)
      } else {
        Button("Reload", systemImage: "arrow.clockwise") { page.reload() }
          .labelStyle(.iconOnly)
          .disabled(page.pageURL == nil)
          .keyboardShortcut("r", modifiers: .command)
      }
      TextField("Address", text: $address, prompt: Text(verbatim: "https://example.com"))
        .textFieldStyle(.roundedBorder)
        .focused($isAddressFocused)
        .onSubmit(go)
        .accessibilityIdentifier("browserReview.address")
      Button("Go", action: go)
        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      Button("Edit Address", systemImage: "character.cursor.ibeam") { isAddressFocused = true }
        .labelStyle(.iconOnly)
        .keyboardShortcut("l", modifiers: .command)
        .help("Edit the address (⌘L)")
      Button("Lab Page", systemImage: "testtube.2") { session.loadLabPage() }
        .help("Loads the offline lab page from the app. It makes no network requests.")
        .accessibilityIdentifier("browserReview.labPage")
    }
    .padding(.horizontal, DS.Space.s5)
    .padding(.vertical, DS.Space.s3)
  }

  private var statusLine: some View {
    HStack(spacing: DS.Space.s3) {
      if page.isLoading {
        ProgressView(value: page.progress)
          .controlSize(.small)
          .frame(width: DS.Space.s12)
      }
      // A blocked or failed reason wraps in full instead of truncating (A20).
      Text(statusText)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("browserReview.status")
      Spacer(minLength: DS.Space.s3)
      Text(session.placement.title)
      if lab.isPresentingLive(session) {
        Button("Park Page") { lab.parkFromReview(session) }
          .help(
            "Moves the same page out of this window into the chosen parking place. It keeps running."
          )
      } else {
        Button("Show Live") { lab.showLive(session) }
      }
      Button("Close Browser") { lab.close(session) }
        .help("Releases this page. The profile's store and its data stay on disk.")
        .accessibilityIdentifier("browserReview.close")
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .padding(.horizontal, DS.Space.s5)
    .padding(.bottom, DS.Space.s3)
  }

  private var separateProfileNote: some View {
    Label(
      "Another site opened in a separate, empty profile: no cookies or storage from this profile. It is discarded when the task ends.",
      systemImage: "person.crop.rectangle.stack"
    )
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, DS.Space.s5)
    .padding(.bottom, DS.Space.s3)
    .accessibilityIdentifier("browserReview.separateProfile")
  }

  private var controlBanner: some View {
    HStack(spacing: DS.Space.s4) {
      Label("You're in control", systemImage: "hand.raised.fill")
        .font(.callout.weight(.semibold))
      Text("Lab actions wait until you hand back. Nothing you do here is recorded.")
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      Spacer(minLength: DS.Space.s3)
      Button("Hand Back") { session.handBack() }
        .keyboardShortcut("t", modifiers: [.control, .command])
        .accessibilityIdentifier("browserReview.handBack")
    }
    .padding(.horizontal, DS.Space.s5)
    .padding(.vertical, DS.Space.s3)
    .background(DS.Colors.Accent.selection)
    .accessibilityElement(children: .contain)
  }

  @ViewBuilder
  private var liveArea: some View {
    if lab.isPresentingLive(session) {
      BrowserLiveView(lab: lab, session: session, shieldsInput: session.control == .watching)
        .overlay {
          if session.control == .user {
            Rectangle()
              .strokeBorder(DS.Colors.Accent.default, lineWidth: 2)
              .allowsHitTesting(false)
          }
        }
        .overlay(alignment: .bottomTrailing) {
          if session.control == .watching {
            Button("Take Over", systemImage: "hand.raised") { session.takeOver() }
              .keyboardShortcut("t", modifiers: [.control, .command])
              .help("Hold lab actions and use the page yourself. Hand back with ⌃⌘T.")
              .padding(DS.Space.s5)
              .accessibilityIdentifier("browserReview.takeOver")
          }
        }
        .accessibilityElement(children: .contain)
        // "<Name>'s browser, watching" / "…, you are in control" (02 §13.2, A10).
        .accessibilityLabel(liveLabel)
        .accessibilityIdentifier("browserReview.live")
        .onChange(of: session.control) { _, _ in announcer.announce(String(localized: liveLabel)) }
    } else {
      ContentUnavailableView {
        Label("Page Parked", systemImage: "rectangle.dashed")
      } description: {
        Text(
          "\(session.placement.title). The same page keeps running; showing it here moves the view without reloading."
        )
      } actions: {
        Button("Show Live") { lab.showLive(session) }
      }
    }
  }

  private var liveLabel: LocalizedStringResource {
    session.control == .user
      ? "\(session.profile.name)'s browser, you are in control"
      : "\(session.profile.name)'s browser, watching"
  }

  private var statusText: String {
    if let addressProblem { return addressProblem }
    switch page.navigation {
    case .idle:
      return page.pageURL == nil
        ? String(localized: "Nothing loaded. Enter an address or open the lab page.")
        : String(localized: "Ready")
    case .loading:
      return String(localized: "Loading…")
    case .finished(let ms):
      guard let ms else { return String(localized: "Loaded") }
      return String(localized: "Loaded in \(Int(ms.rounded())) ms")
    case .failed(let failure):
      return failure.message
    case .blocked(let reason):
      return reason.message
    case .terminated:
      return String(localized: "The page's web content process ended. Reload to recover.")
    }
  }

  private func go() {
    if let problem = session.navigate(to: address) {
      addressProblem = problem.message
    } else {
      addressProblem = nil
      isAddressFocused = false
    }
  }
}
