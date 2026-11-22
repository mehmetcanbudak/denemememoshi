import AppKit
import Contacts
import DesignSystem
import Foundation
import MemoshiProtocol
import MemoshiRuntime
import Observation
import SwiftUI

/// Built-in productivity panes hosted inside the native My Apps hub (D112, D116, AP-15..AP-20).
enum BuiltInAppTab: String, CaseIterable, Identifiable, Sendable {
  case mail = "Mail"
  case calendar = "Calendar"
  case reminders = "Reminders & Tasks"
  case contacts = "Contacts"
  case notes = "Notes"
  case files = "Files & Library"
  case connectors = "Connectors"

  var id: String { rawValue }

  var symbol: String {
    switch self {
    case .mail: "envelope"
    case .calendar: "calendar"
    case .reminders: "checklist"
    case .contacts: "person.crop.circle"
    case .notes: "note.text"
    case .files: "folder"
    case .connectors: "puzzlepiece.extension"
    }
  }
}

/// Live Apple Contacts bridge for the Contacts pane (D116, AP-18).
@MainActor
@Observable
final class LiveContactsStore {
  struct ContactItem: Identifiable, Hashable, Sendable {
    let id: String
    let fullName: String
    let organization: String?
    let emails: [String]
    let phones: [String]
  }

  private(set) var isAuthorized = false
  private(set) var isLoading = false
  private(set) var contacts: [ContactItem] = []

  init() {
    if CNContactStore.authorizationStatus(for: .contacts) == .authorized {
      isAuthorized = true
      Task { await refresh() }
    }
  }

  func requestAccess() {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    if status == .denied || status == .restricted {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Contacts")
      {
        NSWorkspace.shared.open(url)
      }
      return
    }
    Task {
      let granted = await Self.requestContactsAccess()
      isAuthorized = granted
      if granted { await refresh() }
    }
  }

  func refresh() async {
    guard isAuthorized else { return }
    isLoading = true
    defer { isLoading = false }
    contacts = await Self.fetchContacts()
  }

  private nonisolated static func requestContactsAccess() async -> Bool {
    let localStore = CNContactStore()
    return (try? await localStore.requestAccess(for: .contacts)) ?? false
  }

  private nonisolated static func fetchContacts() async -> [ContactItem] {
    let localStore = CNContactStore()
    let keys: [CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactGivenNameKey as CNKeyDescriptor,
      CNContactFamilyNameKey as CNKeyDescriptor,
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    request.sortOrder = .userDefault
    var results: [ContactItem] = []
    try? localStore.enumerateContacts(with: request) { contact, _ in
      let full = [contact.givenName, contact.familyName]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
      let org = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
      let display =
        full.isEmpty
        ? (org.isEmpty ? String(localized: "Unnamed Contact") : org)
        : full
      let emails = contact.emailAddresses.map { $0.value as String }.filter { !$0.isEmpty }
      let phones = contact.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty }
      results.append(
        ContactItem(
          id: contact.identifier,
          fullName: display,
          organization: org.isEmpty || org == display ? nil : org,
          emails: emails,
          phones: phones
        )
      )
    }
    return results
  }
}

/// Real local Markdown notes backed by files on disk in Memoshi's Notes directory (AP-19).
@MainActor
@Observable
final class NotesDocumentStore {
  struct NoteDocument: Identifiable, Hashable, Sendable {
    let id: String
    let filename: String
    let title: String
    let content: String
    let modifiedAt: Date
    let fileURL: URL
  }

  private(set) var directoryURL: URL
  private(set) var notes: [NoteDocument] = []
  private(set) var lastError: String?

  init(directoryURL: URL? = nil) {
    if let directoryURL {
      self.directoryURL = directoryURL
    } else {
      let appSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
      self.directoryURL = appSupport.appendingPathComponent("Memoshi/Notes", isDirectory: true)
    }
    reload()
  }

  func setDirectory(_ url: URL) {
    guard url.standardizedFileURL != directoryURL.standardizedFileURL else { return }
    directoryURL = url.standardizedFileURL
    reload()
  }

