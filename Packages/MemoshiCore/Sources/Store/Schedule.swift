import Foundation

/// Cadences supported by the pure next-occurrence calculator.
public enum RoutineSchedule: String, CaseIterable, Sendable {
  case manual, hourly, daily, weekdays, cron
}

/// Pure next-occurrence/label utilities, not a routine runner or Phase 1 scheduler.
/// Re-expressed from Draft 3 sidecar/src/routines/{schedule,cron}.ts at
/// ce39f8a7ca324ce1c2473518593b1fb4f96ebe4b; no TypeScript runtime is imported.
public enum Schedule {
  /// Finds the next fire time without starting a task, timer or routine.
  public static func nextRun(
    _ schedule: RoutineSchedule, timeOfDay: String? = nil,
    from milliseconds: Int64 = IDGenerator.nowMilliseconds(),
    cronExpression: String? = nil, timeZone: String? = nil
  ) -> Int64? {
    if schedule == .manual { return nil }
    if schedule == .hourly {
      let (next, overflow) = milliseconds.addingReportingOverflow(3_600_000)
      return overflow ? nil : next
    }
    if schedule == .cron {
      guard let cronExpression, let fields = CronFields(cronExpression) else { return nil }
      return fields.next(after: milliseconds, zone: TimeZone(identifier: timeZone ?? "UTC") ?? .gmt)
    }
    let components = (timeOfDay ?? "").split(separator: ":", omittingEmptySubsequences: false)
    let valid =
      components.count == 2 && components.allSatisfy { $0.count == 2 && $0.allSatisfy(\.isNumber) }
    let hour = valid ? Int(components[0]) : nil
    let minute = valid ? Int(components[1]) : nil
    let validTime = (0...23).contains(hour ?? -1) && (0...59).contains(minute ?? -1)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
    let matching = DateComponents(
      hour: validTime ? hour : 9, minute: validTime ? minute : 0, second: 0)
    var cursor = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    for _ in 0..<8 {
      guard
        let next = calendar.nextDate(
          after: cursor, matching: matching, matchingPolicy: .nextTime, repeatedTimePolicy: .first)
      else { return nil }
      let weekday = calendar.component(.weekday, from: next)
      if schedule != .weekdays || (2...6).contains(weekday) {
        return epochMilliseconds(next)
      }
      cursor = next
    }
    return nil
  }

  /// Describes a cadence for display without changing its execution state.
  public static func label(
    _ schedule: RoutineSchedule, timeOfDay: String? = nil,
    cronExpression: String? = nil, timeZone: String? = nil
  ) -> String {
    switch schedule {
    case .manual: "Manual"
    case .hourly: "Every hour"
    case .daily: "Daily at \(timeOfDay ?? "09:00")"
    case .weekdays: "Weekdays at \(timeOfDay ?? "09:00")"
    case .cron:
      if let cronExpression, cronExpression.isEmpty == false {
        "\(cronExpression) (\(timeZone ?? "UTC"))"
      } else {
        "Cron, not set up"
      }
    }
  }

  fileprivate static func epochMilliseconds(_ date: Date) -> Int64? {
    let value = date.timeIntervalSince1970 * 1_000
    guard value.isFinite, value >= Double(Int64.min), value < Double(Int64.max) else { return nil }
    return Int64(value.rounded())
  }
}

private struct CronFields {
  let minutes: UInt64
  let hours: UInt64
  let days: UInt64
  let months: UInt64
  let weekdays: UInt64
  let daysRestricted: Bool
  let weekdaysRestricted: Bool

  init?(_ expression: String) {
    let fields = expression.lowercased().split(whereSeparator: \.isWhitespace)
    guard fields.count == 5,
      let minutes = Self.parse(fields[0], range: 0...59),
      let hours = Self.parse(fields[1], range: 0...23),
      let days = Self.parse(fields[2], range: 1...31),
      let months = Self.parse(fields[3], range: 1...12, names: Self.monthNames),
      let weekdays = Self.parse(fields[4], range: 0...6, names: Self.dayNames)
    else { return nil }
    self.minutes = minutes
    self.hours = hours
    self.days = days
    self.months = months
    self.weekdays = weekdays
    self.daysRestricted = fields[2] != "*"
    self.weekdaysRestricted = fields[4] != "*"
  }

