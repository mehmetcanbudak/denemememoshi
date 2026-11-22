import AppCore
import AppKit
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// The review lab's inspector: snapshot refs, validated actions, proof instruments and the log.
struct BrowserInspector: View {
  let lab: BrowserReviewLab
  @Binding var selectedElementID: String?
  @State private var tab = Tab.snapshot

  private enum Tab: String, CaseIterable, Identifiable {
    case snapshot, actions, proof, log

    var id: Self { self }

    var title: LocalizedStringKey {
      switch self {
      case .snapshot: "Snapshot"
      case .actions: "Actions"
      case .proof: "Proof"
      case .log: "Log"
      }
    }
  }

  var body: some View {
    VStack(spacing: DS.Space.s0) {
      Picker("Inspector", selection: $tab) {
        ForEach(Tab.allCases) { tab in
          Text(tab.title).tag(tab)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .padding(DS.Space.s5)
      .accessibilityIdentifier("browserReview.inspectorTabs")
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: DS.Space.s5) {
          switch tab {
          case .snapshot:
            // The page the bot works in now, a separate profile included (D136).
            if let session = lab.selectedLane {
              BrowserSnapshotPanel(session: session, selectedElementID: $selectedElementID)
            } else {
              noSession
            }
          case .actions:
            if let session = lab.selectedLane {
              BrowserActionsPanel(session: session, selectedElementID: selectedElementID)
            } else {
              noSession
            }
          case .proof:
            BrowserProofPanel(lab: lab)
          case .log:
            BrowserLogPanel(lab: lab)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DS.Space.s5)
      }
    }
    .background(DS.Colors.Surface.inspector)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("browserReview.inspector")
  }

  private var noSession: some View {
    Text("Open the selected profile's browser to take snapshots and run actions.")
      .font(.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
  }
}

// MARK: - Snapshot

private struct BrowserSnapshotPanel: View {
  let session: BrowserSession
  @Binding var selectedElementID: String?
  @State private var mode = BrowserSnapshotMode.interactive

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s4) {
      HStack(spacing: DS.Space.s3) {
        Picker("Snapshot Mode", selection: $mode) {
          Text("Interactive").tag(BrowserSnapshotMode.interactive)
          Text("Full").tag(BrowserSnapshotMode.full)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        Spacer(minLength: DS.Space.s3)
        Button("Take Snapshot", systemImage: "camera.viewfinder") {
          session.startSnapshot(mode: mode)
        }
        .disabled(session.isSnapshotting || session.isClosed || session.pageURL == nil)
        .accessibilityIdentifier("browserReview.takeSnapshot")
      }
      if let problem = session.snapshotProblem {
        Label(problem.message, systemImage: "exclamationmark.triangle")
          .font(DS.Typography.callout)
      }
      if let snapshot = session.snapshot {
        summary(of: snapshot)
        LazyVStack(alignment: .leading, spacing: DS.Space.s1) {
          ForEach(snapshot.elements) { element in
            BrowserElementRow(
              element: element, isSelected: selectedElementID == element.id
            ) {
              selectedElementID = element.id
            }
          }
        }
      } else {
        Text(
          "Snapshots list visible elements with refs for actions. Page text appears only here; it is never logged or exported."
        )
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
  }

  private func summary(of snapshot: BrowserPageSnapshot) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      if !snapshot.title.isEmpty {
        Text(verbatim: snapshot.title)
          .font(.callout.weight(.semibold))
          .lineLimit(2)
      }
      Text(
        "\(snapshot.elements.count) elements in \(snapshot.frames.count) frames · \(Int(snapshot.durationMs.rounded())) ms"
      )
      if snapshot.truncated {
        Text("Some frames had more elements than the snapshot limit.")
      }
      if snapshot.skippedFrames > 0 {
        Text("Frames that did not answer: \(snapshot.skippedFrames)")
      }
      if !session.snapshotIsCurrent {
        Label(
          "The page changed. Take a new snapshot before acting.",
          systemImage: "clock.arrow.circlepath")
      }
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.snapshotSummary")
  }
}

private struct BrowserElementRow: View {
  let element: BrowserElement
  let isSelected: Bool
  let select: () -> Void

  var body: some View {
    Button(action: select) {
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        HStack(spacing: DS.Space.s3) {
          Text(verbatim: element.displayRef)
            .font(DS.Typography.callout.monospaced())
            .foregroundStyle(DS.Colors.Text.secondary)
          Text(verbatim: element.role)
            .font(DS.Typography.callout.weight(.semibold))
          if !element.states.isEmpty {
            Text(verbatim: element.states.joined(separator: ", "))
              .font(DS.Typography.callout)
              .foregroundStyle(DS.Colors.Text.tertiary)
          }
        }
        if !element.name.isEmpty {
          Text(verbatim: element.name)
            .font(.callout)
            .lineLimit(2)
        }
        if element.masked {
          Label("Value hidden", systemImage: "eye.slash")
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        } else if let value = element.value, !value.isEmpty {
          Text(verbatim: value)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
            .lineLimit(1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DS.Space.s3)
      .background(
        isSelected ? AnyShapeStyle(DS.Colors.Accent.selection) : AnyShapeStyle(Color.clear),
        in: RoundedRectangle(cornerRadius: DS.Radius.sm)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint("Selects this element for the Actions tab.")
  }
}

// MARK: - Actions

private struct BrowserActionsPanel: View {
  let session: BrowserSession
  let selectedElementID: String?
  @State private var path = BrowserInputPath.native
  @State private var text = ""
  @State private var replace = true
  @State private var optionIndex = 0
  @State private var direction = BrowserScrollDirection.down
  @State private var points = 600

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      Picker("Input", selection: $path) {
        ForEach(BrowserInputPath.allCases) { path in
          Text(path.title).tag(path)
        }
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("browserReview.inputPath")
      Text(pathExplanation)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      if session.control == .user {
        Label("You're in control. Hand back to run lab actions.", systemImage: "hand.raised")
          .font(DS.Typography.callout)
      }
      if let handBack = session.lastHandBack {
        BrowserHandBackSummary(summary: handBack)
      }
      if let snapshot = session.snapshot, let element {
        elementActions(element, ref: snapshot.reference(to: element))
      } else {
        Text("Select an element in the Snapshot tab.")
          .font(.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
      Divider()
      HStack(spacing: DS.Space.s3) {
        Picker("Direction", selection: $direction) {
          ForEach(BrowserScrollDirection.allCases) { direction in
            Text(direction.title).tag(direction)
          }
        }
        .fixedSize()
        Stepper(value: $points, in: 50...5_000, step: 50) {
          Text("\(points) pt")
        }
        Button("Scroll Page") { session.start(.scroll(direction, points: points)) }
          .disabled(!canAct)
      }
      if let outcome = session.lastOutcome {
        BrowserOutcomeCard(outcome: outcome)
      }
      Divider()
      BrowserSignInCardPanel(session: session)
      Divider()
      BrowserSavedLoginPanel(session: session)
      Divider()
      BrowserUploadPanel(
        session: session,
        reference: element.flatMap { element in
          session.snapshot.map { $0.reference(to: element) }
        })
    }
    .onChange(of: selectedElementID) { optionIndex = 0 }
  }

  private var element: BrowserElement? {
    session.snapshot?.elements.first { $0.id == selectedElementID }
  }

  private var canAct: Bool {
    !session.isClosed && !session.isPerforming && session.control == .watching
  }

  private var canActOnElement: Bool { canAct && session.snapshotIsCurrent }

  private var pathExplanation: String {
    switch path {
    case .native:
      String(
        localized:
          "NSEvents go straight to this web view, and the page reports whether it saw them as trusted. A detached view has no window and can't receive them."
      )
    case .script:
      String(
        localized:
          "DOM calls from the isolated world, not native input. Script clicks are untrusted; WebKit may report execCommand text events as trusted."
      )
    }
  }

  @ViewBuilder
  private func elementActions(_ element: BrowserElement, ref: BrowserElementRef) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(verbatim: "\(element.displayRef) · \(element.role)")
        .font(DS.Typography.callout.monospaced())
      if !element.name.isEmpty {
        Text(verbatim: element.name)
          .font(.callout)
          .lineLimit(2)
      }
      HStack(spacing: DS.Space.s3) {
        Button("Click") { session.start(.click(ref, path)) }
          .disabled(!canActOnElement)
          .accessibilityIdentifier("browserReview.click")
        Button("Scroll Into View") { session.start(.scrollTo(ref)) }
          .disabled(!canActOnElement)
      }
    }
    if element.editable && !element.sensitive {
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        TextField("Text to type", text: $text)
          .textFieldStyle(.roundedBorder)
          .accessibilityIdentifier("browserReview.typeText")
        Toggle("Replace existing text", isOn: $replace)
        Button("Type") {
          session.start(.type(ref, text: text, replace: replace, path))
        }
        .disabled(!canActOnElement || text.isEmpty)
        .accessibilityIdentifier("browserReview.type")
        Text("Text goes only to this page. Outcomes record its length, never the text.")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
    } else if element.sensitive {
      Label(
        "Credential field: lab actions refuse it. Only a sign-in Card fills it.",
        systemImage: "key"
      )
      .font(DS.Typography.callout)
    }
    if element.selectable, let options = element.options, !options.isEmpty {
      VStack(alignment: .leading, spacing: DS.Space.s3) {
        Picker("Option", selection: $optionIndex) {
          ForEach(Array(options.enumerated()), id: \.offset) { index, option in
            Text(verbatim: option.label).tag(index)
          }
        }
        .accessibilityIdentifier("browserReview.option")
        Button("Select") {
          session.start(
            .select(ref, optionIndex: optionIndex, optionLabel: options[optionIndex].label))
        }
        .disabled(
          !canActOnElement || !options.indices.contains(optionIndex)
            || options[optionIndex].disabled)
        Text("Lists use script input: a native click would open a system menu.")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
  }
}

/// The development sign-in Card: offers, fills or declines a canary login for the lab page's
/// login form. It shows fingerprints, booleans and counts, never a credential value.
private struct BrowserSignInCardPanel: View {
  let session: BrowserSession

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text("Sign-in Card (development review)")
        .font(.callout.weight(.semibold))
      Text(
        "Fills a canary login into the lab page from the isolated world, like a sign-in Card after Use saved login. It never uses a real credential or the Keychain, and it fills only the offline lab page."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if let card = session.signInCard {
        offered(card)
      } else {
        Button("Request Sign-in Card", systemImage: "key") { session.offerSignIn() }
          .disabled(!canRequest)
          .accessibilityIdentifier("browserReview.requestSignIn")
      }
      if let problem = session.signInProblem {
        Label(problem.message, systemImage: "exclamationmark.triangle")
          .font(DS.Typography.callout)
      }
      if let outcome = session.lastSignIn {
        BrowserSignInOutcomeView(outcome: outcome)
      }
    }
  }

  private var canRequest: Bool {
    session.isShowingLabPage && session.snapshotIsCurrent && session.control == .watching
      && !session.isClosed && !session.isPerforming
  }

  private func offered(_ card: BrowserSignInCard) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s2) {
      Text("\(session.profile.name) wants to sign in to \(card.host)")
        .font(.callout)
      Text(
        "Fields \(card.usernameRef) and \(card.passwordRef) in snapshot \(card.snapshotID). Login: \(card.source.title)."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      HStack(spacing: DS.Space.s3) {
        Button("Fill Canary Login") { session.fillSignIn() }
          .disabled(card.state != .offered || session.control != .watching)
          .accessibilityIdentifier("browserReview.fillSignIn")
        Button("Decline") { session.declineSignIn() }
          .disabled(card.state != .offered)
          .accessibilityIdentifier("browserReview.declineSignIn")
      }
    }
    .padding(DS.Space.s3)
    .background(DS.Colors.Surface.content, in: RoundedRectangle(cornerRadius: DS.Radius.sm))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("browserReview.signInCard")
  }
}

private struct BrowserSignInOutcomeView: View {
  let outcome: BrowserSignInOutcome

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      Text(headline)
        .font(DS.Typography.callout.weight(.semibold))
      if outcome.result == .filled {
        Text(
          "Page script received both values: \(Self.answer(outcome.pageReceiptMatched)). Read back equal in the isolated world: \(Self.answer(outcome.domMatched)). Fields masked afterwards: \(outcome.maskedFieldsAfterFill ?? 0) of 2. Canary in the verification snapshot: \(Self.answer(outcome.snapshotContainsCanary))."
        )
      }
      if let user = outcome.usernameFingerprint, let password = outcome.passwordFingerprint {
        Text(verbatim: "Fingerprints \(user) / \(password)")
          .font(DS.Typography.callout.monospaced())
      }
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.signInOutcome")
  }

  private var headline: String {
    let duration = outcome.durationMs.map { " in \(Int($0.rounded())) ms" } ?? ""
    switch outcome.result {
    case .filled: return String(localized: "Filled the canary login\(duration)")
    case .declined: return String(localized: "Declined; nothing was filled")
    case .refused:
      let reason = outcome.refusal ?? String(localized: "unknown")
      return String(localized: "Refused (\(reason)); nothing was filled")
    }
  }

  private static func answer(_ value: Bool?) -> String {
    switch value {
    case true?: String(localized: "yes")
    case false?: String(localized: "no")
    case nil: String(localized: "not checked")
    }
  }
}

private struct BrowserOutcomeCard: View {
  let outcome: BrowserActionOutcome

  private struct EventGroup: Identifiable {
    let type: String
    var count = 0
    var trusted = 0
    var onTarget = 0
    var id: String { type }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      HStack {
        Label(
          outcome.succeeded
            ? String(localized: "Completed") : String(localized: "Not completed"),
          systemImage: outcome.succeeded ? "checkmark.circle" : "exclamationmark.triangle"
        )
        .font(.callout.weight(.semibold))
        Spacer()
        Text("\(Int(outcome.durationMs.rounded())) ms")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
      if let error = outcome.error {
        Text(error.message)
          .font(DS.Typography.callout)
      }
      LabeledContent("Action", value: "\(outcome.kind.title) · \(outcome.path.title)")
      LabeledContent("Placement", value: outcome.placement.title)
      if let verified = outcome.verified {
        LabeledContent(
          "Read back",
          value: verified ? String(localized: "Matches") : String(localized: "Does not match"))
      }
      if let length = outcome.textLength {
        LabeledContent("Typed characters", value: "\(length)")
      }
      if outcome.navigationStarted {
        Text("The page started a navigation.")
          .font(DS.Typography.callout)
      }
      if !groups.isEmpty {
        Text("Events the page saw")
          .font(DS.Typography.callout.weight(.semibold))
        ForEach(groups) { group in
          Text(
            "\(group.type) ×\(group.count) · trusted \(group.trusted) · on target \(group.onTarget)"
          )
          .font(DS.Typography.callout.monospaced())
        }
      } else if outcome.succeeded {
        Text("The page reported no input events.")
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
      }
    }
    .font(.callout)
    .padding(DS.Layout.Card.padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.Border.hairline)
    )
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.outcome")
  }

  private var groups: [EventGroup] {
    var ordered: [EventGroup] = []
    for event in outcome.observed {
      if !ordered.contains(where: { $0.type == event.type }) {
        ordered.append(EventGroup(type: event.type))
      }
      guard let index = ordered.firstIndex(where: { $0.type == event.type }) else { continue }
      ordered[index].count += 1
      if event.trusted { ordered[index].trusted += 1 }
      if event.onTarget { ordered[index].onTarget += 1 }
    }
    return ordered
  }
}

/// The change summary after a takeover: duration, navigations and hosts. Nothing else is kept.
private struct BrowserHandBackSummary: View {
  let summary: BrowserSession.HandBackSummary

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      Text("Last takeover")
        .font(DS.Typography.callout.weight(.semibold))
      Text(
        "Lasted \(Int(summary.duration.rounded())) s · navigations during takeover: \(summary.navigations)"
      )
      Text(verbatim: "\(summary.hostBefore ?? "–") → \(summary.hostAfter ?? "–")")
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.handBackSummary")
  }
}

// MARK: - Proof

private struct BrowserPanelSection<Content: View>: View {
  let title: LocalizedStringKey
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(title)
        .font(.headline)
        .accessibilityAddTraits(.isHeader)
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(DS.Layout.Card.padding)
    .background(DS.Colors.Surface.raised, in: RoundedRectangle(cornerRadius: DS.Radius.card))
    .overlay(
      RoundedRectangle(cornerRadius: DS.Radius.card).strokeBorder(DS.Colors.Border.hairline)
    )
    .accessibilityElement(children: .contain)
  }
}

