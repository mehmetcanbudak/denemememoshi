import Foundation
import MemoshiProtocol

#if canImport(EventKit)
  import EventKit
#endif
#if canImport(Contacts)
  import Contacts
#endif

/// Native Apple Calendar, Reminders, and Contacts host tools (`D116`, `AP-14`).
///
/// Each tool runs directly against Apple's EventKit / Contacts frameworks on macOS (and iOS
/// in Phase 3) with explicit macOS TCC authorization checks and Memoshi `PolicyHooks` gating.
/// Mail never uses Apple Mail's store or Apple Events (`D41`, `D116`).
public enum ApplePersonalTools {
  /// Returns all available native Apple personal-information tools on this platform.
  public static func definitions() -> [RuntimeToolDefinition] {
    var tools: [RuntimeToolDefinition] = []
    #if canImport(EventKit)
      tools.append(contentsOf: [
        calendarListTool(),
        calendarCreateTool(),
        remindersListTool(),
        remindersCreateTool(),
        remindersCompleteTool(),
      ])
    #endif
    #if canImport(Contacts)
      tools.append(contactsSearchTool())
    #endif
    return tools
  }

  /// Parses an ISO-8601 timestamp (with or without fractional seconds) or a `YYYY-MM-DD` date.
  public static func parseDate(_ raw: String, calendar: Calendar = .current) -> Date? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let parsed = fractional.date(from: trimmed) { return parsed }

    let standard = ISO8601DateFormatter()
    standard.formatOptions = [.withInternetDateTime]
    if let parsed = standard.date(from: trimmed) { return parsed }

    let dayOnly = DateFormatter()
    dayOnly.locale = Locale(identifier: "en_US_POSIX")
    dayOnly.calendar = calendar
    dayOnly.timeZone = calendar.timeZone
    dayOnly.dateFormat = "yyyy-MM-dd"
    if let parsed = dayOnly.date(from: trimmed) { return parsed }

    let localDateTime = DateFormatter()
    localDateTime.locale = Locale(identifier: "en_US_POSIX")
    localDateTime.calendar = calendar
    localDateTime.timeZone = calendar.timeZone
    localDateTime.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
    if let parsed = localDateTime.date(from: trimmed) { return parsed }