  func next(after milliseconds: Int64, zone: TimeZone) -> Int64? {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let from = Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
    var day = calendar.startOfDay(for: from)
    // A five-field calendar cron has no year constraint. Even February 29 across a century
    // omission recurs within eight years; impossible dates terminate rather than loop forever.
    let selectedHours = (0...23).filter { Self.contains(hours, $0) }
    let selectedMinutes = (0...59).filter { Self.contains(minutes, $0) }
    let firstDay = day
    let start = calendar.dateComponents([.hour, .minute], from: from)
    for _ in 0...(8 * 366) {
      let wall = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
      if let month = wall.month, let date = wall.day, let weekday = wall.weekday,
        Self.contains(months, month), matchesDay(date, weekday: weekday - 1)
      {
        for hour in selectedHours {
          for minute in selectedMinutes {
            if day == firstDay, let startHour = start.hour, let startMinute = start.minute,
              hour < startHour || (hour == startHour && minute <= startMinute)
            {
              continue
            }
            var candidate = wall
            candidate.weekday = nil
            candidate.hour = hour
            candidate.minute = minute
            candidate.second = 0
            guard let instant = calendar.date(from: candidate), instant > from else { continue }
            let actual = calendar.dateComponents([.hour, .minute, .day], from: instant)
            // A nonexistent wall-clock cron time is skipped, never silently shifted by DST.
            guard actual.hour == hour, actual.minute == minute, actual.day == date else { continue }
            return Schedule.epochMilliseconds(instant)
          }
        }
      }
      guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
      day = next
    }
    return nil
  }

  private func matchesDay(_ day: Int, weekday: Int) -> Bool {
    let dateMatches = Self.contains(days, day)
    let weekdayMatches = Self.contains(weekdays, weekday)
    if daysRestricted && weekdaysRestricted { return dateMatches || weekdayMatches }
    if daysRestricted { return dateMatches }
    if weekdaysRestricted { return weekdayMatches }
    return true
  }

  private static let monthNames = Dictionary(
    uniqueKeysWithValues: [
      "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec",
    ].enumerated().map { ($1, $0 + 1) })
  private static let dayNames = Dictionary(
    uniqueKeysWithValues: ["sun", "mon", "tue", "wed", "thu", "fri", "sat"].enumerated().map {
      ($1, $0)
    })

  private static func contains(_ mask: UInt64, _ value: Int) -> Bool {
    mask & (UInt64(1) << value) != 0
  }

  private static func parse(
    _ field: Substring, range: ClosedRange<Int>, names: [String: Int] = [:]
  ) -> UInt64? {
    var mask: UInt64 = 0
    for item in field.split(separator: ",", omittingEmptySubsequences: false) {
      let pieces = item.split(separator: "/", omittingEmptySubsequences: false)
      guard (1...2).contains(pieces.count) else { return nil }
      let step = pieces.count == 2 ? decimal(pieces[1]) : 1
      guard let step, step > 0 else { return nil }
      let base = pieces[0]
      let bounds = base.split(separator: "-", omittingEmptySubsequences: false)
      let start: Int
      let end: Int
      if base == "*" {
        start = range.lowerBound
        end = range.upperBound
      } else if bounds.count == 2 {
        guard let first = named(bounds[0], names: names), let last = named(bounds[1], names: names)
        else { return nil }
        start = first
        end = last
      } else if bounds.count == 1, let value = named(base, names: names) {
        start = value
        end = step > 1 ? range.upperBound : value
      } else {
        return nil
      }
      guard range.contains(start), range.contains(end), start <= end else { return nil }
      var value = start
      while value <= end {
        mask |= UInt64(1) << value
        if step > end - value { break }
        value += step
      }
    }
    return mask == 0 ? nil : mask
  }

  private static func named(_ value: Substring, names: [String: Int]) -> Int? {
    names[String(value)] ?? decimal(value)
  }

  private static func decimal(_ value: Substring) -> Int? {
    guard value.isEmpty == false, value.utf8.allSatisfy({ (48...57).contains($0) }) else {
      return nil
    }
    return Int(value)
  }
}
