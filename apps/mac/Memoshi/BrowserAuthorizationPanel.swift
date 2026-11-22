import AppCore
import AppKit
import Darwin
import DesignSystem
import SwiftUI
import UniformTypeIdentifiers

/// Review-only controls. No value supplied by a page can operate or approve these controls. The
/// sites being chosen live in the lab, so switching inspector tabs keeps them.
struct BrowserAuthorizationPanel: View {
  @Bindable var lab: BrowserReviewLab
  @State private var importing = false
  @State private var importProblem: String?

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text("Authorized Browser Tasks").font(.headline)
      Text(
        "Offline by default. Public sites use an authenticated host-only proxy, not HTTPS method interception. Direct fixture mode admits explicitly selected loopback origins or the built-in offline lab, never real-site/gateway evidence. A grant does not approve sends or purchases; page JavaScript can send data to approved hosts."
      )
      .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      if let session = lab.selectedSession {
        configuration(session)
        Divider()
        suite(session)
      } else {
        Text("Open a review profile before authorizing any page or task.").font(
          DS.Typography.callout)
      }
      if lab.evidence.storageProblem {
        Label(
          "The durable evidence file is unavailable. Task execution is disabled; existing evidence is left unchanged.",
          systemImage: "exclamationmark.triangle"
        )
        .font(DS.Typography.callout)
      }
    }
    .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
      do {
        let url = try result.get()
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
        defer { _ = Darwin.close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_mode & S_IFMT == S_IFREG,
          status.st_size <= 1_000_000
        else { throw CocoaError(.fileReadTooLarge) }
        let bytes =
          try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false).read(
            upToCount: 1_000_001) ?? Data()
        lab.taskRunner.select(data: bytes)
        lab.siteGrantDraft.approved = false
        importProblem = nil
      } catch {
        importProblem = "The selected recipe could not be read as a bounded regular JSON file."
      }
    }
    .accessibilityIdentifier("browserReview.authorization")
  }

  private func configuration(_ session: BrowserSession) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      TextField(
        "Exact site origin", text: $lab.siteGrantDraft.origin, prompt: Text("https://example.com")
      )
      .textFieldStyle(.roundedBorder)
      .accessibilityIdentifier("browserReview.siteOrigin")
      Toggle("Interact: non-consequential POSTs and buttons", isOn: $lab.siteGrantDraft.interact)
      Toggle("Sign-in: a separately approved saved test account", isOn: $lab.siteGrantDraft.signIn)
      Toggle(
        "Owned synthetic/local fixture (not a real site)", isOn: $lab.siteGrantDraft.ownedFixture)
      Button("Add Exact Site") {
        do {
          try lab.siteGrantDraft.addSite()
          importProblem = nil
        } catch { importProblem = "Enter an exact HTTP(S) origin; sign-in requires HTTPS." }
      }
      ForEach(lab.siteGrantDraft.sites) { site in
        HStack {
          Text(verbatim: site.origin).font(DS.Typography.callout.monospaced())
            // Origins stay left-to-right in mirrored chrome (L4).
            .environment(\.layoutDirection, .leftToRight)
          Spacer()
          Button("Remove", systemImage: "minus.circle") {
            lab.siteGrantDraft.removeSite(origin: site.origin)
          }.labelStyle(.iconOnly).accessibilityLabel("Remove \(site.origin)")
        }
      }
      Picker("Network route", selection: $lab.siteGrantRoute) {
        Text("Authenticated public-site proxy").tag(BrowserSessionReview.Route.authenticatedProxy)
        Text("Direct owned loopback / offline lab fixtures").tag(
          BrowserSessionReview.Route.directFixture)
      }
      Toggle(
        "I selected these sites and authorize the listed test effects",
        isOn: $lab.siteGrantDraft.approved
      )
      .accessibilityIdentifier("browserReview.authorizeEffects")
      Button("Authorize Listed Sites") {
        session.review.configure(sites: lab.siteGrantDraft.sites, route: lab.siteGrantRoute)
      }
      .disabled(
        !lab.siteGrantDraft.approved || lab.siteGrantDraft.sites.isEmpty
          || session.review.isConfiguring
      )
      .accessibilityIdentifier("browserReview.applySiteGrants")
      LabeledContent("Active route") { Text(session.review.route.label) }
      if session.review.isConfiguring {
        ProgressView("Starting authenticated gateway…").controlSize(.small)
      }
      if let problem = session.review.problem {
        Text(verbatim: problem).font(DS.Typography.callout).foregroundStyle(
          DS.Colors.Text.secondary)
      }
      Button("Revoke Review Permissions", role: .destructive) { session.review.revokePermissions() }
      // The page the bot works in decides: a separate profile's staged files count there (D136).
      if session.lane.review.privateData {
        Button("Confirm Next Private-data Form (30 s)") { session.review.confirmNextPrivateForm() }
          .help(
            "One explicit exposure confirmation for the next otherwise-authorized form. It does not authorize a send or purchase."
          )
      }
    }
    .font(DS.Typography.callout)
  }

  private func suite(_ session: BrowserSession) -> some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Button("Select Task Recipe…", systemImage: "doc.badge.plus") { importing = true }
        .disabled(lab.taskRunner.isRunning)
        .accessibilityIdentifier("browserReview.importSuite")
      if let candidate = lab.taskRunner.candidate {
        Text(verbatim: candidate.id).font(.callout.weight(.semibold))
        Text(
          "Tasks: \(candidate.tasks.count) · Declared real sites: \(candidate.sites.filter { !$0.ownedFixture }.count) · Owned fixtures: \(candidate.sites.filter(\.ownedFixture).count)"
        )
        .font(DS.Typography.callout)
        ForEach(candidate.sites) { site in
          Text(
            verbatim:
              "\(site.origin) · interact=\(site.interact) · signIn=\(site.signIn) · fixture=\(site.ownedFixture)"
          )
          .font(DS.Typography.callout.monospaced())
        }
        Text(
          "Review the selected JSON's exact operations before approval. The runner executes each action once, waits for assertions, and never resumes interrupted effects. A declared real site is not proof of a real-site gate run."
        )
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        Button("Approve Selected Recipe's Sites and Effects") {
          lab.taskRunner.approve(on: session)
        }
        .disabled(!lab.siteGrantDraft.approved || lab.taskRunner.isRunning)
        HStack {
          Button("Run Approved Recipe") { lab.taskRunner.start(on: session) }
            .disabled(
              lab.taskRunner.suite == nil || lab.taskRunner.isRunning
                || session.review.isConfiguring
            )
            .accessibilityIdentifier("browserReview.runSuite")
          Button("Cancel Run") { lab.taskRunner.cancel() }.disabled(!lab.taskRunner.isRunning)
        }
      }
      if lab.taskRunner.waitingForSignIn {
        Label(
          "Waiting for the native saved-login Card in Actions. No credential is auto-filled.",
          systemImage: "key"
        )
        .font(DS.Typography.callout)
      }
      if lab.taskRunner.waitingForExposure {
        Label(
          "Waiting for Confirm Next Private-data Form above. The page will be rechecked before its one authorized action.",
          systemImage: "hand.raised"
        )
        .font(DS.Typography.callout)
      }
      if let run = lab.taskRunner.run ?? lab.evidence.contents.runs.last {
        // Localized state; label-and-count form needs no plural agreement (L2, L3).
        Text(
          "\(String(localized: run.state.label)) · Tasks: \(run.successfulTasks.count)/\(run.taskCount) · Attempted steps: \(run.steps.count)"
        )
        .font(DS.Typography.callout.monospaced())
      }
      if let problem = importProblem ?? lab.taskRunner.problem {
        Text(verbatim: problem).font(DS.Typography.callout)
      }
    }
  }
}