private struct BrowserProofPanel: View {
  let lab: BrowserReviewLab
  @State private var configuration = BrowserBackgroundConfiguration()
  @State private var export: BrowserReviewExport?
  @State private var isExporting = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s5) {
      BrowserAuthorizationPanel(lab: lab)
      Divider()
      placementSection
      isolationSection
      backgroundSection
      measurementsSection
      unavailableSection
      exportSection
    }
  }

  private var placementSection: some View {
    BrowserPanelSection(title: "Placement") {
      Picker(
        "When not shown",
        selection: Binding(get: { lab.parkingMode }, set: { lab.setParkingMode($0) })
      ) {
        ForEach(BrowserParkingMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .accessibilityIdentifier("browserReview.parking")
      Text(lab.parkingMode.explanation)
        .font(DS.Typography.callout)
        .foregroundStyle(DS.Colors.Text.secondary)
      Picker(
        "Scheduling for new pages",
        selection: Binding(
          get: { lab.schedulingForNewSessions }, set: { lab.setSchedulingForNewSessions($0) })
      ) {
        ForEach(BrowserSchedulingPolicy.allCases) { policy in
          Text(policy.title).tag(policy)
        }
      }
      Text(
        "WebKit's inactive scheduling policy is fixed when a browser opens, so each measurement runs under one recorded policy."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if let session = lab.selectedSession {
        LabeledContent("This page", value: session.placement.title)
        LabeledContent("Its scheduling", value: session.scheduling.title)
        LabeledContent("Registered frames", value: "\(session.registeredFrameCount)")
      }
      ForEach(Array(recentMoves)) { check in
        HStack(alignment: .firstTextBaseline) {
          Text("\(check.from.title) → \(check.to.title)")
          Spacer(minLength: DS.Space.s3)
          Text(check.result.title)
        }
        .font(DS.Typography.callout)
        .accessibilityElement(children: .combine)
      }
    }
  }

  private var recentMoves: ArraySlice<BrowserHostMoveCheck> {
    lab.hostMoves.filter { $0.profileName == lab.selectedProfile?.name }.prefix(4)
  }

  private var isolationSection: some View {
    BrowserPanelSection(title: "Isolation and Persistence") {
      Text(
        "Set a non-secret probe cookie in one profile, then check every profile. Its own profile must keep it across a normal relaunch; no other profile may see it."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if let profile = lab.selectedProfile {
        Button("Set Probe in \(profile.name)") { lab.setProbe(in: profile) }
          .disabled(!lab.canEditProfiles || lab.isCheckingIsolation || lab.isWritingProbe)
          .accessibilityIdentifier("browserReview.setProbe")
        if let probe = profile.probe {
          LabeledContent(
            "Probe set", value: probe.setAt.formatted(date: .abbreviated, time: .shortened))
          Text(
            probe.setAt < lab.launchDate
              ? String(localized: "Set before this launch: a check now tests relaunch persistence.")
              : String(
                localized:
                  "Set in this launch: quit and reopen Memoshi, then check again for persistence."
              )
          )
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        }
      }
      Button("Check All Profiles") { lab.checkIsolation() }
        .disabled(lab.isCheckingIsolation || lab.isWritingProbe || lab.profiles.isEmpty)
        .accessibilityIdentifier("browserReview.checkIsolation")
      if let check = lab.isolationChecks.first {
        ForEach(check.observations, id: \.profileID) { observation in
          HStack(alignment: .firstTextBaseline, spacing: DS.Space.s3) {
            Image(
              systemName: observation.meetsExpectation
                ? "checkmark.circle" : "exclamationmark.triangle"
            )
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.Space.s1) {
              Text(verbatim: observation.profileName)
                .font(.callout)
              Text(observation.summary)
                .font(DS.Typography.callout)
                .foregroundStyle(DS.Colors.Text.secondary)
            }
          }
          .accessibilityElement(children: .combine)
        }
      }
      Text(
        "Safari is compared by hand: Safari › Settings › Privacy › Manage Website Data must not list memoshi.invalid."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
    }
  }

  private var backgroundSection: some View {
    BrowserPanelSection(title: "Background Run") {
      Text(
        "Samples the selected page on a fixed cadence wherever it lives: timer rate, DOM snapshot, takeSnapshot and placement. For S3.5, start a run and close every window. With the page kept visible, it waits in the one-point host window (row 3's fallback); turn that off and choose Detached for the no-window gate case."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      Picker("Duration", selection: $configuration.minutes) {
        Text("1 minute").tag(1)
        Text("3 minutes").tag(3)
        Text("11 minutes").tag(11)
        Text("30 minutes").tag(30)
      }
      .accessibilityIdentifier("browserReview.runDuration")
      Picker("Sample every", selection: $configuration.sampleSeconds) {
        Text("1 second").tag(1)
        Text("5 seconds").tag(5)
      }
      .accessibilityIdentifier("browserReview.runInterval")
      Toggle("Reload the lab page about once a minute", isOn: $configuration.includesNavigation)
        .accessibilityIdentifier("browserReview.runNavigation")
      Toggle(
        "Keep the page visible to WebKit while running (one-point host window)",
        isOn: $configuration.keepsPageVisible
      )
      .accessibilityIdentifier("browserReview.runVisibleHost")
      if lab.activeRun != nil {
        Button("Stop Run") { lab.stopBackgroundRun() }
          .accessibilityIdentifier("browserReview.stopRun")
      } else {
        Button("Start Run") {
          if let session = lab.selectedSession {
            lab.startBackgroundRun(for: session, configuration: configuration)
          }
        }
        .disabled(lab.selectedSession?.pageURL == nil)
        .accessibilityIdentifier("browserReview.startRun")
      }
      if let run = lab.backgroundRuns.first {
        BrowserRunSummary(run: run)
      }
      if let session = lab.selectedSession, let image = session.lastImage {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: DS.Layout.BrowserReview.snapshotMaxHeight)
          .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
          .accessibilityLabel(Text("Latest takeSnapshot image, kept in memory only"))
        if let date = session.lastImageAt {
          Text("Latest takeSnapshot at \(date, style: .time); kept in memory only.")
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
        }
      }
    }
  }

  private var measurementsSection: some View {
    BrowserPanelSection(title: "This Launch") {
      LabeledContent("Snapshots", value: "\(manualTimings.count)")
      if let p50 = BrowserClock.percentile(manualTimings.map(\.durationMs), 0.5) {
        LabeledContent("Snapshot p50", value: "\(Int(p50.rounded())) ms")
      }
      LabeledContent("Native actions completed", value: "\(nativeOutcomes.count)")
      LabeledContent(
        "Trusted target events",
        value: String(localized: "\(trustedTargetEvents) of \(targetEvents.count)"))
      LabeledContent(
        "Moves without reload",
        value: String(localized: "\(sameDocumentMoves) of \(checkedMoves.count)"))
    }
  }

  private var unavailableSection: some View {
    BrowserPanelSection(title: "Not Available in This Lab") {
      ForEach(Self.prerequisites, id: \.self) { prerequisite in
        Label(prerequisite, systemImage: "xmark.circle")
          .font(DS.Typography.callout)
      }
    }
  }

  private var exportSection: some View {
    BrowserPanelSection(title: "Export") {
      Text(
        "Saves this launch's typed evidence as JSON: counts, timings, codes and page hosts. It holds no page text, typed text, screenshots or full URLs, and it is not an S3 verdict."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      Button("Export Results…", systemImage: "square.and.arrow.up") { prepareExport() }
        .accessibilityIdentifier("browserReview.export")
    }
    .fileExporter(
      isPresented: $isExporting, item: export, contentTypes: [.json],
      defaultFilename: lab.exportFilename
    ) { result in
      lab.exportFinished(result)
      export = nil
    } onCancellation: {
      export = nil
    }
  }

  private var manualTimings: [BrowserSnapshotTiming] {
    lab.snapshotTimings.filter { $0.source == .manual }
  }

  private var nativeOutcomes: [BrowserActionOutcome] {
    lab.outcomes.filter { $0.path == .native && $0.error == nil }
  }

  private var targetEvents: [BrowserObservedEvent] {
    nativeOutcomes.flatMap(\.nativeInputEvents).filter(\.onTarget)
  }

  private var trustedTargetEvents: Int { targetEvents.filter(\.trusted).count }

  private var checkedMoves: [BrowserHostMoveCheck] {
    lab.hostMoves.filter { $0.result != .noBaseline }
  }

  private var sameDocumentMoves: Int {
    checkedMoves.filter { $0.result == .sameDocument }.count
  }

  private static let prerequisites = [
    String(
      localized:
        "Gateway coverage (S3.6): the authenticated gateway route runs here, but its decisions show only what went through it, not that nothing bypassed it; that needs the packet capture below."
    ),
    String(
      localized:
        "Saved-login qualification (S3.4): a genuinely entitled signed app, owned test account, and external transcript/log/crash canary scan are required."
    ),
    String(
      localized:
        "The 20-task suite on 5 real sites (S3.3): explicitly selected safe sites and authorized owned test accounts are still required."
    ),
    String(localized: "Packet capture over 20 sites: an external capture setup is required."),
    String(localized: "Per-profile memory (S3.7): measure WebContent processes externally."),
    String(localized: "iPhone and iPad rows (S3.8): outside this Mac lab."),
  ]

  private func prepareExport() {
    do {
      export = try lab.makeExport()
      isExporting = true
    } catch {
      lab.exportFinished(.failure(error))
    }
  }
}

private struct BrowserRunSummary: View {
  let run: BrowserBackgroundRunRecord

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s1) {
      Text(verbatim: "\(run.profileName) · \(run.state.title) · \(run.scheduling.title)")
        .font(DS.Typography.callout.weight(.semibold))
      Text(
        "Samples \(run.samples.count), detached \(run.detachedSamples.count), visible host \(run.samples.filter { $0.placement == .onePointWindow }.count)"
      )
      ForEach(BrowserClosedWindowCase.allCases, id: \.self) { closedCase in
        let summary = run.summary(of: closedCase)
        if summary.samples > 0, let minimum = summary.minimumHz, let median = summary.medianHz {
          Text(
            "\(closedCase.title), windows closed: \(summary.samples) samples, span \(summary.longestCaseSpanSeconds, format: .number.precision(.fractionLength(0))) s, timer min \(minimum, format: .number.precision(.fractionLength(3))) Hz, median \(median, format: .number.precision(.fractionLength(3))) Hz"
          )
        }
      }
      Text(
        "takeSnapshot succeeded \(run.samples.filter { $0.imageSnapshotMs != nil }.count) of \(run.samples.count)"
      )
      if let last = run.samples.last {
        Text(
          "Last sample: \(last.placement.title), page \(last.documentVisibility ?? "unknown"), other windows \(last.otherVisibleWindows)"
        )
        if !last.failures.isEmpty {
          Text(verbatim: last.failures.joined(separator: ", "))
            .font(DS.Typography.callout.monospaced())
        }
      }
    }
    .font(DS.Typography.callout)
    .foregroundStyle(DS.Colors.Text.secondary)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("browserReview.runSummary")
  }
}

// MARK: - Log

private struct BrowserLogPanel: View {
  let lab: BrowserReviewLab

  var body: some View {
    LazyVStack(alignment: .leading, spacing: DS.Space.s3) {
      Text(
        "Typed events only: hosts, codes and counts. Page text and typed input are never logged."
      )
      .font(DS.Typography.callout)
      .foregroundStyle(DS.Colors.Text.secondary)
      if lab.events.isEmpty {
        Text("No events yet.")
          .font(.callout)
      }
      ForEach(lab.events) { event in
        VStack(alignment: .leading, spacing: DS.Space.s1) {
          HStack(spacing: DS.Space.s3) {
            Text(event.date, style: .time)
            if let name = event.profileName {
              Text(verbatim: name)
            }
          }
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
          Text(event.kind.summary)
            .font(.callout)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

// MARK: - Presentation

extension BrowserClosedWindowCase {
  var title: String {
    switch self {
    case .detached: String(localized: "Detached")
    case .visibleHost: String(localized: "Visible host window")
    case .offscreenWindow: String(localized: "Off-screen window")
    }
  }
}

extension BrowserCanarySource {
  var title: String {
    switch self {
    case .harnessFile: String(localized: "canary from the review harness file")
    case .ephemeral: String(localized: "canary generated in memory for this fill")
    }
  }
}

extension BrowserPlacement {
  var title: String {
    switch self {
    case .reviewWindow: String(localized: "Live in Browser Review")
    case .detached: String(localized: "Detached, in no window")
    case .offscreenWindow: String(localized: "Off-screen window")
    case .onePointWindow: String(localized: "One-point window")
    }
  }
}

extension BrowserParkingMode {
  var title: String {
    switch self {
    case .detached: String(localized: "Detached: no window (S3.5 gate)")
    case .offscreenWindow: String(localized: "Off-screen window (experiment)")
    case .onePointWindow: String(localized: "One-point window (row 3 fallback)")
    }
  }

  var explanation: String {
    switch self {
    case .detached:
      String(
        localized:
          "The view is in no window and the lab keeps it alive: the case S3.5 asks about. Native input needs a window, so only script input works while detached."
      )
    case .offscreenWindow:
      String(
        localized:
          "An experiment, not the S3.5 gate: a borderless window beyond every screen. Native input can be tested here."
      )
    case .onePointWindow:
      String(
        localized:
          "S3 row 3's fallback, not the S3.5 gate: a one-point window kept visible at the top-left of the main display."
      )
    }
  }
}

extension BrowserSchedulingPolicy {
  var title: String {
    switch self {
    case .suspend: String(localized: "Suspend (WebKit default)")
    case .throttle: String(localized: "Throttle")
    case .unthrottled: String(localized: "None (keep running)")
    }
  }
}

extension BrowserInputPath {
  var title: String {
    switch self {
    case .native: String(localized: "Native events")
    case .script: String(localized: "Script")
    }
  }
}

extension BrowserActionKind {
  var title: String {
    switch self {
    case .click: String(localized: "Click")
    case .type: String(localized: "Type")
    case .select: String(localized: "Select")
    case .scroll: String(localized: "Scroll")
    }
  }
}

extension BrowserScrollDirection {
  var title: String {
    switch self {
    case .up: String(localized: "Up")
    case .down: String(localized: "Down")
    case .left: String(localized: "Left")
    case .right: String(localized: "Right")
    }
  }
}

extension BrowserBlockReason {
  var message: String {
    switch self {
    case .scheme:
      String(localized: "Blocked: only http and https open here, with no hand-off to other apps.")
    case .formSubmission:
      String(localized: "Blocked a form submission without current document/site authority.")
    case .nonGETMethod: String(localized: "Blocked a navigation that was not a GET.")
    case .download:
      String(localized: "Blocked a download without a current explicit authorization.")
    case .newWindow: String(localized: "Blocked a script-opened window.")
    case .siteGrant: String(localized: "Blocked a site not authorized for this review session.")
    case .networkBoundary:
      String(localized: "Blocked a load before this session's network boundary was in place.")
    case .outsideRoute:
      String(localized: "Blocked a load outside the sites this session's route admits.")
    }
  }
}

extension BrowserHostMoveResult {
  var title: String {
    switch self {
    case .sameDocument: String(localized: "Same document, no reload")
    case .documentChanged: String(localized: "Document replaced")
    case .navigationDuringCheck: String(localized: "Navigated during the check")
    case .noBaseline: String(localized: "No baseline")
    case .checkFailed: String(localized: "Page did not answer")
    }
  }
}

extension BrowserBackgroundRunState {
  var title: String {
    switch self {
    case .running: String(localized: "running")
    case .completed: String(localized: "completed")
    case .cancelled: String(localized: "stopped")
    case .sessionClosed: String(localized: "ended when the browser closed")
    }
  }
}

extension BrowserIsolationObservation {
  var summary: String {
    guard !readFailed else {
      return String(localized: "The store did not answer in time; nothing was concluded.")
    }
    var parts: [String] = []
    if expectsOwnProbe {
      parts.append(
        foundOwnProbe
          ? String(localized: "own probe present") : String(localized: "own probe missing"))
    } else {
      parts.append(String(localized: "no probe registered"))
    }
    parts.append(
      foundForeignProbe
        ? String(localized: "another profile's probe visible")
        : String(localized: "no other profile's probe"))
    if foundUnregisteredProbe { parts.append(String(localized: "unregistered probe present")) }
    if foundOwnProbe && probeSetBeforeThisLaunch == true {
      parts.append(String(localized: "kept across relaunch"))
    }
    parts.append(String(localized: "\(dataRecordCount) data records"))
    return parts.joined(separator: " · ")
  }
}

extension BrowserLabEvent.Kind {
  var summary: String {
    switch self {
    case .profileCreated:
      return String(localized: "Review profile created")
    case .profileRemoved:
      return String(localized: "Review profile and its WebKit store removed")
    case .profileRemovalFailed(let error):
      let reason =
        error?.message
        ?? String(localized: "WebKit refused, for example while a page still used the store.")
      return String(localized: "Store removal failed; the profile was kept. \(reason)")
    case .sessionOpened(let policy):
      return String(localized: "Browser opened · scheduling \(policy.title)")
    case .sessionClosed:
      return String(localized: "Browser closed; its store stays on disk")
    case .navigationFinished(let host, let ms):
      let page = host ?? String(localized: "page")
      guard let ms else { return String(localized: "Loaded \(page)") }
      return String(localized: "Loaded \(page) in \(Int(ms.rounded())) ms")
    case .navigationFailed(let host, let failure):
      let page = host ?? String(localized: "page")
      return String(localized: "\(page): \(failure.message)")
    case .blocked(let reason, let detail):
      guard let detail else { return reason.message }
      return String(localized: "\(reason.message) (\(detail))")
    case .openedInPlace(let host):
      let page = host ?? String(localized: "page")
      return String(localized: "New-window link opened in place · \(page)")
    case .openedInSeparateProfile(let host):
      let page = host ?? String(localized: "page")
      return String(
        localized: "Another site opened in a separate, empty profile · \(page)")
    case .dialogDismissed:
      return String(localized: "Page dialog dismissed automatically")
    case .permissionDenied:
      return String(localized: "Camera or microphone request denied")
    case .filePickerCancelled:
      return String(localized: "File picker cancelled; the review lab has no uploads")
    case .authenticationDeclined:
      return String(localized: "Sign-in challenge declined; no credential is used")
    case .contentProcessTerminated:
      return String(localized: "Web content process ended")
    case .snapshotTaken(let elements, let frames, let ms):
      return String(
        localized: "Snapshot: \(elements) elements in \(frames) frames, \(Int(ms.rounded())) ms")
    case .snapshotFailed(let error):
      return String(localized: "Snapshot failed: \(error.message)")
    case .action(let kind, let path, let error):
      guard let error else {
        return String(localized: "\(kind.title) · \(path.title) · completed")
      }
      return String(localized: "\(kind.title) · \(path.title) · \(error.message)")
    case .moved(let from, let to):
      return String(localized: "Moved: \(from.title) → \(to.title)")
    case .moveChecked(let result):
      return String(localized: "Move check: \(result.title)")
    case .takeoverStarted:
      return String(localized: "Takeover started")
    case .takeoverEnded(let navigations):
      return String(localized: "Handed back; navigations during takeover: \(navigations)")
    case .probeSet:
      return String(localized: "Isolation probe set")
    case .probeFailed:
      return String(localized: "Isolation probe could not be created")
    case .isolationChecked(let met, let total):
      return String(localized: "Isolation check: \(met) of \(total) profiles met expectations")
    case .backgroundRunStarted(let placement):
      return String(localized: "Background run started · \(placement.title)")
    case .backgroundRunEnded(let state):
      return String(localized: "Background run \(state.title)")
    case .signInOffered(let host):
      let page = host ?? String(localized: "page")
      return String(localized: "Sign-in Card offered for \(page)")
    case .signInEnded(let result, let refusal):
      switch result {
      case .filled: return String(localized: "Sign-in Card filled its canary login")
      case .declined: return String(localized: "Sign-in Card declined; nothing was filled")
      case .refused:
        let reason = refusal ?? String(localized: "unknown")
        return String(localized: "Sign-in Card refused (\(reason)); nothing was filled")
      }
    case .exportWritten:
      return String(localized: "Results exported")
    case .exportFailed:
      return String(localized: "Results export failed")
    }
  }
}