    localDateTime.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return localDateTime.date(from: trimmed)
  }

  /// Formats a date as an ISO-8601 string in the local time zone.
  public static func formatISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }

  #if canImport(EventKit)
    private struct CalendarEventSnapshot: Sendable {
      let id: String
      let title: String
      let calendar: String
      let startDate: Date
      let endDate: Date
      let isAllDay: Bool
      let location: String?
      let notes: String?
    }

    private struct ReminderSnapshot: Sendable {
      let id: String
      let title: String
      let list: String
      let isCompleted: Bool
      let dueDate: Date?
      let priority: Int
      let notes: String?
    }

    private static func ensureCalendarAccess(_ store: EKEventStore) async -> Bool {
      let status = EKEventStore.authorizationStatus(for: .event)
      if status == .fullAccess || status == .authorized { return true }
      if status == .denied || status == .restricted { return false }
      return (try? await store.requestFullAccessToEvents()) ?? false
    }

    private static func ensureRemindersAccess(_ store: EKEventStore) async -> Bool {
      let status = EKEventStore.authorizationStatus(for: .reminder)
      if status == .fullAccess || status == .authorized { return true }
      if status == .denied || status == .restricted { return false }
      return (try? await store.requestFullAccessToReminders()) ?? false
    }

    private static func calendarListTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "calendar_list",
        description:
          "List events from Apple Calendar over a date window (default next 7 days).",
        parameters: [
          "type": "object",
          "properties": [
            "startDate": [
              "type": "string",
              "description": "Optional ISO-8601 or YYYY-MM-DD start date (defaults to start of today).",
            ],
            "days": [
              "type": "integer",
              "minimum": 1,
              "maximum": 90,
              "description": "Number of days to include (default 7, max 90).",
            ],
            "calendarName": [
              "type": "string",
              "description": "Optional calendar title filter (case-insensitive).",
            ],
          ],
          "additionalProperties": false,
        ],
        operation: .appleRead,
        replaySafe: true,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments else {
            throw RuntimeToolError.invalidArguments
          }
          let startRaw = stringArg(values["startDate"])
          let days = clampInt(intArg(values["days"]) ?? 7, min: 1, max: 90)
          let calendarFilter = stringArg(values["calendarName"])?.trimmingCharacters(
            in: .whitespacesAndNewlines)

          let start: Date
          if let startRaw, !startRaw.isEmpty {
            guard let parsed = parseDate(startRaw) else {
              throw RuntimeToolError.invalidArguments
            }
            start = parsed
          } else {
            start = Calendar.current.startOfDay(for: Date())
          }
          let end = Calendar.current.date(byAdding: .day, value: days, to: start)
            ?? start.addingTimeInterval(TimeInterval(days) * 86_400)

          return try await invocation.runCancellable {
            let store = EKEventStore()
            guard await ensureCalendarAccess(store) else {
              return RuntimeToolResult(
                text:
                  "Apple Calendar access is not granted. Ask the user to enable Calendar access in System Settings → Privacy & Security → Calendars.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            let calendars: [EKCalendar]?
            if let calendarFilter, !calendarFilter.isEmpty {
              let matched = store.calendars(for: .event).filter {
                $0.title.localizedCaseInsensitiveCompare(calendarFilter) == .orderedSame
              }
              if matched.isEmpty {
                return RuntimeToolResult(
                  text: "No Apple Calendar named '\(calendarFilter)' was found."
                )
              }
              calendars = matched
            } else {
              calendars = nil
            }

            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
            let snapshots: [CalendarEventSnapshot] = store.events(matching: predicate)
              .sorted { $0.startDate < $1.startDate }
              .map { event in
                CalendarEventSnapshot(
                  id: event.eventIdentifier ?? UUID().uuidString,
                  title: event.title ?? "Untitled Event",
                  calendar: event.calendar?.title ?? "Calendar",
                  startDate: event.startDate,
                  endDate: event.endDate,
                  isAllDay: event.isAllDay,
                  location: event.location?.trimmingCharacters(in: .whitespacesAndNewlines),
                  notes: event.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
                )
              }

            if snapshots.isEmpty {
              return RuntimeToolResult(
                text: "No calendar events found between \(formatISO8601(start)) and \(formatISO8601(end))."
              )
            }

            let lines = snapshots.map { item -> String in
              var line =
                "- \(item.title) [\(item.calendar)] | \(formatISO8601(item.startDate)) → \(formatISO8601(item.endDate))"
              if item.isAllDay { line += " (All day)" }
              if let loc = item.location, !loc.isEmpty { line += " | Location: \(loc)" }
              if let notes = item.notes, !notes.isEmpty {
                line += " | Notes: \(String(notes.prefix(160)))"
              }
              return line
            }
            return RuntimeToolResult(
              text: "Found \(snapshots.count) calendar event(s):\n" + lines.joined(separator: "\n")
            )
          }
        }
      )
    }

    private static func calendarCreateTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "calendar_create",
        description: "Create a new event in Apple Calendar.",
        parameters: [
          "type": "object",
          "properties": [
            "title": ["type": "string", "minLength": 1, "maxLength": 240],
            "startDate": [
              "type": "string",
              "description": "ISO-8601 timestamp or YYYY-MM-DD date.",
            ],
            "endDate": [
              "type": "string",
              "description": "Optional ISO-8601 end timestamp (defaults to 1 hour after startDate).",
            ],
            "allDay": ["type": "boolean"],
            "location": ["type": "string", "maxLength": 300],
            "notes": ["type": "string", "maxLength": 2000],
            "calendarName": ["type": "string", "maxLength": 120],
          ],
          "required": ["title", "startDate"],
          "additionalProperties": false,
        ],
        operation: .connectorStage,
        replaySafe: false,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments,
            let title = stringArg(values["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty,
            let startRaw = stringArg(values["startDate"]),
            let startDate = parseDate(startRaw)
          else {
            throw RuntimeToolError.invalidArguments
          }
          let allDay = boolArg(values["allDay"]) ?? false
          let endDate: Date
          if let endRaw = stringArg(values["endDate"]), !endRaw.isEmpty {
            guard let parsed = parseDate(endRaw), parsed >= startDate else {
              throw RuntimeToolError.invalidArguments
            }
            endDate = parsed
          } else {
            endDate = startDate.addingTimeInterval(allDay ? 86_400 : 3_600)
          }
          let location = stringArg(values["location"])
          let notes = stringArg(values["notes"])
          let calendarName = stringArg(values["calendarName"])?.trimmingCharacters(
            in: .whitespacesAndNewlines)

          return try await invocation.runCancellable {
            let store = EKEventStore()
            guard await ensureCalendarAccess(store) else {
              return RuntimeToolResult(
                text: "Apple Calendar access is not granted.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            let targetCalendar: EKCalendar?
            if let calendarName, !calendarName.isEmpty {
              targetCalendar = store.calendars(for: .event).first {
                $0.title.localizedCaseInsensitiveCompare(calendarName) == .orderedSame
              } ?? store.defaultCalendarForNewEvents
            } else {
              targetCalendar = store.defaultCalendarForNewEvents
            }
            guard let calendar = targetCalendar else {
              return RuntimeToolResult(
                text: "No writable Apple Calendar is configured.",
                isError: true,
                effectOutcome: .notApplied
              )
            }

            let event = EKEvent(eventStore: store)
            event.title = title
            event.startDate = startDate
            event.endDate = endDate
            event.isAllDay = allDay
            event.location = location
            event.notes = notes
            event.calendar = calendar
            do {
              try store.save(event, span: .thisEvent)
            } catch {
              throw RuntimeToolExecutionError.notApplied
            }
            let eventID = event.eventIdentifier ?? "saved"
            return RuntimeToolResult(
              text:
                "Created calendar event '\(title)' in '\(calendar.title)' (\(formatISO8601(startDate)) → \(formatISO8601(endDate)), id: \(eventID))."
            )
          }
        }
      )
    }

    private static func remindersListTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "reminders_list",
        description:
          "List reminders from Apple Reminders (defaults to all incomplete reminders, including undated ones).",
        parameters: [
          "type": "object",
          "properties": [
            "includeCompleted": ["type": "boolean"],
            "listName": ["type": "string", "maxLength": 120],
            "limit": ["type": "integer", "minimum": 1, "maximum": 100],
          ],
          "additionalProperties": false,
        ],
        operation: .appleRead,
        replaySafe: true,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments else {
            throw RuntimeToolError.invalidArguments
          }
          let includeCompleted = boolArg(values["includeCompleted"]) ?? false
          let listName = stringArg(values["listName"])?.trimmingCharacters(in: .whitespacesAndNewlines)
          let limit = clampInt(intArg(values["limit"]) ?? 50, min: 1, max: 100)

          return try await invocation.runCancellable {
            let store = EKEventStore()
            guard await ensureRemindersAccess(store) else {
              return RuntimeToolResult(
                text:
                  "Apple Reminders access is not granted. Ask the user to enable Reminders access in System Settings → Privacy & Security → Reminders.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            let calendars: [EKCalendar]?
            if let listName, !listName.isEmpty {
              let matched = store.calendars(for: .reminder).filter {
                $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
              }
              if matched.isEmpty {
                return RuntimeToolResult(
                  text: "No Apple Reminders list named '\(listName)' was found."
                )
              }
              calendars = matched
            } else {
              calendars = nil
            }

            let predicate: NSPredicate =
              includeCompleted
              ? store.predicateForReminders(in: calendars)
              : store.predicateForIncompleteReminders(
                withDueDateStarting: nil, ending: nil, calendars: calendars)

            let snapshots = await fetchReminderSnapshots(store: store, predicate: predicate)
            let sorted = snapshots.sorted { lhs, rhs in
              switch (lhs.dueDate, rhs.dueDate) {
              case let (l?, r?): return l < r
              case (_?, nil): return true
              case (nil, _?): return false
              case (nil, nil):
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
              }
            }
            let capped = Array(sorted.prefix(limit))
            if capped.isEmpty {
              return RuntimeToolResult(text: "No matching reminders found.")
            }

            let lines = capped.map { item -> String in
              let box = item.isCompleted ? "[x]" : "[ ]"
              var line = "- \(box) \(item.title) [\(item.list)] (id: \(item.id))"
              if let due = item.dueDate { line += " | Due: \(formatISO8601(due))" }
              if item.priority > 0 { line += " | Priority: \(item.priority)" }
              if let notes = item.notes, !notes.isEmpty {
                line += " | Notes: \(String(notes.prefix(120)))"
              }
              return line
            }
            return RuntimeToolResult(
              text: "Found \(capped.count) reminder(s):\n" + lines.joined(separator: "\n")
            )
          }
        }
      )
    }

    private static func remindersCreateTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "reminders_create",
        description: "Create a new reminder in Apple Reminders.",
        parameters: [
          "type": "object",
          "properties": [
            "title": ["type": "string", "minLength": 1, "maxLength": 240],
            "dueDate": [
              "type": "string",
              "description": "Optional ISO-8601 timestamp or YYYY-MM-DD due date.",
            ],
            "listName": ["type": "string", "maxLength": 120],
            "notes": ["type": "string", "maxLength": 2000],
            "priority": ["type": "integer", "minimum": 0, "maximum": 9],
          ],
          "required": ["title"],
          "additionalProperties": false,
        ],
        operation: .connectorStage,
        replaySafe: false,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments,
            let title = stringArg(values["title"])?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
          else {
            throw RuntimeToolError.invalidArguments
          }
          let dueDate: Date?
          if let dueRaw = stringArg(values["dueDate"]), !dueRaw.isEmpty {
            guard let parsed = parseDate(dueRaw) else {
              throw RuntimeToolError.invalidArguments
            }
            dueDate = parsed
          } else {
            dueDate = nil
          }
          let listName = stringArg(values["listName"])?.trimmingCharacters(in: .whitespacesAndNewlines)
          let notes = stringArg(values["notes"])
          let priority = clampInt(intArg(values["priority"]) ?? 0, min: 0, max: 9)

          return try await invocation.runCancellable {
            let store = EKEventStore()
            guard await ensureRemindersAccess(store) else {
              return RuntimeToolResult(
                text: "Apple Reminders access is not granted.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            let targetCalendar: EKCalendar?
            if let listName, !listName.isEmpty {
              targetCalendar = store.calendars(for: .reminder).first {
                $0.title.localizedCaseInsensitiveCompare(listName) == .orderedSame
              } ?? store.defaultCalendarForNewReminders()
            } else {
              targetCalendar = store.defaultCalendarForNewReminders()
            }
            guard let calendar = targetCalendar else {
              return RuntimeToolResult(
                text: "No writable Apple Reminders list is configured.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            let reminder = EKReminder(eventStore: store)
            reminder.title = title
            reminder.notes = notes
            reminder.priority = priority
            reminder.calendar = calendar
            if let dueDate {
              reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: dueDate)
            }
            do {
              try store.save(reminder, commit: true)
            } catch {
              throw RuntimeToolExecutionError.notApplied
            }
            return RuntimeToolResult(
              text:
                "Created reminder '\(title)' in '\(calendar.title)' (id: \(reminder.calendarItemIdentifier))."
            )
          }
        }
      )
    }

    private static func remindersCompleteTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "reminders_complete",
        description: "Mark an Apple Reminder completed or incomplete by its identifier.",
        parameters: [
          "type": "object",
          "properties": [
            "id": ["type": "string", "minLength": 1, "maxLength": 200],
            "completed": ["type": "boolean"],
          ],
          "required": ["id"],
          "additionalProperties": false,
        ],
        operation: .connectorStage,
        replaySafe: false,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments,
            let id = stringArg(values["id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
            !id.isEmpty
          else {
            throw RuntimeToolError.invalidArguments
          }
          let completed = boolArg(values["completed"]) ?? true

          return try await invocation.runCancellable {
            let store = EKEventStore()
            guard await ensureRemindersAccess(store) else {
              return RuntimeToolResult(
                text: "Apple Reminders access is not granted.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
              return RuntimeToolResult(
                text: "No reminder found with id '\(id)'.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
            reminder.isCompleted = completed
            reminder.completionDate = completed ? Date() : nil
            do {
              try store.save(reminder, commit: true)
            } catch {
              throw RuntimeToolExecutionError.notApplied
            }
            let stateText = completed ? "completed" : "incomplete"
            return RuntimeToolResult(
              text: "Marked reminder '\(reminder.title ?? id)' as \(stateText)."
            )
          }
        }
      )
    }

    private static func fetchReminderSnapshots(
      store: EKEventStore, predicate: NSPredicate
    ) async -> [ReminderSnapshot] {
      await withCheckedContinuation { continuation in
        store.fetchReminders(matching: predicate) { reminders in
          let snapshots: [ReminderSnapshot] = (reminders ?? []).map { item in
            let due = item.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
            return ReminderSnapshot(
              id: item.calendarItemIdentifier,
              title: item.title ?? "Untitled Reminder",
              list: item.calendar?.title ?? "Reminders",
              isCompleted: item.isCompleted,
              dueDate: due,
              priority: item.priority,
              notes: item.notes?.trimmingCharacters(in: .whitespacesAndNewlines)
            )
          }
          continuation.resume(returning: snapshots)
        }
      }
    }
  #endif

  #if canImport(Contacts)
    private struct ContactSnapshot: Sendable {
      let id: String
      let fullName: String
      let organization: String?
      let emails: [String]
      let phones: [String]
    }

    private static func ensureContactsAccess(_ store: CNContactStore) async -> Bool {
      let status = CNContactStore.authorizationStatus(for: .contacts)
      if status == .authorized { return true }
      if status == .denied || status == .restricted { return false }
      return (try? await store.requestAccess(for: .contacts)) ?? false
    }

    private static func contactsSearchTool() -> RuntimeToolDefinition {
      RuntimeToolDefinition(
        name: "contacts_search",
        description: "Search Apple Contacts by name, email address, phone number, or organization.",
        parameters: [
          "type": "object",
          "properties": [
            "query": [
              "type": "string",
              "maxLength": 160,
              "description": "Optional case-insensitive filter across name, org, email, and phone.",
            ],
            "limit": ["type": "integer", "minimum": 1, "maximum": 50],
          ],
          "additionalProperties": false,
        ],
        operation: .appleRead,
        replaySafe: true,
        outputExposure: Exposure(untrusted: false, privateData: true),
        authorize: { _ in true },
        execute: { arguments, invocation in
          guard case .object(let values) = arguments else {
            throw RuntimeToolError.invalidArguments
          }
          let query =
            stringArg(values["query"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
          let limit = clampInt(intArg(values["limit"]) ?? 20, min: 1, max: 50)

          return try await invocation.runCancellable {
            let store = CNContactStore()
            guard await ensureContactsAccess(store) else {
              return RuntimeToolResult(
                text:
                  "Apple Contacts access is not granted. Ask the user to enable Contacts access in System Settings → Privacy & Security → Contacts.",
                isError: true,
                effectOutcome: .notApplied
              )
            }
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
            var matches: [ContactSnapshot] = []
            try? store.enumerateContacts(with: request) { contact, stop in
              let full = [contact.givenName, contact.familyName]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
              let org = contact.organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
              let display = full.isEmpty ? (org.isEmpty ? "Unnamed Contact" : org) : full
              let emails = contact.emailAddresses.map { $0.value as String }.filter { !$0.isEmpty }
              let phones = contact.phoneNumbers.map { $0.value.stringValue }.filter { !$0.isEmpty }

              let isMatch: Bool
              if query.isEmpty {
                isMatch = true
              } else {
                isMatch =
                  display.localizedCaseInsensitiveContains(query)
                  || org.localizedCaseInsensitiveContains(query)
                  || emails.contains(where: { $0.localizedCaseInsensitiveContains(query) })
                  || phones.contains(where: { $0.localizedCaseInsensitiveContains(query) })
              }
              if isMatch {
                matches.append(
                  ContactSnapshot(
                    id: contact.identifier,
                    fullName: display,
                    organization: org.isEmpty || org == display ? nil : org,
                    emails: emails,
                    phones: phones
                  )
                )
                if matches.count >= limit {
                  stop.pointee = true
                }
              }
            }

            if matches.isEmpty {
              return RuntimeToolResult(
                text: query.isEmpty ? "No contacts found." : "No contacts matched '\(query)'."
              )
            }
            let lines = matches.map { item -> String in
              var line = "- \(item.fullName)"
              if let org = item.organization { line += " (\(org))" }
              if !item.emails.isEmpty { line += " | Email: \(item.emails.joined(separator: ", "))" }
              if !item.phones.isEmpty { line += " | Phone: \(item.phones.joined(separator: ", "))" }
              return line
            }
            return RuntimeToolResult(
              text: "Found \(matches.count) contact(s):\n" + lines.joined(separator: "\n")
            )
          }
        }
      )
    }
  #endif

  // MARK: - Argument Helpers

  private static func stringArg(_ value: MemoshiProtocol.JSONValue?) -> String? {
    guard case .string(let s)? = value else { return nil }
    return s
  }

  private static func boolArg(_ value: MemoshiProtocol.JSONValue?) -> Bool? {
    guard case .bool(let b)? = value else { return nil }
    return b
  }

  private static func intArg(_ value: MemoshiProtocol.JSONValue?) -> Int? {
    switch value {
    case .integer(let i)?: return Int(i)
    case .double(let d)?: return Int(d)
    default: return nil
    }
  }

  private static func clampInt(_ value: Int, min lower: Int, max upper: Int) -> Int {
    Swift.max(lower, Swift.min(upper, value))
  }
}