struct BrowserUploadPanel: View {
  let session: BrowserSession
  let reference: BrowserElementRef?
  @State private var problem: String?
  @State private var approvedDisclosure = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text("Staged Files and Downloads").font(.callout.weight(.semibold))
      Toggle(
        "I authorize the selected test files to be shared with this page", isOn: $approvedDisclosure
      )
      Button("Stage Selected Files for This Input…") {
        guard let reference else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Stage Test Files"
        panel.begin { response in
          guard response == .OK else { return }
          let selected = panel.urls
          Task {
            do {
              try await session.review.stageUpload(
                ref: reference, urls: selected, userConfirmedDisclosure: approvedDisclosure)
              problem = nil
            } catch { problem = BrowserSessionReview.code(error) }
          }
        }
      }
      .disabled(reference == nil || session.control != .watching || !approvedDisclosure)
      Text(
        "Only these copied files can reach this exact page/input once, within 30 seconds. Unstaged pickers are cancelled; navigation revokes staged access."
      )
      .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      Text("Staged files: \(session.review.stagedFileCount)").font(DS.Typography.callout)
      Button("Authorize Next Download (30 s)") {
        do {
          try session.review.authorizeDownload()
          problem = nil
        } catch { problem = BrowserSessionReview.code(error) }
      }
      Text(
        "Downloads stay in this review profile's private Downloads folder, receive quarantine, and are never opened automatically. Completed files must fit the 1 GB cap."
      )
      .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      Text("Completed downloads: \(session.review.downloadCount)").font(DS.Typography.callout)
      if let problem { Text(verbatim: problem).font(DS.Typography.callout) }
    }
    .accessibilityIdentifier("browserReview.fileStaging")
  }
}

