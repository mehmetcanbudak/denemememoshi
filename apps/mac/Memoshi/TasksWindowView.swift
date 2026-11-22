import DesignSystem
import MemoshiProtocol
import SwiftUI

/// Real per-conversation task graphs, with read-only child attachment and task-targeted Stop.
struct TasksWindowView: View {
  let model: LiveChatModel
  @State private var selectedTaskID: TaskID?

  var body: some View {
    content
      .frame(
        minWidth: DS.Layout.Conversation.minWidth, maxWidth: .infinity,
        minHeight: DS.Layout.Inspector.min, maxHeight: .infinity
      )
      .background(DS.Colors.Surface.window)
      .toolbar {
        ToolbarItem {
          Button("Refresh", systemImage: "arrow.clockwise") {
            model.loadTasks()
            model.taskInspector.refresh()
          }
          .help("Read the conversation graphs and attached child's history again.")
          .disabled(model.connection != .connected || model.isLoadingTasks)
          .accessibilityIdentifier("tasks.refresh")
        }
      }
      .onAppear { model.showTasks() }
      .onDisappear { model.hideTasks() }
      .onChange(of: Sources(model: model)) { model.loadTasks() }
      .onChange(of: selectedTask, initial: true) { _, task in model.inspectTask(task) }
  }

  private var selectedTask: MemoshiTask? {
    selectedTaskID.flatMap { model.knownTasks[$0] }
  }

  @ViewBuilder
  private var content: some View {
    let roots = TaskNode.forest(Array(model.knownTasks.values))
    if roots.isEmpty {
      if model.isLoadingTasks {
        ProgressView("Loading tasks…")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView {
          Label("No Tasks", systemImage: "checklist")
        } description: {
          if let problem = model.taskListProblem {
            Text(verbatim: problem)
          } else if model.connection != .connected {
            Text("Connect to the local daemon to read task snapshots.")
          } else {
            Text(
              "Tasks appear after a real conversation starts work. The graph includes its durable foreground and background children."
            )
          }
        }
        .accessibilityIdentifier("tasks.empty")
      }
    } else {
      VStack(spacing: DS.Space.s0) {
        HSplitView {
          List(roots, children: \.children, selection: $selectedTaskID) { node in
            TaskRow(task: node.task, chat: chatTitle(for: node.task)).tag(node.task.id)
          }
          .frame(minWidth: DS.Layout.Sidebar.min, idealWidth: DS.Layout.Sidebar.default)
          .accessibilityLabel("Tasks")
          .accessibilityIdentifier("tasks.list")
          TaskAttachmentView(inspector: model.taskInspector)
        }
        if let problem = model.taskListProblem {
          Text(verbatim: problem)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.s4)
            .accessibilityIdentifier("tasks.problem")
        }
      }
    }
  }

  private func chatTitle(for task: MemoshiTask) -> String {
    if let chat = model.directory.conversations.first(where: { $0.id == task.conversationId }) {
      return chat.title
    }
    return task.conversationId.rawValue
  }

  /// Re-reads snapshots when the applied chat state names other tasks or is bootstrapped again.
  private struct Sources: Hashable {
    let ids: [TaskID]
    let generation: Int
    let directoryGeneration: Int
    let isConnected: Bool

    @MainActor
    init(model: LiveChatModel) {
      ids = model.referencedTaskIDs
      generation = model.taskListGeneration
      directoryGeneration = model.directory.generation
      isConnected = model.connection == .connected
    }
  }
}

/// Parent/child nesting, newest first, from whatever snapshots name a parent.
private struct TaskNode: Identifiable {
  let task: MemoshiTask
  let children: [TaskNode]?
  var id: TaskID { task.id }

  static func forest(_ tasks: [MemoshiTask]) -> [TaskNode] {
    let present = Set(tasks.map(\.id))
    var childrenByParent: [TaskID: [MemoshiTask]] = [:]
    var roots: [MemoshiTask] = []
    for task in tasks {
      if let parent = task.parentTaskId, present.contains(parent), parent != task.id {
        childrenByParent[parent, default: []].append(task)
      } else {
        roots.append(task)
      }
    }
    func node(_ task: MemoshiTask) -> TaskNode {
      let children = (childrenByParent[task.id] ?? []).sorted(by: newestFirst).map(node)
      return TaskNode(task: task, children: children.isEmpty ? nil : children)
    }
    return roots.sorted(by: newestFirst).map(node)
  }

