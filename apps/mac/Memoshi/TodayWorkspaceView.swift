import AppKit
import DesignSystem
import EventKit
import Foundation
import MemoshiProtocol
import Observation
import SwiftUI

/// Live EventKit Reminders bridge shared across Today and the Right Sidebar (D116, AP-17).
@MainActor
@Observable
final class LiveRemindersStore {
  struct Item: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let listName: String
    let dueDate: Date?
    let dueLabel: String
    let isOverdue: Bool
    let isCompleted: Bool
  }

  private let store = EKEventStore()
  private(set) var isAuthorized = false
  private(set) var isLoading = false
  private(set) var items: [Item] = []

  init() {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if status == .fullAccess || status == .authorized {
      isAuthorized = true
      Task { await refresh() }
    }
  }

  func requestAccess() {
    let status = EKEventStore.authorizationStatus(for: .reminder)
    if status == .denied || status == .restricted {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
      {
        NSWorkspace.shared.open(url)
      }
      return
    }
    Task {
      let granted = (try? await store.requestFullAccessToReminders()) ?? false
      isAuthorized = granted
      if granted { await refresh() }
    }
  }

  func refresh() async {
    guard isAuthorized else { return }
    isLoading = true
    defer { isLoading = false }
    items = await Self.fetchItems()
  }

  func addReminder(title: String, dueDate: Date? = nil) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isAuthorized, !trimmed.isEmpty,
      let defaultList = store.defaultCalendarForNewReminders()
    else { return }
    let reminder = EKReminder(eventStore: store)
    reminder.title = trimmed
    reminder.calendar = defaultList
    if let dueDate {
      reminder.dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute], from: dueDate)
    }
    try? store.save(reminder, commit: true)
    Task { await refresh() }
  }

  func toggle(id: String) {
    guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
    reminder.isCompleted.toggle()
    try? store.save(reminder, commit: true)
    Task { await refresh() }
  }

  private nonisolated static func fetchItems() async -> [Item] {
    let localStore = EKEventStore()
    let predicate = localStore.predicateForIncompleteReminders(
      withDueDateStarting: nil, ending: nil, calendars: nil)
    let now = Date()
    return await withCheckedContinuation { continuation in
      localStore.fetchReminders(matching: predicate) { list in
        let mapped: [Item] = (list ?? []).map { r in
          let dueDate = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
          let dueStr =
            dueDate.map { $0.formatted(.dateTime.month(.abbreviated).day().hour().minute()) }
            ?? String(localized: "No due date")
          let overdue = dueDate.map { $0 < now } ?? false
          return Item(
            id: r.calendarItemIdentifier,
            title: r.title ?? String(localized: "Untitled"),
            listName: r.calendar.title.uppercased(),
            dueDate: dueDate,
            dueLabel: dueStr,
            isOverdue: overdue,
            isCompleted: r.isCompleted)
        }
        let sorted = mapped.sorted { lhs, rhs in
          if lhs.isOverdue != rhs.isOverdue { return lhs.isOverdue }
          switch (lhs.dueDate, rhs.dueDate) {
          case (let a?, let b?): return a < b
          case (_?, nil): return true
          case (nil, _?): return false
          case (nil, nil): return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
          }
        }
        continuation.resume(returning: sorted)
      }
    }
  }
}

/// Live EventKit Calendar bridge for the Today view (D116, AP-16).
@MainActor
@Observable
final class LiveCalendarStore {
  struct EventItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let calendarTitle: String
    let startDate: Date
    let endDate: Date
    let isAllDay: Bool
    let location: String?
  }

  struct CalendarDayGroup: Identifiable, Hashable, Sendable {
    let id: Date
    let date: Date
    let events: [EventItem]
  }

  private let store = EKEventStore()
  private(set) var isAuthorized = false
  private(set) var isLoading = false
  private(set) var events: [EventItem] = []

  init() {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .fullAccess || status == .authorized {
      isAuthorized = true
      Task { await refresh() }
    }
  }

  func requestAccess() {
    let status = EKEventStore.authorizationStatus(for: .event)
    if status == .denied || status == .restricted {
      if let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
      {
        NSWorkspace.shared.open(url)
      }
      return
    }
    Task {
      let granted = (try? await store.requestFullAccessToEvents()) ?? false
      isAuthorized = granted
      if granted { await refresh() }
    }
  }

  func refresh() async {
    guard isAuthorized else { return }
    isLoading = true
    defer { isLoading = false }
    events = await Self.fetchEvents()
  }

  func addEvent(title: String, startDate: Date, durationMinutes: Int = 60) {
    let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isAuthorized, !trimmed.isEmpty,
      let defaultCalendar = store.defaultCalendarForNewEvents
    else { return }
    let event = EKEvent(eventStore: store)
    event.title = trimmed
    event.calendar = defaultCalendar
    event.startDate = startDate
    event.endDate = startDate.addingTimeInterval(TimeInterval(max(15, durationMinutes) * 60))
    try? store.save(event, span: .thisEvent)
    Task { await refresh() }
  }

  nonisolated static func eventsByDay(
    _ events: [EventItem],
    startingFrom referenceDate: Date = Date(),
    days: Int = 7,
    calendar: Calendar = .current
  ) -> [CalendarDayGroup] {
    let startOfWindow = calendar.startOfDay(for: referenceDate)
    let clampedDays = max(1, days)
    return (0..<clampedDays).compactMap { offset in
      guard let dayStart = calendar.date(byAdding: .day, value: offset, to: startOfWindow),
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
      else { return nil }
      let matching = events
        .filter { $0.startDate < dayEnd && $0.endDate > dayStart }
        .sorted { $0.startDate < $1.startDate }
      return CalendarDayGroup(id: dayStart, date: dayStart, events: matching)
    }
  }

  private nonisolated static func fetchEvents() async -> [EventItem] {
    let localStore = EKEventStore()
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: Date())
    guard let end = calendar.date(byAdding: .day, value: 7, to: start) else { return [] }
    let predicate = localStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    return localStore.events(matching: predicate)
      .sorted { $0.startDate < $1.startDate }
      .map { event in
        EventItem(
          id: (event.eventIdentifier ?? UUID().uuidString) + "-\(event.startDate.timeIntervalSince1970)",
          title: event.title ?? String(localized: "Untitled Event"),
          calendarTitle: event.calendar.title,
          startDate: event.startDate,
          endDate: event.endDate,
          isAllDay: event.isAllDay,
          location: event.location?.isEmpty == false ? event.location : nil
        )
      }
  }
}