struct BrowserSavedLoginPanel: View {
  let session: BrowserSession
  @State private var username = ""
  @State private var password = ""
  @State private var ownsAccount = false

  var body: some View {
    VStack(alignment: .leading, spacing: DS.Space.s3) {
      Text("Saved Test Login (Keychain)").font(.callout.weight(.semibold))
      Text(
        "Use only an explicitly selected owned test account. The signed app's broker releases immediately before fill, for an unchanged HTTPS origin/document/form. Nothing is sent through the helper, model, transcript or report. Keychain synchronization is not qualified by this device-only lab path."
      )
      .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
      LabeledContent(
        "Exact Login Origin",
        value: session.pageURL.flatMap(BrowserAuthorization.origin(of:)) ?? "No HTTPS origin")
      SecureField("Test account username", text: $username).privacySensitive()
      SecureField("Test account password", text: $password).privacySensitive()
      Toggle("I own and authorize this test account", isOn: $ownsAccount)
      Button("Save Test Login in Keychain") {
        let user = username
        let secret = password
        username = ""
        password = ""
        Task { await session.review.saveLogin(username: user, password: secret) }
      }.disabled(
        !ownsAccount || username.isEmpty || password.isEmpty
          || session.review.savedLogin != nil || session.review.isSavingLogin)
      if session.review.savedLogin != nil {
        Text(
          "Revoke the saved test login before adding another. Changing pages never rebinds a credential."
        )
        .font(DS.Typography.callout).foregroundStyle(DS.Colors.Text.secondary)
        Button("Request Saved-login Card") { session.review.offerSavedLogin() }
          .disabled(!session.snapshotIsCurrent || session.review.isFilling)
        Button("Revoke Saved Login", role: .destructive) {
          Task { await session.review.revokeSavedLogin() }
        }
      }
      if let card = session.review.savedCard {
        Text("Sign in to \(card.binding.origin)?").font(.callout.weight(.semibold))
        HStack {
          Button("Use Saved Test Login") { session.review.fillSavedLogin() }.disabled(
            session.review.isFilling
          )
          .accessibilityIdentifier("browserReview.fillSavedLogin")
          Button("Decline") { session.review.declineSavedLogin() }.disabled(
            session.review.isFilling)
        }
      }
      if let matched = session.review.lastSavedFillMatched {
        Text(
          matched
            ? "Both values filled and both fields masked."
            : "Saved login was not filled or verified."
        )
        .font(DS.Typography.callout)
      }
    }
    .accessibilityIdentifier("browserReview.savedLogin")
    .onChange(of: session.profile.id) { clearEntry() }
    .onChange(of: session.pageURL.flatMap(BrowserAuthorization.origin(of:))) { clearEntry() }
    .onDisappear { clearEntry() }
  }

  private func clearEntry() {
    username = ""
    password = ""
    ownsAccount = false
  }
}

extension BrowserSessionReview.Route {
  /// The reader-facing route name, never the raw value.
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .offline: "Offline"
    case .directFixture: "Direct owned loopback / offline lab fixtures"
    case .authenticatedProxy: "Authenticated public-site proxy"
    }
  }
}

extension BrowserTaskRun.State {
  /// The reader-facing run state, never the raw value.
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .running: "Running"
    case .completed: "Completed"
    case .cancelled: "Cancelled"
    case .interrupted: "Interrupted"
    }
  }
}