  private static func newestFirst(_ lhs: MemoshiTask, _ rhs: MemoshiTask) -> Bool {
    (lhs.createdAt, lhs.id.rawValue) > (rhs.createdAt, rhs.id.rawValue)
  }
}

private struct TaskRow: View {
  let task: MemoshiTask
  let chat: String

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: DS.Space.s4) {
      Image(systemName: symbol)
        .foregroundStyle(tint)
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: DS.Space.s1) {
        Text(verbatim: task.title.rawValue)
          .lineLimit(2)
        Text(verbatim: [task.statusLabel, kind, chat].joined(separator: " · "))
          .font(DS.Typography.callout)
          .foregroundStyle(DS.Colors.Text.secondary)
        Text(verbatim: times)
          .font(DS.Typography.callout.monospacedDigit())
          .foregroundStyle(DS.Colors.Text.tertiary)
        if let detail {
          Text(verbatim: detail)
            .font(DS.Typography.callout)
            .foregroundStyle(DS.Colors.Text.secondary)
            .lineLimit(2)
        }
      }
    }
    .padding(.vertical, DS.Space.s2)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("tasks.row.\(task.id.rawValue)")
  }

  private var kind: String {
    switch task.kind {
    case .turn: String(localized: "Turn")
    case .run: String(localized: "Run")
    case .subagent: String(localized: "Subagent")
    case .handoff: String(localized: "Handoff")
    case .app: String(localized: "App call")
    case .groupTurn: String(localized: "Group turn")
    case .unknown(let raw): raw
    }
  }

  private var times: String {
    var parts = [String(localized: "Created \(Self.time(task.createdAt))")]
    if let started = task.startedAt {
      parts.append(String(localized: "started \(Self.time(started))"))
    }
    if let ended = task.endedAt {
      parts.append(String(localized: "ended \(Self.time(ended))"))
      if let started = task.startedAt, ended >= started {
        let elapsed = Duration.milliseconds(ended - started)
        parts.append(elapsed.formatted(.units(allowed: [.seconds, .milliseconds])))
      }
    }
    return parts.joined(separator: " · ")
  }

  private var detail: String? {
    task.error?.message ?? task.summary?.rawValue
  }

  private var symbol: String {
    switch task.status {
    case .queued: "clock"
    case .running: "play.circle"
    case .waiting: "hand.raised"
    case .done: "checkmark.circle"
    case .failed: "exclamationmark.triangle"
    case .canceled: "stop.circle"
    case .unknown: "questionmark.circle"
    }
  }

  private var tint: AdaptiveColor {
    switch task.status {
    case .running, .queued: DS.Colors.Status.Running.fg
    case .waiting: DS.Colors.Status.Attention.fg
    case .done: DS.Colors.Status.Success.fg
    case .failed: DS.Colors.Status.Danger.fg
    case .canceled, .unknown: DS.Colors.Status.Neutral.fg
    }
  }

  private static func time(_ milliseconds: Int64) -> String {
    Date(timeIntervalSince1970: Double(milliseconds) / 1_000)
      .formatted(date: .omitted, time: .standard)
  }
}

extension MemoshiTask {
  /// The task's status for a reader, with what a waiting task waits for; unknown wire values
  /// stay raw.
  var statusLabel: String {
    let base: String =
      switch status {
      case .queued: String(localized: "Queued")
      case .running: String(localized: "Running")
      case .waiting: String(localized: "Waiting")
      case .done: String(localized: "Done")
      case .failed: String(localized: "Failed")
      case .canceled: String(localized: "Canceled")
      case .unknown(let raw): raw
      }
    if status == .waiting, let waitingOn {
      return String(localized: "\(base) for \(String(localized: waitingOn.label))")
    }
    return base
  }
}

extension WaitingOn {
  /// The reader-facing name of what a waiting task waits for; unknown wire values stay raw.
  fileprivate var label: LocalizedStringResource {
    switch self {
    case .approval: "approval"
    case .user: "your answer"
    case .childTasks: "subtasks"
    case .takeover: "takeover"
    case .computer: "a computer"
    case .device: "a device"
    case .budget: "budget"
    case .authority: "authority confirmation"
    case .outcomeCheck: "an outcome check"
    case .resume: "resume"
    case .unknown(let raw): "unrecognized (\(raw))"
    }
  }
}