  func reload() {
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let urls = try fm.contentsOfDirectory(
        at: directoryURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
      let allowedExtensions: Set<String> = ["md", "markdown", "txt"]
      var loaded: [NoteDocument] = []
      for url in urls where allowedExtensions.contains(url.pathExtension.lowercased()) {
        let values = try? url.resourceValues(forKeys: [
          .contentModificationDateKey, .isRegularFileKey,
        ])
        guard values?.isRegularFile != false else { continue }
        let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let modified = values?.contentModificationDate ?? Date.distantPast
        let filename = url.lastPathComponent
        loaded.append(
          NoteDocument(
            id: filename,
            filename: filename,
            title: Self.extractTitle(from: content, fallbackFilename: filename),
            content: content,
            modifiedAt: modified,
            fileURL: url
          )
        )
      }
      notes = loaded.sorted { lhs, rhs in
        if lhs.modifiedAt != rhs.modifiedAt { return lhs.modifiedAt > rhs.modifiedAt }
        return lhs.filename.localizedCaseInsensitiveCompare(rhs.filename) == .orderedAscending
      }
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  @discardableResult
  func createNote(title: String, content: String = "") -> NoteDocument? {
    let fm = FileManager.default
    do {
      try fm.createDirectory(at: directoryURL, withIntermediateDirectories: true)
      let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
      let displayTitle = trimmedTitle.isEmpty ? String(localized: "Untitled Note") : trimmedTitle
      let baseName = Self.sanitizedFilename(from: displayTitle)
      let stem = (baseName as NSString).deletingPathExtension
      let ext = (baseName as NSString).pathExtension
      var candidate = directoryURL.appendingPathComponent(baseName)
      var suffix = 2
      while fm.fileExists(atPath: candidate.path) {
        candidate = directoryURL.appendingPathComponent("\(stem)-\(suffix).\(ext)")
        suffix += 1
      }
      let initialBody = content.isEmpty ? "# \(displayTitle)\n\n" : content
      try initialBody.write(to: candidate, atomically: true, encoding: .utf8)
      reload()
      return notes.first { $0.fileURL == candidate }
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  func saveNote(_ note: NoteDocument, content: String) {
    do {
      try content.write(to: note.fileURL, atomically: true, encoding: .utf8)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func deleteNote(_ note: NoteDocument) {
    do {
      try FileManager.default.removeItem(at: note.fileURL)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  nonisolated static func sanitizedFilename(from title: String) -> String {
    let lowered = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    var slug = ""
    var lastWasDash = false
    for scalar in lowered.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        slug.unicodeScalars.append(scalar)
        lastWasDash = false
      } else if (scalar == " " || scalar == "-" || scalar == "_") && !slug.isEmpty && !lastWasDash {
        slug.append("-")
        lastWasDash = true
      }
    }
    let trimmed = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    let finalStem = trimmed.isEmpty ? "untitled" : String(trimmed.prefix(48))
    return "\(finalStem).md"
  }

  nonisolated static func extractTitle(from content: String, fallbackFilename: String) -> String {
    for rawLine in content.split(whereSeparator: \.isNewline) {
      let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let stripped = trimmed.drop(while: { $0 == "#" || $0 == " " })
      if !stripped.isEmpty {
        return String(stripped.prefix(80))
      }
    }
    return (fallbackFilename as NSString).deletingPathExtension
  }
}

/// Mail workspace state backed by `MailHostStore` (staged drafts, provider accounts, audit log).
/// Tokens live exclusively in Keychain via `MailTokenKeychain`; Memoshi never reads Apple Mail's
/// store or sends Apple Events (D41, D116, D118).
@MainActor
@Observable
final class MailWorkspaceStore {
  private(set) var dataDirectory: URL
  private(set) var accounts: [MailAccountRecord] = []
  private(set) var drafts: [MailDraftRecord] = []
  private(set) var auditEntries: [MailOrganizeAuditEntry] = []
  private(set) var lastError: String?

  private var hostStore: MailHostStore { MailHostStore(dataDirectory: dataDirectory) }

  init(dataDirectory: URL? = nil) {
    if let dataDirectory {
      self.dataDirectory = dataDirectory.standardizedFileURL
    } else {
      let appSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
      self.dataDirectory = appSupport.appendingPathComponent("Memoshi", isDirectory: true)
    }
    reload()
  }

  func setDataDirectory(_ url: URL) {
    guard url.standardizedFileURL != dataDirectory.standardizedFileURL else { return }
    dataDirectory = url.standardizedFileURL
    reload()
  }

  func reload() {
    let store = hostStore
    accounts = store.loadAccounts()
    drafts = store.loadDrafts()
    auditEntries = store.loadOrganizeAudit(limit: 40)
    lastError = nil
  }

  @discardableResult
  func saveDraft(
    id: String? = nil, to: [String], cc: [String] = [], subject: String, body: String
  ) -> MailDraftRecord? {
    let cleanedTo = to.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let cleanedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanedTo.isEmpty, !cleanedSubject.isEmpty else { return nil }
    let existing = id.flatMap { target in drafts.first { $0.id == target } }
    let record = MailDraftRecord(
      id: existing?.id ?? UUID().uuidString,
      accountID: existing?.accountID ?? accounts.first?.id,
      to: cleanedTo,
      cc: cc.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
      subject: cleanedSubject,
      body: body,
      replyToMessageID: existing?.replyToMessageID,
      remoteDraftID: existing?.remoteDraftID,
      createdAt: existing?.createdAt ?? Date(),
      updatedAt: Date()
    )
    do {
      try hostStore.saveDraft(record)
      reload()
      return record
    } catch {
      lastError = error.localizedDescription
      return nil
    }
  }

  func deleteDraft(_ draft: MailDraftRecord) {
    do {
      try hostStore.deleteDraft(id: draft.id)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func addAccount(
    provider: MailProviderKind, email: String, displayName: String, accessToken: String
  ) {
    let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
    let cleanToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleanEmail.isEmpty, !cleanToken.isEmpty else { return }
    let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    let account = MailAccountRecord(
      provider: provider,
      emailAddress: cleanEmail,
      displayName: name.isEmpty ? cleanEmail : name
    )
    guard MailTokenKeychain.saveToken(cleanToken, for: account.id) else {
      lastError = String(localized: "Could not save mail access token to Keychain.")
      return
    }
    var updated = accounts.filter {
      $0.emailAddress.localizedCaseInsensitiveCompare(cleanEmail) != .orderedSame
    }
    updated.append(account)
    do {
      try hostStore.saveAccounts(updated)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func removeAccount(_ account: MailAccountRecord) {
    MailTokenKeychain.deleteToken(for: account.id)
    let updated = accounts.filter { $0.id != account.id }
    do {
      try hostStore.saveAccounts(updated)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func openDraftInMailClient(_ draft: MailDraftRecord) {
    var components = URLComponents()
    components.scheme = "mailto"
    components.path = draft.to.joined(separator: ",")
    var items = [
      URLQueryItem(name: "subject", value: draft.subject),
      URLQueryItem(name: "body", value: draft.body),
    ]
    if !draft.cc.isEmpty {
      items.append(URLQueryItem(name: "cc", value: draft.cc.joined(separator: ",")))
    }
    components.queryItems = items
    if let url = components.url {
      NSWorkspace.shared.open(url)
    }
  }
}

/// Connectors, search providers, and one-tap Connect Cards store (`D112`, `D120`, `CON-14`).
/// API keys and connector OAuth tokens stay strictly in Keychain via `ConnectorTokenKeychain`.
@MainActor
@Observable
final class ConnectorWorkspaceStore {
  private(set) var dataDirectory: URL
  private(set) var settings = SearchSettings()
  private(set) var connectedIDs: Set<String> = []
  private(set) var connectCards: [ConnectorConnectCard] = []
  private(set) var lastError: String?

  private var hostStore: ConnectorCatalogStore {
    ConnectorCatalogStore(dataDirectory: dataDirectory)
  }

  init(dataDirectory: URL? = nil) {
    if let dataDirectory {
      self.dataDirectory = dataDirectory.standardizedFileURL
    } else {
      let appSupport =
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? FileManager.default.homeDirectoryForCurrentUser
      self.dataDirectory = appSupport.appendingPathComponent("Memoshi", isDirectory: true)
    }
    reload()
  }

  func setDataDirectory(_ url: URL) {
    guard url.standardizedFileURL != dataDirectory.standardizedFileURL else { return }
    dataDirectory = url.standardizedFileURL
    reload()
  }

  func reload() {
    let store = hostStore
    settings = store.loadSearchSettings()
    connectCards = store.loadConnectCards()
    var active = store.loadConnectedIDs()
    for item in ConnectorCatalogStore.catalog {
      if let token = ConnectorTokenKeychain.readToken(for: item.id), !token.isEmpty {
        active.insert(item.id)
      }
    }
    connectedIDs = active
    lastError = nil
  }

  func setDefaultWebProvider(_ provider: WebSearchProviderKind) {
    var updated = settings
    updated.defaultWebProvider = provider
    do {
      try hostStore.saveSearchSettings(updated)
      settings = updated
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  func connect(_ connectorID: String, token: String, resolvingCardID: String? = nil) {
    let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return }
    guard ConnectorTokenKeychain.saveToken(cleaned, for: connectorID) else {
      lastError = String(localized: "Could not save connector credential to Keychain.")
      return
    }
    do {
      try hostStore.markConnected(connectorID, connected: true)
      if let cardID = resolvingCardID {
        try hostStore.updateConnectCard(id: cardID, status: .connected)
      }
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func disconnect(_ connectorID: String) {
    ConnectorTokenKeychain.deleteToken(for: connectorID)
    do {
      try hostStore.markConnected(connectorID, connected: false)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }

  func dismissConnectCard(_ cardID: String) {
    do {
      try hostStore.updateConnectCard(id: cardID, status: .dismissed)
      reload()
    } catch {
      lastError = error.localizedDescription
    }
  }
}

/// Native My Apps workspace hosting Mail, Calendar, Reminders & Tasks, Contacts, Notes, Files, and Connectors.
struct MyAppsWorkspaceView: View {
  let model: LiveChatModel
  let remindersStore: LiveRemindersStore
  let calendarStore: LiveCalendarStore
  let contactsStore: LiveContactsStore
  let notesStore: NotesDocumentStore
  let mailStore: MailWorkspaceStore
  let connectorStore: ConnectorWorkspaceStore
  @Binding var selectedTab: BuiltInAppTab
  var onOpenFolders: () -> Void
  var onSelectConversation: (ConversationID) -> Void

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider().overlay(WarmShellColors.divider)
      Group {
        switch selectedTab {
        case .mail:
          MailAppPane(mailStore: mailStore)
        case .calendar:
          CalendarAppPane(calendarStore: calendarStore)
        case .reminders:
          RemindersTasksAppPane(
            model: model,
            remindersStore: remindersStore,
            onSelectConversation: onSelectConversation
          )
        case .contacts:
          ContactsAppPane(contactsStore: contactsStore)
        case .notes:
          NotesAppPane(notesStore: notesStore)
        case .files:
          FilesLibraryAppPane(model: model, onOpenFolders: onOpenFolders)
        case .connectors:
          ConnectorsAppPane(connectorStore: connectorStore)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .background(WarmShellColors.canvas)
    .accessibilityIdentifier("workspace.myApps")
    .task {
      model.loadTasks()
      mailStore.reload()
      notesStore.reload()
      connectorStore.reload()
      if calendarStore.isAuthorized { await calendarStore.refresh() }
      if remindersStore.isAuthorized { await remindersStore.refresh() }
      if contactsStore.isAuthorized { await contactsStore.refresh() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text("My Apps")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Live Apple data, local Markdown notes, and granted Mac folders")
            .font(.system(size: 12.5))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        Spacer()
        Button {
          refreshCurrentTab()
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(WarmShellColors.primaryText)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(WarmShellColors.pill, in: Capsule())
        }
        .buttonStyle(.plain)
      }

      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(BuiltInAppTab.allCases) { tab in
            let isSelected = selectedTab == tab
            Button {
              selectedTab = tab
            } label: {
              HStack(spacing: 6) {
                Image(systemName: tab.symbol)
                  .font(.system(size: 12, weight: .semibold))
                Text(tab.rawValue)
                  .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
              }
              .foregroundStyle(
                isSelected ? WarmShellColors.badgeText : WarmShellColors.primaryText
              )
              .padding(.horizontal, 12)
              .padding(.vertical, 7)
              .background(
                isSelected ? WarmShellColors.badgeFill : WarmShellColors.card,
                in: Capsule()
              )
              .overlay(
                Capsule().stroke(
                  isSelected ? WarmShellColors.badgeText.opacity(0.35) : WarmShellColors.cardBorder,
                  lineWidth: 1)
              )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("myApps.tab.\(tab.rawValue)")
          }
        }
      }
    }
    .padding(.horizontal, 28)
    .padding(.top, 22)
    .padding(.bottom, 14)
  }

  private func refreshCurrentTab() {
    switch selectedTab {
    case .mail:
      mailStore.reload()
    case .calendar:
      Task { await calendarStore.refresh() }
    case .reminders:
      model.loadTasks()
      Task { await remindersStore.refresh() }
    case .contacts:
      Task { await contactsStore.refresh() }
    case .notes:
      notesStore.reload()
    case .files:
      model.folders.refresh()
    case .connectors:
      connectorStore.reload()
    }
  }
}

// MARK: - Calendar 7-Day Week Pane (AP-16)

private struct CalendarAppPane: View {
  let calendarStore: LiveCalendarStore
  @State private var newEventTitle = ""
  @State private var selectedDayOffset = 0
  @State private var selectedHour = 10
  @State private var durationMinutes = 60

  private var dayGroups: [LiveCalendarStore.CalendarDayGroup] {
    LiveCalendarStore.eventsByDay(calendarStore.events, startingFrom: Date(), days: 7)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        if !calendarStore.isAuthorized {
          connectCalendarBanner
        } else {
          quickAddEventCard
          ForEach(dayGroups) { group in
            daySection(group)
          }
        }
      }
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.vertical, 20)
    }
  }

  private var connectCalendarBanner: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Apple Calendar", systemImage: "calendar")
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(WarmShellColors.primaryText)
      Text("Connect Apple Calendar to view your 7-day schedule and create events directly from Memoshi.")
        .font(.system(size: 13))
        .foregroundStyle(WarmShellColors.mutedText)
      Button("Connect Apple Calendar") { calendarStore.requestAccess() }
        .buttonStyle(.plain)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundStyle(WarmShellColors.badgeText)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(WarmShellColors.badgeFill, in: Capsule())
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private var quickAddEventCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("QUICK ADD EVENT")
        .font(.system(size: 10.5, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(WarmShellColors.badgeText)
      HStack(spacing: 8) {
        TextField(
          "New event title…", text: $newEventTitle,
          prompt: Text("New event title…").foregroundStyle(WarmShellColors.mutedText)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .foregroundStyle(WarmShellColors.primaryText)
        .onSubmit { submitEvent() }

        Picker("Day", selection: $selectedDayOffset) {
          ForEach(0..<7, id: \.self) { offset in
            Text(dayLabel(offset: offset)).tag(offset)
          }
        }
        .labelsHidden()
        .frame(width: 112)

        Picker("Hour", selection: $selectedHour) {
          ForEach(6..<23, id: \.self) { hour in
            Text(String(format: "%02d:00", hour)).tag(hour)
          }
        }
        .labelsHidden()
        .frame(width: 78)

        Picker("Duration", selection: $durationMinutes) {
          Text("30m").tag(30)
          Text("1h").tag(60)
          Text("90m").tag(90)
        }
        .labelsHidden()
        .frame(width: 68)

        Button("Add") { submitEvent() }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background(WarmShellColors.userBubble, in: Capsule())
          .disabled(newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(WarmShellColors.canvas, in: RoundedRectangle(cornerRadius: 10))
      .overlay(
        RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1)
      )
    }
    .padding(16)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private func daySection(_ group: LiveCalendarStore.CalendarDayGroup) -> some View {
    let isToday = Calendar.current.isDateInToday(group.date)
    let isTomorrow = Calendar.current.isDateInTomorrow(group.date)
    let title: String =
      if isToday {
        String(localized: "Today")
      } else if isTomorrow {
        String(localized: "Tomorrow")
      } else {
        group.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
      }
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(title)
          .font(.system(size: 13.5, weight: .semibold))
          .foregroundStyle(isToday ? WarmShellColors.badgeText : WarmShellColors.primaryText)
        Text(group.date, format: .dateTime.month(.abbreviated).day())
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
        Text("\(group.events.count)")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(WarmShellColors.mutedText)
      }
      if group.events.isEmpty {
        Text("No scheduled events")
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText.opacity(0.8))
      } else {
        ForEach(group.events) { event in
          HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
              .fill(WarmShellColors.badgeText)
              .frame(width: 3, height: 32)
            VStack(alignment: .leading, spacing: 2) {
              Text(verbatim: event.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
              HStack(spacing: 6) {
                if event.isAllDay {
                  Text("All day")
                } else {
                  Text(event.startDate, format: .dateTime.hour().minute())
                  Text("–")
                  Text(event.endDate, format: .dateTime.hour().minute())
                }
                Text("·")
                Text(verbatim: event.calendarTitle)
                if let location = event.location {
                  Text("·")
                  Text(verbatim: location).lineLimit(1)
                }
              }
              .font(.system(size: 11.5))
              .foregroundStyle(WarmShellColors.mutedText)
            }
            Spacer()
          }
        }
      }
    }
    .padding(14)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private func dayLabel(offset: Int) -> String {
    if offset == 0 { return String(localized: "Today") }
    if offset == 1 { return String(localized: "Tomorrow") }
    let date = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    return date.formatted(.dateTime.weekday(.abbreviated).day())
  }

  private func submitEvent() {
    let trimmed = newEventTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let cal = Calendar.current
    let targetDay = cal.date(byAdding: .day, value: selectedDayOffset, to: Date()) ?? Date()
    let start =
      cal.date(bySettingHour: selectedHour, minute: 0, second: 0, of: targetDay) ?? targetDay
    calendarStore.addEvent(title: trimmed, startDate: start, durationMinutes: durationMinutes)
    newEventTitle = ""
  }
}

// MARK: - Reminders & Memoshi Tasks Merged Pane (AP-17)

private struct RemindersTasksAppPane: View {
  enum Scope: String, CaseIterable, Identifiable {
    case all = "All"
    case reminders = "Reminders"
    case tasks = "Bot Tasks"
    var id: String { rawValue }
  }

  let model: LiveChatModel
  let remindersStore: LiveRemindersStore
  var onSelectConversation: (ConversationID) -> Void

  @State private var scope: Scope = .all
  @State private var selectedList = "ALL"
  @State private var newReminderTitle = ""
  @State private var dueToday = false

  private var reminderLists: [String] {
    let unique = Set(remindersStore.items.map(\.listName))
    return ["ALL"] + unique.sorted()
  }

  private var filteredReminders: [LiveRemindersStore.Item] {
    guard selectedList != "ALL" else { return remindersStore.items }
    return remindersStore.items.filter { $0.listName == selectedList }
  }

  private var sortedTasks: [MemoshiTask] {
    model.knownTasks.values.sorted { lhs, rhs in
      let lhsActive = [.queued, .running, .waiting].contains(lhs.status)
      let rhsActive = [.queued, .running, .waiting].contains(rhs.status)
      if lhsActive != rhsActive { return lhsActive }
      return lhs.createdAt > rhs.createdAt
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 18) {
        HStack {
          Picker("Scope", selection: $scope) {
            ForEach(Scope.allCases) { item in
              Text(item.rawValue).tag(item)
            }
          }
          .pickerStyle(.segmented)
          .frame(maxWidth: 280)
          Spacer()
          if scope != .tasks && reminderLists.count > 2 {
            Picker("List", selection: $selectedList) {
              ForEach(reminderLists, id: \.self) { list in
                Text(list == "ALL" ? "All Lists" : list.capitalized).tag(list)
              }
            }
            .frame(maxWidth: 180)
          }
        }

        if scope == .all || scope == .reminders {
          remindersSection
        }

        if scope == .all || scope == .tasks {
          tasksSection
        }
      }
      .frame(maxWidth: 760)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.vertical, 20)
    }
  }

  private var remindersSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("APPLE REMINDERS", systemImage: "checklist")
          .font(.system(size: 10.5, weight: .bold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.badgeText)
        Spacer()
        if !remindersStore.isAuthorized {
          Button("Connect Reminders") { remindersStore.requestAccess() }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(WarmShellColors.badgeFill, in: Capsule())
        } else {
          Text("\(filteredReminders.count) open")
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)
        }
      }

      if remindersStore.isAuthorized {
        HStack(spacing: 8) {
          TextField(
            "Add a reminder…", text: $newReminderTitle,
            prompt: Text("Add a reminder…").foregroundStyle(WarmShellColors.mutedText)
          )
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.primaryText)
          .onSubmit { submitReminder() }

          Toggle("Today", isOn: $dueToday)
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)

          Button("Add") { submitReminder() }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(WarmShellColors.userBubble, in: Capsule())
            .disabled(newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(WarmShellColors.canvas, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
          RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1)
        )

        if filteredReminders.isEmpty {
          Text("No incomplete reminders in this list.")
            .font(.system(size: 12.5))
            .foregroundStyle(WarmShellColors.mutedText)
        } else {
          VStack(alignment: .leading, spacing: 9) {
            ForEach(filteredReminders) { item in
              Button {
                remindersStore.toggle(id: item.id)
              } label: {
                HStack(alignment: .top, spacing: 10) {
                  Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(item.isCompleted ? Color.purple : WarmShellColors.mutedText)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.title)
                      .font(.system(size: 13, weight: .medium))
                      .foregroundStyle(WarmShellColors.primaryText)
                    HStack(spacing: 6) {
                      Text(verbatim: item.dueLabel)
                        .foregroundStyle(
                          item.isOverdue ? Color.red.opacity(0.85) : WarmShellColors.mutedText)
                      Text("·").foregroundStyle(WarmShellColors.mutedText)
                      Text(verbatim: item.listName).foregroundStyle(WarmShellColors.mutedText)
                    }
                    .font(.system(size: 11))
                  }
                  Spacer()
                }
                .contentShape(Rectangle())
              }
              .buttonStyle(.plain)
            }
          }
        }
      }
    }
    .padding(16)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private var tasksSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("MEMOSHI BOT TASKS", systemImage: "cpu")
          .font(.system(size: 10.5, weight: .bold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.badgeText)
        Spacer()
        Text("\(sortedTasks.count) recorded")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      }

      if sortedTasks.isEmpty {
        Text("No bot tasks recorded yet. Start a turn in any conversation to track tasks here.")
          .font(.system(size: 12.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else {
        ForEach(sortedTasks.prefix(20), id: \.id) { task in
          Button {
            onSelectConversation(task.conversationId)
          } label: {
            HStack(spacing: 10) {
              Image(systemName: taskSymbol(task.status))
                .font(.system(size: 14))
                .foregroundStyle(taskColor(task.status))
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: task.title.rawValue)
                  .font(.system(size: 13, weight: .medium))
                  .foregroundStyle(WarmShellColors.primaryText)
                  .lineLimit(1)
                Text(verbatim: task.statusLabel)
                  .font(.system(size: 11.5))
                  .foregroundStyle(WarmShellColors.mutedText)
              }
              Spacer()
              Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(16)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private func submitReminder() {
    let trimmed = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let dueDate: Date? =
      dueToday
      ? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) : nil
    remindersStore.addReminder(title: trimmed, dueDate: dueDate)
    newReminderTitle = ""
  }

  private func taskSymbol(_ status: TaskStatus) -> String {
    switch status {
    case .done: "checkmark.circle.fill"
    case .failed: "exclamationmark.triangle.fill"
    case .canceled: "xmark.circle"
    case .waiting: "hand.raised.fill"
    default: "clock.arrow.trianglehead.counterclockwise.rotate.90"
    }
  }

  private func taskColor(_ status: TaskStatus) -> Color {
    switch status {
    case .done: Color(red: 0.18, green: 0.68, blue: 0.36)
    case .failed: Color.red.opacity(0.85)
    case .waiting: WarmShellColors.badgeText
    default: WarmShellColors.mutedText
    }
  }
}

// MARK: - Contacts Pane (AP-18)

private struct ContactsAppPane: View {
  let contactsStore: LiveContactsStore
  @State private var searchQuery = ""
  @State private var copiedValue: String?

  private var filteredContacts: [LiveContactsStore.ContactItem] {
    let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return contactsStore.contacts }
    return contactsStore.contacts.filter { item in
      item.fullName.localizedCaseInsensitiveContains(query)
        || (item.organization?.localizedCaseInsensitiveContains(query) ?? false)
        || item.emails.contains(where: { $0.localizedCaseInsensitiveContains(query) })
        || item.phones.contains(where: { $0.localizedCaseInsensitiveContains(query) })
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      if !contactsStore.isAuthorized {
        VStack(alignment: .leading, spacing: 10) {
          Label("Apple Contacts", systemImage: "person.crop.circle")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Connect Apple Contacts to search people, copy addresses, and start emails.")
            .font(.system(size: 13))
            .foregroundStyle(WarmShellColors.mutedText)
          Button("Connect Apple Contacts") { contactsStore.requestAccess() }
            .buttonStyle(.plain)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(WarmShellColors.badgeFill, in: Capsule())
        }
        .padding(18)
        .frame(maxWidth: 760, alignment: .leading)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
          RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(WarmShellColors.cardBorder, lineWidth: 1)
        )
        .padding(28)
        Spacer()
      } else {
        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass")
            .font(.system(size: 13))
            .foregroundStyle(WarmShellColors.mutedText)
          TextField(
            "Search \(contactsStore.contacts.count) contacts…", text: $searchQuery,
            prompt: Text("Search \(contactsStore.contacts.count) contacts…")
              .foregroundStyle(WarmShellColors.mutedText)
          )
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.primaryText)
          if !searchQuery.isEmpty {
            Button {
              searchQuery = ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12.5))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            .buttonStyle(.plain)
          }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(WarmShellColors.card, in: Capsule())
        .overlay(Capsule().stroke(WarmShellColors.cardBorder, lineWidth: 1))
        .frame(maxWidth: 760)
        .padding(.horizontal, 28)
        .padding(.top, 16)
        .padding(.bottom, 12)

        if contactsStore.isLoading {
          ProgressView("Loading Contacts…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredContacts.isEmpty {
          ContentUnavailableView(
            "No Contacts Found",
            systemImage: "person.crop.circle",
            description: Text("Try a different name, organization, email, or phone number.")
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
              ForEach(filteredContacts.prefix(150)) { person in
                contactRow(person)
              }
            }
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
          }
        }
      }
    }
  }

  private func contactRow(_ person: LiveContactsStore.ContactItem) -> some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle()
          .fill(WarmShellColors.badgeFill)
        Text(String(person.fullName.prefix(1)).uppercased())
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(WarmShellColors.badgeText)
      }
      .frame(width: 34, height: 34)

      VStack(alignment: .leading, spacing: 3) {
        HStack(spacing: 6) {
          Text(verbatim: person.fullName)
            .font(.system(size: 13.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          if let org = person.organization {
            Text("· \(org)")
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.mutedText)
              .lineLimit(1)
          }
        }
        if let email = person.emails.first {
          Text(verbatim: email)
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        if let phone = person.phones.first {
          Text(verbatim: phone)
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }
      }

      Spacer(minLength: 8)

      HStack(spacing: 6) {
        if let email = person.emails.first {
          Button {
            copy(email)
          } label: {
            Label(copiedValue == email ? "Copied" : "Email", systemImage: "doc.on.doc")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())

          if let mailURL = URL(string: "mailto:\(email)") {
            Button {
              NSWorkspace.shared.open(mailURL)
            } label: {
              Image(systemName: "envelope")
                .font(.system(size: 11.5, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(WarmShellColors.badgeText)
            .frame(width: 26, height: 26)
            .background(WarmShellColors.badgeFill, in: Circle())
            .help("Compose Email")
          }
        }
        if let phone = person.phones.first {
          Button {
            copy(phone)
          } label: {
            Label(copiedValue == phone ? "Copied" : "Phone", systemImage: "phone")
              .font(.system(size: 11, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 9)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())
        }
      }
    }
    .padding(12)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private func copy(_ value: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    copiedValue = value
    Task {
      try? await Task.sleep(for: .seconds(1.4))
      if copiedValue == value { copiedValue = nil }
    }
  }
}

// MARK: - Local Markdown Notes Pane (AP-19)

private struct NotesAppPane: View {
  let notesStore: NotesDocumentStore
  @State private var selectedNoteID: String?
  @State private var draftContent = ""
  @State private var isPreviewMode = false
  @State private var newNoteTitle = ""

  private var selectedNote: NotesDocumentStore.NoteDocument? {
    guard let selectedNoteID else { return notesStore.notes.first }
    return notesStore.notes.first { $0.id == selectedNoteID } ?? notesStore.notes.first
  }

  var body: some View {
    HStack(spacing: 0) {
      notesSidebar
        .frame(width: 240)
      Rectangle()
        .fill(WarmShellColors.divider)
        .frame(width: 1)
      noteEditorArea
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      notesStore.reload()
      syncEditorToSelection()
    }
    .onChange(of: selectedNote?.id) { _, _ in
      syncEditorToSelection()
    }
  }

  private var notesSidebar: some View {
    VStack(spacing: 10) {
      HStack(spacing: 6) {
        TextField(
          "New note title…", text: $newNoteTitle,
          prompt: Text("New note title…").foregroundStyle(WarmShellColors.mutedText)
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12.5))
        .foregroundStyle(WarmShellColors.primaryText)
        .onSubmit { createNote() }

        Button {
          createNote()
        } label: {
          Image(systemName: "plus")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .background(WarmShellColors.userBubble, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Create Markdown Note")
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 6)
      .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1))
      .padding(.horizontal, 12)
      .padding(.top, 14)

      if notesStore.notes.isEmpty {
        VStack(spacing: 6) {
          Text("No Notes Yet")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Notes are stored as real .md files in Application Support.")
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)
            .multilineTextAlignment(.center)
        }
        .padding(16)
        Spacer()
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 4) {
            ForEach(notesStore.notes) { note in
              let isSelected = selectedNote?.id == note.id
              Button {
                selectedNoteID = note.id
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(verbatim: note.title)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(WarmShellColors.primaryText)
                    .lineLimit(1)
                  Text(note.modifiedAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.system(size: 11))
                    .foregroundStyle(WarmShellColors.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                  isSelected ? WarmShellColors.badgeFill : Color.clear,
                  in: RoundedRectangle(cornerRadius: 10)
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 10)
          .padding(.bottom, 16)
        }
      }
    }
  }

  @ViewBuilder
  private var noteEditorArea: some View {
    if let note = selectedNote {
      let hasUnsavedChanges = draftContent != note.content
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: note.title)
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
              .lineLimit(1)
            Text(verbatim: note.filename)
              .font(.system(size: 11, design: .monospaced))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          Spacer()
          Button(isPreviewMode ? "Edit" : "Preview") {
            isPreviewMode.toggle()
          }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())

          Button("Save") {
            notesStore.saveNote(note, content: draftContent)
          }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background(
            hasUnsavedChanges ? WarmShellColors.userBubble : WarmShellColors.mutedText.opacity(0.4),
            in: Capsule()
          )
          .disabled(!hasUnsavedChanges)

          Button {
            NSWorkspace.shared.activateFileViewerSelecting([note.fileURL])
          } label: {
            Image(systemName: "folder")
              .font(.system(size: 12.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .buttonStyle(.plain)
          .help("Reveal Note in Finder")

          Button(role: .destructive) {
            notesStore.deleteNote(note)
            selectedNoteID = notesStore.notes.first?.id
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 12.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .buttonStyle(.plain)
          .help("Delete Note")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)

        Divider().overlay(WarmShellColors.divider)

        if isPreviewMode {
          ScrollView {
            MarkdownMessageView(text: draftContent, isUser: false)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(22)
          }
        } else {
          TextEditor(text: $draftContent)
            .font(.system(size: 13.5, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(16)
        }
      }
    } else {
      ContentUnavailableView {
        Label("Select or Create a Note", systemImage: "note.text")
      } description: {
        Text("Create a local Markdown note to keep project plans, snippets, and drafts on this Mac.")
      } actions: {
        Button("Create First Note") {
          newNoteTitle = "Quick Note"
          createNote()
        }
      }
    }
  }

  private func createNote() {
    if let created = notesStore.createNote(title: newNoteTitle) {
      newNoteTitle = ""
      selectedNoteID = created.id
      draftContent = created.content
      isPreviewMode = false
    }
  }

  private func syncEditorToSelection() {
    if let note = selectedNote {
      selectedNoteID = note.id
      draftContent = note.content
    } else {
      draftContent = ""
    }
  }
}

// MARK: - Files & Library Pane (AP-20)

private struct FilesLibraryAppPane: View {
  private struct DirectoryEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    let fileSize: Int64?
    let modifiedAt: Date?
  }

  let model: LiveChatModel
  var onOpenFolders: () -> Void

  @State private var selectedGrantID: GrantID?
  @State private var currentFolderURL: URL?
  @State private var entries: [DirectoryEntry] = []
  @State private var readError: String?

  private var activeGrants: [FolderGrantSummary] {
    model.folders.grants.filter { $0.status == .active }
  }

  private var selectedGrant: FolderGrantSummary? {
    if let selectedGrantID, let match = activeGrants.first(where: { $0.id == selectedGrantID }) {
      return match
    }
    return activeGrants.first
  }

  var body: some View {
    HStack(spacing: 0) {
      grantsList
        .frame(width: 260)
      Rectangle()
        .fill(WarmShellColors.divider)
        .frame(width: 1)
      browserPane
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      if let grant = selectedGrant {
        selectGrant(grant)
      }
    }
    .onChange(of: activeGrants.map(\.id)) { _, _ in
      if let grant = selectedGrant {
        if currentFolderURL == nil || !isInsideGrant(currentFolderURL, grant: grant) {
          selectGrant(grant)
        }
      } else {
        currentFolderURL = nil
        entries = []
      }
    }
  }

  private var grantsList: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("GRANTED FOLDERS")
          .font(.system(size: 10.5, weight: .bold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
        Button("Manage…", action: onOpenFolders)
          .buttonStyle(.plain)
          .font(.system(size: 11.5, weight: .semibold))
          .foregroundStyle(WarmShellColors.badgeText)
      }
      .padding(.horizontal, 14)
      .padding(.top, 14)

      if activeGrants.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("No active folder grants")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Grant a folder to your Assistant to browse and share files safely.")
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
          Button("Manage Folder Grants…", action: onOpenFolders)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(WarmShellColors.badgeFill, in: Capsule())
        }
        .padding(.horizontal, 14)
        Spacer()
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 6) {
            ForEach(activeGrants, id: \.id) { grant in
              let isSelected = selectedGrant?.id == grant.id
              Button {
                selectGrant(grant)
              } label: {
                VStack(alignment: .leading, spacing: 3) {
                  HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                      .font(.system(size: 12.5))
                      .foregroundStyle(WarmShellColors.badgeText)
                    Text(verbatim: (grant.path as NSString).lastPathComponent)
                      .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                      .foregroundStyle(WarmShellColors.primaryText)
                      .lineLimit(1)
                    Spacer()
                    Text(grant.access == .write ? "Read & Write" : "Read Only")
                      .font(.system(size: 10, weight: .semibold))
                      .foregroundStyle(WarmShellColors.mutedText)
                  }
                  Text(verbatim: grant.path)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WarmShellColors.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                }
                .padding(10)
                .background(
                  isSelected ? WarmShellColors.badgeFill : WarmShellColors.card,
                  in: RoundedRectangle(cornerRadius: 10)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 10)
                    .stroke(WarmShellColors.cardBorder, lineWidth: 1)
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(.horizontal, 12)
          .padding(.bottom, 16)
        }
      }
    }
  }

  @ViewBuilder
  private var browserPane: some View {
    if let grant = selectedGrant, let folderURL = currentFolderURL {
      let grantRoot = URL(fileURLWithPath: grant.path, isDirectory: true).standardizedFileURL
      let canGoUp = folderURL.standardizedFileURL.path != grantRoot.path
      VStack(spacing: 0) {
        HStack(spacing: 10) {
          if canGoUp {
            Button {
              let parent = folderURL.deletingLastPathComponent().standardizedFileURL
              if isInsideGrant(parent, grant: grant) {
                loadDirectory(parent)
              }
            } label: {
              Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
                .frame(width: 26, height: 26)
                .background(WarmShellColors.pill, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Parent Folder")
          }
          Text(verbatim: folderURL.path)
            .font(.system(size: 12, design: .monospaced))
            .foregroundStyle(WarmShellColors.mutedText)
            .lineLimit(1)
            .truncationMode(.head)
          Spacer()
          Button {
            NSWorkspace.shared.activateFileViewerSelecting([folderURL])
          } label: {
            Label("Reveal in Finder", systemImage: "arrow.up.right.square")
              .font(.system(size: 11.5, weight: .medium))
          }
          .buttonStyle(.plain)
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)

        Divider().overlay(WarmShellColors.divider)

        if let readError {
          ContentUnavailableView(
            "Unable to Read Folder",
            systemImage: "exclamationmark.triangle",
            description: Text(verbatim: readError)
          )
        } else if entries.isEmpty {
          ContentUnavailableView(
            "Empty Folder",
            systemImage: "folder",
            description: Text("This granted folder has no visible files.")
          )
        } else {
          ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
              ForEach(entries) { entry in
                HStack(spacing: 10) {
                  Image(systemName: entry.isDirectory ? "folder.fill" : "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(
                      entry.isDirectory ? WarmShellColors.badgeText : WarmShellColors.mutedText)
                    .frame(width: 20)
                  VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: entry.name)
                      .font(.system(size: 13, weight: .medium))
                      .foregroundStyle(WarmShellColors.primaryText)
                      .lineLimit(1)
                    if let modified = entry.modifiedAt {
                      HStack(spacing: 6) {
                        Text(modified, format: .dateTime.month(.abbreviated).day().hour().minute())
                        if let size = entry.fileSize, !entry.isDirectory {
                          Text("·")
                          Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        }
                      }
                      .font(.system(size: 11))
                      .foregroundStyle(WarmShellColors.mutedText)
                    }
                  }
                  Spacer()
                  if entry.isDirectory {
                    Button("Open") { loadDirectory(entry.url) }
                      .buttonStyle(.plain)
                      .font(.system(size: 11.5, weight: .medium))
                      .foregroundStyle(WarmShellColors.badgeText)
                      .padding(.horizontal, 9)
                      .padding(.vertical, 4)
                      .background(WarmShellColors.badgeFill, in: Capsule())
                  } else {
                    Button("Open") { NSWorkspace.shared.open(entry.url) }
                      .buttonStyle(.plain)
                      .font(.system(size: 11.5, weight: .medium))
                      .foregroundStyle(WarmShellColors.primaryText)
                      .padding(.horizontal, 9)
                      .padding(.vertical, 4)
                      .background(WarmShellColors.pill, in: Capsule())
                  }
                  Button {
                    NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                  } label: {
                    Image(systemName: "magnifyingglass")
                      .font(.system(size: 11.5))
                      .foregroundStyle(WarmShellColors.mutedText)
                  }
                  .buttonStyle(.plain)
                  .help("Reveal in Finder")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                  WarmShellColors.card,
                  in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                  RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(WarmShellColors.cardBorder, lineWidth: 1)
                )
              }
            }
            .padding(16)
          }
        }
      }
    } else {
      ContentUnavailableView {
        Label("Files & Library", systemImage: "folder")
      } description: {
        Text("Select an active folder grant on the left or grant a folder to your Assistant.")
      } actions: {
        Button("Manage Folder Grants…", action: onOpenFolders)
      }
    }
  }

  private func selectGrant(_ grant: FolderGrantSummary) {
    selectedGrantID = grant.id
    let root = URL(fileURLWithPath: grant.path, isDirectory: true).standardizedFileURL
    loadDirectory(root)
  }

  private func isInsideGrant(_ url: URL?, grant: FolderGrantSummary) -> Bool {
    guard let url else { return false }
    let rootPath = URL(fileURLWithPath: grant.path, isDirectory: true).standardizedFileURL.path
    let candidate = url.standardizedFileURL.path
    return candidate == rootPath || candidate.hasPrefix(rootPath + "/")
  }

  private func loadDirectory(_ url: URL) {
    currentFolderURL = url
    do {
      let urls = try FileManager.default.contentsOfDirectory(
        at: url,
        includingPropertiesForKeys: [
          .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        ],
        options: [.skipsHiddenFiles]
      )
      let mapped = urls.map { item -> DirectoryEntry in
        let values = try? item.resourceValues(forKeys: [
          .isDirectoryKey, .fileSizeKey, .contentModificationDateKey,
        ])
        return DirectoryEntry(
          id: item.path,
          name: item.lastPathComponent,
          url: item,
          isDirectory: values?.isDirectory == true,
          fileSize: values?.fileSize.map(Int64.init),
          modifiedAt: values?.contentModificationDate
        )
      }
      entries = mapped.sorted { lhs, rhs in
        if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
      }
      readError = nil
    } catch {
      entries = []
      readError = error.localizedDescription
    }
  }
}

// MARK: - Mail Drafts & Provider Accounts Pane (AP-15, D116, D118)

private struct MailAppPane: View {
  let mailStore: MailWorkspaceStore
  @State private var selectedDraftID: String?
  @State private var toField = ""
  @State private var subjectField = ""
  @State private var bodyField = ""
  @State private var isAddingAccount = false
  @State private var newProvider: MailProviderKind = .gmail
  @State private var newEmail = ""
  @State private var newDisplayName = ""
  @State private var newToken = ""

  private var selectedDraft: MailDraftRecord? {
    guard let selectedDraftID else { return mailStore.drafts.first }
    return mailStore.drafts.first { $0.id == selectedDraftID } ?? mailStore.drafts.first
  }

  var body: some View {
    HStack(spacing: 0) {
      leftColumn
        .frame(width: 280)
      Divider().overlay(WarmShellColors.divider)
      rightDetailColumn
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .onAppear {
      mailStore.reload()
      syncEditorToSelection()
    }
    .onChange(of: selectedDraft?.id) { _, _ in
      syncEditorToSelection()
    }
  }

  private var leftColumn: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        accountsSection
        Divider().overlay(WarmShellColors.divider)
        draftsSection
        if !mailStore.auditEntries.isEmpty {
          Divider().overlay(WarmShellColors.divider)
          auditSection
        }
      }
      .padding(14)
    }
    .background(WarmShellColors.canvas)
  }

  private var accountsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("MAIL ACCOUNTS")
          .font(.system(size: 10.5, weight: .semibold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
        Button {
          isAddingAccount.toggle()
        } label: {
          Image(systemName: isAddingAccount ? "minus.circle" : "plus.circle")
            .font(.system(size: 13))
            .foregroundStyle(WarmShellColors.badgeText)
        }
        .buttonStyle(.plain)
        .help("Connect Gmail or Microsoft 365 OAuth token")
      }

      if isAddingAccount {
        VStack(alignment: .leading, spacing: 7) {
          Picker("Provider", selection: $newProvider) {
            ForEach(MailProviderKind.allCases, id: \.self) { provider in
              Text(provider.displayName).tag(provider)
            }
          }
          .pickerStyle(.segmented)

          TextField("Email address", text: $newEmail)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
          TextField("Display name (optional)", text: $newDisplayName)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
          SecureField("OAuth Bearer token (stored in Keychain)", text: $newToken)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))

          HStack {
            Spacer()
            Button("Save Account") {
              mailStore.addAccount(
                provider: newProvider, email: newEmail,
                displayName: newDisplayName, accessToken: newToken)
              newEmail = ""
              newDisplayName = ""
              newToken = ""
              isAddingAccount = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(
              newEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
          }
        }
        .padding(10)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1))
      }

      if mailStore.accounts.isEmpty {
        Text("No live Gmail or Microsoft 365 account connected. Bots can still stage drafts locally for your review.")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else {
        ForEach(mailStore.accounts) { account in
          HStack(spacing: 8) {
            Image(systemName: "envelope.badge.shield.half.filled")
              .font(.system(size: 12))
              .foregroundStyle(WarmShellColors.badgeText)
            VStack(alignment: .leading, spacing: 1) {
              Text(account.emailAddress)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WarmShellColors.primaryText)
                .lineLimit(1)
              Text(account.provider.displayName + " · Keychain token")
                .font(.system(size: 10.5))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            Spacer()
            Button(role: .destructive) {
              mailStore.removeAccount(account)
            } label: {
              Image(systemName: "trash")
                .font(.system(size: 11))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            .buttonStyle(.plain)
          }
          .padding(.horizontal, 10)
          .padding(.vertical, 7)
          .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(WarmShellColors.cardBorder, lineWidth: 1))
        }
      }
    }
  }

  private var draftsSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text("STAGED DRAFTS (\(mailStore.drafts.count))")
          .font(.system(size: 10.5, weight: .semibold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.mutedText)
        Spacer()
        Button {
          selectedDraftID = nil
          toField = ""
          subjectField = ""
          bodyField = ""
        } label: {
          Label("New", systemImage: "square.and.pencil")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WarmShellColors.badgeText)
        }
        .buttonStyle(.plain)
      }

      if mailStore.drafts.isEmpty {
        Text("Drafts prepared by bots via `mail_draft` or created here appear for review before sending.")
          .font(.system(size: 11.5))
          .foregroundStyle(WarmShellColors.mutedText)
      } else {
        ForEach(mailStore.drafts) { draft in
          let isSelected = selectedDraft?.id == draft.id
          Button {
            selectedDraftID = draft.id
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(draft.subject)
                  .font(.system(size: 12.5, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                  .lineLimit(1)
                Spacer()
                if draft.remoteDraftID != nil {
                  Image(systemName: "cloud.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(WarmShellColors.badgeText)
                }
              }
              Text("To: \(draft.to.joined(separator: ", "))")
                .font(.system(size: 11))
                .foregroundStyle(WarmShellColors.mutedText)
                .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
              isSelected ? WarmShellColors.badgeFill : WarmShellColors.card,
              in: RoundedRectangle(cornerRadius: 9)
            )
            .overlay(
              RoundedRectangle(cornerRadius: 9).stroke(
                isSelected ? WarmShellColors.badgeText.opacity(0.35) : WarmShellColors.cardBorder,
                lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var auditSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("RECENT ORGANIZE AUDIT")
        .font(.system(size: 10.5, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(WarmShellColors.mutedText)
      ForEach(mailStore.auditEntries.prefix(6)) { entry in
        VStack(alignment: .leading, spacing: 2) {
          Text("\(entry.action.rawValue) · \(entry.messageID.prefix(12))")
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Reversible via \(entry.inverseAction.rawValue)")
            .font(.system(size: 10.5))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        .padding(.vertical, 3)
      }
    }
  }

  private var rightDetailColumn: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Text(selectedDraft == nil ? "New Staged Draft" : "Review Draft (Not Sent)")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(WarmShellColors.primaryText)
        Spacer()
        if let draft = selectedDraft {
          Button {
            mailStore.openDraftInMailClient(draft)
          } label: {
            Label("Open in Mail App", systemImage: "paperplane")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(WarmShellColors.primaryText)
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(WarmShellColors.pill, in: Capsule())
          }
          .buttonStyle(.plain)
          .help("Hand off to your default macOS mail client to review and send")

          Button(role: .destructive) {
            mailStore.deleteDraft(draft)
            selectedDraftID = mailStore.drafts.first?.id
          } label: {
            Image(systemName: "trash")
              .font(.system(size: 12.5))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .buttonStyle(.plain)
        }

        Button("Save Draft") {
          let recipients = toField.split(separator: ",").map(String.init)
          if let saved = mailStore.saveDraft(
            id: selectedDraft?.id, to: recipients, subject: subjectField, body: bodyField)
          {
            selectedDraftID = saved.id
          }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(WarmShellColors.badgeText, in: Capsule())
        .disabled(
          toField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || subjectField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        )
      }

      VStack(spacing: 8) {
        TextField("To (comma-separated emails)", text: $toField)
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .padding(9)
          .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(WarmShellColors.cardBorder, lineWidth: 1))

        TextField("Subject", text: $subjectField)
          .textFieldStyle(.plain)
          .font(.system(size: 13.5, weight: .medium))
          .padding(9)
          .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 9))
          .overlay(RoundedRectangle(cornerRadius: 9).stroke(WarmShellColors.cardBorder, lineWidth: 1))
      }

      TextEditor(text: $bodyField)
        .font(.system(size: 13.5))
        .scrollContentBackground(.hidden)
        .padding(10)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1))

      Text("Safety (D116): Bots stage drafts via `mail_draft` and tidy via reversible `mail_organize`. Memoshi never reads Apple Mail's store or uses Apple Events.")
        .font(.system(size: 11))
        .foregroundStyle(WarmShellColors.mutedText)
    }
    .padding(20)
  }

  private func syncEditorToSelection() {
    if let draft = selectedDraft {
      toField = draft.to.joined(separator: ", ")
      subjectField = draft.subject
      bodyField = draft.body
    } else {
      toField = ""
      subjectField = ""
      bodyField = ""
    }
  }
}

// MARK: - Search & Built-in Connector Catalog Pane (D112, D120, CON-14)

private struct ConnectorsAppPane: View {
  let connectorStore: ConnectorWorkspaceStore
  @State private var editingConnectorID: String?
  @State private var pendingCardID: String?
  @State private var tokenDraft = ""

  private var pendingCards: [ConnectorConnectCard] {
    connectorStore.connectCards.filter { $0.status == .pending }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !pendingCards.isEmpty {
          pendingConnectCardsSection
        }
        searchProviderSection
        catalogSection
      }
      .frame(maxWidth: 780)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.vertical, 20)
    }
    .onAppear { connectorStore.reload() }
  }

  private var pendingConnectCardsSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("BOT CONNECT REQUESTS (\(pendingCards.count))")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(WarmShellColors.badgeText)

      ForEach(pendingCards) { card in
        let meta = ConnectorCatalogStore.connector(id: card.connectorID)
        VStack(alignment: .leading, spacing: 10) {
          HStack(spacing: 10) {
            Image(systemName: meta?.symbol ?? "puzzlepiece.extension")
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(WarmShellColors.badgeText)
              .frame(width: 30, height: 30)
              .background(WarmShellColors.badgeFill, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
              Text("Connect \(meta?.name ?? card.connectorID)")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
              Text(card.reason)
                .font(.system(size: 12))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            Spacer()
            Button("Dismiss") {
              connectorStore.dismissConnectCard(card.id)
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)

            Button("Connect") {
              editingConnectorID = card.connectorID
              pendingCardID = card.id
              tokenDraft = ""
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(WarmShellColors.badgeText, in: Capsule())
          }
        }
        .padding(14)
        .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
          RoundedRectangle(cornerRadius: 12)
            .stroke(WarmShellColors.badgeText.opacity(0.35), lineWidth: 1)
        )
      }
    }
  }

  private var searchProviderSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Default Web Search Provider (D120)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(WarmShellColors.primaryText)
          Text("Used by `web_search` on your own API key (Exa default). `x_search` uses your xAI key.")
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }
        Spacer()
      }

      HStack(spacing: 8) {
        ForEach(WebSearchProviderKind.allCases) { provider in
          let isSelected = connectorStore.settings.defaultWebProvider == provider
          let isKeyed = connectorStore.connectedIDs.contains(provider.connectorID)
          Button {
            connectorStore.setDefaultWebProvider(provider)
          } label: {
            HStack(spacing: 6) {
              Image(systemName: isKeyed ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11))
                .foregroundStyle(isKeyed ? WarmShellColors.badgeText : WarmShellColors.mutedText)
              Text(provider.displayName)
                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(
                  isSelected ? WarmShellColors.badgeText : WarmShellColors.primaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
              isSelected ? WarmShellColors.badgeFill : WarmShellColors.card,
              in: Capsule()
            )
            .overlay(
              Capsule().stroke(
                isSelected ? WarmShellColors.badgeText.opacity(0.4) : WarmShellColors.cardBorder,
                lineWidth: 1)
            )
          }
          .buttonStyle(.plain)
        }
      }
    }
    .padding(16)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(WarmShellColors.cardBorder, lineWidth: 1))
  }

  private var catalogSection: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("BUILT-IN CONNECTOR CATALOG (KEYCHAIN BY REFERENCE)")
        .font(.system(size: 11, weight: .semibold))
        .tracking(0.6)
        .foregroundStyle(WarmShellColors.mutedText)

      ForEach(ConnectorCategory.allCases, id: \.self) { category in
        let items = ConnectorCatalogStore.catalog.filter { $0.category == category }
        if !items.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue)
              .font(.system(size: 12.5, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)

            ForEach(items) { item in
              connectorRow(item)
            }
          }
        }
      }
    }
  }

  private func connectorRow(_ item: BuiltInConnector) -> some View {
    let isConnected = connectorStore.connectedIDs.contains(item.id)
    let isEditing = editingConnectorID == item.id

    return VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        Image(systemName: item.symbol)
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(isConnected ? WarmShellColors.badgeText : WarmShellColors.primaryText)
          .frame(width: 32, height: 32)
          .background(
            isConnected ? WarmShellColors.badgeFill : WarmShellColors.pill,
            in: RoundedRectangle(cornerRadius: 8))

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(item.name)
              .font(.system(size: 13.5, weight: .semibold))
              .foregroundStyle(WarmShellColors.primaryText)
            if isConnected {
              Text("Connected")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(WarmShellColors.badgeText)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(WarmShellColors.badgeFill, in: Capsule())
            }
          }
          Text(item.summary)
            .font(.system(size: 12))
            .foregroundStyle(WarmShellColors.mutedText)
        }

        Spacer()

        if isConnected {
          Button("Disconnect") {
            connectorStore.disconnect(item.id)
          }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(WarmShellColors.mutedText)
          .padding(.horizontal, 10)
          .padding(.vertical, 5)
          .background(WarmShellColors.pill, in: Capsule())
        } else {
          Button(isEditing ? "Cancel" : "Connect") {
            if isEditing {
              editingConnectorID = nil
              pendingCardID = nil
              tokenDraft = ""
            } else {
              editingConnectorID = item.id
              pendingCardID = nil
              tokenDraft = ""
            }
          }
          .buttonStyle(.plain)
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isEditing ? WarmShellColors.primaryText : .white)
          .padding(.horizontal, 12)
          .padding(.vertical, 5)
          .background(isEditing ? WarmShellColors.pill : WarmShellColors.badgeText, in: Capsule())
        }
      }

      if isEditing {
        HStack(spacing: 8) {
          SecureField(item.authHint + " (saved in Keychain)", text: $tokenDraft)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
          Button("Save Key") {
            connectorStore.connect(item.id, token: tokenDraft, resolvingCardID: pendingCardID)
            editingConnectorID = nil
            pendingCardID = nil
            tokenDraft = ""
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
      }
    }
    .padding(12)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WarmShellColors.cardBorder, lineWidth: 1))
  }
}