/// Live Today workspace view combining Apple Calendar, Apple Reminders, and active Memoshi work.
struct TodayWorkspaceView: View {
  let model: LiveChatModel
  let remindersStore: LiveRemindersStore
  let calendarStore: LiveCalendarStore
  let appearances: BotAppearanceStore
  var onOpenWaiting: () -> Void
  var onSelectConversation: (ConversationID) -> Void

  @State private var newReminderTitle = ""
  @State private var newReminderDueToday = false

  private var todayEvents: [LiveCalendarStore.EventItem] {
    calendarStore.events.filter { Calendar.current.isDateInToday($0.startDate) }
  }

  private var tomorrowEvents: [LiveCalendarStore.EventItem] {
    calendarStore.events.filter { Calendar.current.isDateInTomorrow($0.startDate) }
  }

  private var activeTasks: [MemoshiTask] {
    model.knownTasks.values
      .filter { [.queued, .running, .waiting].contains($0.status) }
      .sorted { $0.createdAt > $1.createdAt }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header

        if model.reviews.pendingCount > 0 || !activeTasks.isEmpty {
          attentionCard
        }

        calendarCard
        remindersCard

        if !model.directory.conversations.isEmpty {
          conversationsStrip
        }
      }
      .frame(maxWidth: 740)
      .frame(maxWidth: .infinity)
      .padding(.horizontal, 28)
      .padding(.top, 26)
      .padding(.bottom, 32)
    }
    .background(WarmShellColors.canvas)
    .accessibilityIdentifier("workspace.today")
    .task {
      model.loadTasks()
      if remindersStore.isAuthorized { await remindersStore.refresh() }
      if calendarStore.isAuthorized { await calendarStore.refresh() }
    }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Today")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(WarmShellColors.primaryText)
        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
          .font(.system(size: 13))
          .foregroundStyle(WarmShellColors.mutedText)
      }
      Spacer()
      Button {
        model.loadTasks()
        Task {
          if remindersStore.isAuthorized { await remindersStore.refresh() }
          if calendarStore.isAuthorized { await calendarStore.refresh() }
        }
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(WarmShellColors.primaryText)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(WarmShellColors.pill, in: Capsule())
      }
      .buttonStyle(.plain)
    }
  }

  private var attentionCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Label("NEEDS ATTENTION", systemImage: "bell.badge")
          .font(.system(size: 10.5, weight: .bold))
          .tracking(0.6)
          .foregroundStyle(WarmShellColors.badgeText)
        Spacer()
      }

      if model.reviews.pendingCount > 0 {
        Button(action: onOpenWaiting) {
          HStack(spacing: 10) {
            Image(systemName: "hand.raised.fill")
              .font(.system(size: 14))
              .foregroundStyle(WarmShellColors.badgeText)
            VStack(alignment: .leading, spacing: 2) {
              Text("\(model.reviews.pendingCount) pending approval(s)")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(WarmShellColors.primaryText)
              Text("Open Waiting for You to allow once or deny.")
                .font(.system(size: 12))
                .foregroundStyle(WarmShellColors.mutedText)
            }
            Spacer()
            Image(systemName: "chevron.right")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(WarmShellColors.mutedText)
          }
          .padding(10)
          .background(WarmShellColors.badgeFill.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
      }

      ForEach(activeTasks.prefix(4), id: \.id) { task in
        Button {
          onSelectConversation(task.conversationId)
        } label: {
          HStack(spacing: 10) {
            ProgressView().controlSize(.small)
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
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .stroke(WarmShellColors.cardBorder, lineWidth: 1)
    )
  }

  private var calendarCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 5) {
            Image(systemName: "calendar")
              .font(.system(size: 10.5, weight: .semibold))
            Text("CALENDAR")
              .font(.system(size: 10.5, weight: .bold))
              .tracking(0.6)
          }
          .foregroundStyle(WarmShellColors.badgeText)
          Text(
            calendarStore.isAuthorized
              ? "\(todayEvents.count) today · \(tomorrowEvents.count) tomorrow"
              : "Connect Apple Calendar to see your schedule"
          )
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText)
        }
        Spacer()
        if !calendarStore.isAuthorized {
          Button("Connect Calendar") { calendarStore.requestAccess() }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(WarmShellColors.badgeFill, in: Capsule())
        } else if calendarStore.isLoading {
          ProgressView().controlSize(.small)
        }
      }

      if calendarStore.isAuthorized {
        if todayEvents.isEmpty && tomorrowEvents.isEmpty {
          Text("No calendar events scheduled for today or tomorrow.")
            .font(.system(size: 12.5))
            .foregroundStyle(WarmShellColors.mutedText)
            .padding(.vertical, 4)
        } else {
          if !todayEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("TODAY")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WarmShellColors.mutedText)
              ForEach(todayEvents) { event in
                calendarEventRow(event)
              }
            }
          }
          if !tomorrowEvents.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
              Text("TOMORROW")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(WarmShellColors.mutedText)
                .padding(.top, todayEvents.isEmpty ? 0 : 4)
              ForEach(tomorrowEvents) { event in
                calendarEventRow(event)
              }
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

  private func calendarEventRow(_ event: LiveCalendarStore.EventItem) -> some View {
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

  private var remindersCard: some View {
    let overdueCount = remindersStore.items.filter(\.isOverdue).count
    return VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 5) {
            Image(systemName: "checklist")
              .font(.system(size: 10.5, weight: .semibold))
            Text("REMINDERS")
              .font(.system(size: 10.5, weight: .bold))
              .tracking(0.6)
          }
          .foregroundStyle(WarmShellColors.badgeText)
          Text(
            remindersStore.isAuthorized
              ? "\(remindersStore.items.count) open"
                + (overdueCount > 0 ? " · \(overdueCount) overdue" : "")
              : "Connect Apple Reminders to manage your tasks"
          )
          .font(.system(size: 12))
          .foregroundStyle(WarmShellColors.mutedText)
        }
        Spacer()
        if !remindersStore.isAuthorized {
          Button("Connect Reminders") { remindersStore.requestAccess() }
            .buttonStyle(.plain)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(WarmShellColors.badgeText)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(WarmShellColors.badgeFill, in: Capsule())
        } else if remindersStore.isLoading {
          ProgressView().controlSize(.small)
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
          .onSubmit { submitNewReminder() }

          Toggle("Today", isOn: $newReminderDueToday)
            .toggleStyle(.checkbox)
            .font(.system(size: 11.5))
            .foregroundStyle(WarmShellColors.mutedText)

          Button("Add") { submitNewReminder() }
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
          RoundedRectangle(cornerRadius: 10).stroke(WarmShellColors.cardBorder, lineWidth: 1))

        if remindersStore.items.isEmpty {
          Text("No open reminders in Apple Reminders.")
            .font(.system(size: 12.5))
            .foregroundStyle(WarmShellColors.mutedText)
            .padding(.vertical, 4)
        } else {
          VStack(alignment: .leading, spacing: 9) {
            ForEach(remindersStore.items) { item in
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
                      Text("·")
                        .foregroundStyle(WarmShellColors.mutedText)
                      Text(verbatim: item.listName)
                        .foregroundStyle(WarmShellColors.mutedText)
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

  private var conversationsStrip: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("YOUR BOTS")
        .font(.system(size: 10.5, weight: .bold))
        .tracking(0.6)
        .foregroundStyle(WarmShellColors.mutedText)
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
        ForEach(model.directory.conversations.prefix(6), id: \.id) { conv in
          let style = appearances.appearance(
            for: conv.botId, isAssistant: conv.kind == .assistant)
          Button {
            onSelectConversation(conv.id)
          } label: {
            HStack(spacing: 10) {
              ShellBotAvatar(symbol: style.symbol, gradient: style.gradient, size: 32)
              VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: conv.title)
                  .font(.system(size: 13, weight: .semibold))
                  .foregroundStyle(WarmShellColors.primaryText)
                  .lineLimit(1)
                Text(conv.kind == .session ? "Session" : "Live chat")
                  .font(.system(size: 11))
                  .foregroundStyle(WarmShellColors.mutedText)
              }
              Spacer()
            }
            .padding(10)
            .background(WarmShellColors.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
              RoundedRectangle(cornerRadius: 12).stroke(WarmShellColors.cardBorder, lineWidth: 1))
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private func submitNewReminder() {
    let trimmed = newReminderTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    let dueDate: Date? =
      newReminderDueToday
      ? Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) : nil
    remindersStore.addReminder(title: trimmed, dueDate: dueDate)
    newReminderTitle = ""
  }
}
