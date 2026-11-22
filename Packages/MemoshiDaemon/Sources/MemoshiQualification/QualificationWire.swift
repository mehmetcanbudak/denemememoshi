import Foundation
import MemoshiProtocol

/// Where the qualification tool may hold still so the driver can kill the host there.
package enum ToolGate: String, Codable, Sendable {
  /// After announcing execution, before posting the effect.
  case toolExecuting = "tool-executing"
  /// After the ledger accepted the effect, before returning the result to Pi.
  case effectPosted = "effect-posted"
}

/// The host's startup order after a restart.
package enum StartupOrder: String, Codable, Sendable {
  /// start → model discovery → resume: a resumed generation finds its local model.
  case discoverThenResume = "discover-then-resume"
  /// memoshid's current order: start → resume, discovery only when a client lists models.
  case daemon
}

/// The first stdin line the driver sends a host. Secrets travel only on this pipe, never in
/// arguments, environment or files other than the declared ledger-token source.
package struct HostConfiguration: Codable, Sendable {
  /// The qualification run.
  package var run: String
  /// This host process's life within the run, starting at 1.
  package var life: Int
  /// The isolated Memoshi data directory.
  package var dataDirectory: String
  /// The controlled provider's loopback base URL.
  package var providerBaseURL: String
  /// The opaque `kc_` reference configured for the local provider.
  package var providerSecretRef: String
  /// The provider bearer canary, released per use through the runtime's credential seam.
  package var providerBearer: String
  /// Whether this life configures the provider (only the first life does).
  package var configureProvider: Bool
  /// The effect ledger's loopback port.
  package var ledgerPort: Int
  /// The synthetic secret file holding the ledger bearer canary.
  package var ledgerTokenFile: String
  /// A gate where the tool holds still until killed or released.
  package var pause: ToolGate?
  /// Whether this life's runtime composition registers the subagent tools (subagent runs).
  package var subagents: Bool
  /// Whether this life's runtime composition registers the `codemode` tool (codemode-nested runs).
  package var codeMode: Bool
  /// Startup order.
  package var startup: StartupOrder

  package init(
    run: String, life: Int, dataDirectory: String, providerBaseURL: String,
    providerSecretRef: String, providerBearer: String, configureProvider: Bool,
    ledgerPort: Int, ledgerTokenFile: String, pause: ToolGate?, subagents: Bool = false,
    codeMode: Bool = false, startup: StartupOrder
  ) {
    self.subagents = subagents
    self.codeMode = codeMode
    self.run = run
    self.life = life
    self.dataDirectory = dataDirectory
    self.providerBaseURL = providerBaseURL
    self.providerSecretRef = providerSecretRef
    self.providerBearer = providerBearer
    self.configureProvider = configureProvider
    self.ledgerPort = ledgerPort
    self.ledgerTokenFile = ledgerTokenFile
    self.pause = pause
    self.startup = startup
  }
}

/// A driver command after the configuration line; the host answers with the same `id`.
package struct HostCommand: Codable, Sendable {
  /// Command kinds.
  package enum Operation: String, Codable, Sendable {
    /// `RuntimeAdapter.send` with the original parameters.
    case send
    /// `RuntimeAdapter.respondToCard`, the real approval path.
    case respond
    /// A read-only state snapshot.
    case inspect
    /// Releases a paused tool gate.
    case release
    /// Normal close: runtime, then store, then exit 0.
    case shutdown
  }

  /// Correlates the response.
  package var id: Int
  /// The command.
  package var op: Operation
  /// `send` parameters.
  package var send: ChatsSendParams?
  /// `respond` parameters.
  package var respond: CardsRespondParams?
  /// The run's original send key, for `inspect`.
  package var requestId: ULID?

  package init(
    id: Int, op: Operation, send: ChatsSendParams? = nil, respond: CardsRespondParams? = nil,
    requestId: ULID? = nil
  ) {
    self.id = id
    self.op = op
    self.send = send
    self.respond = respond
    self.requestId = requestId
  }
}

/// One host stdout line: a command response (`id`) or an event (`event`).
package struct HostMessage: Codable, Sendable {
  /// Set on responses.
  package var id: Int?
  /// Set on events, such as `ready` or `approval_requested`.
  package var event: String?
  /// Response success.
  package var ok: Bool?
  /// A presentation-safe failure description.
  package var error: String?
  /// Flat event or response fields.
  package var fields: [String: String]?
  /// The `send` receipt.
  package var receipt: ChatsSendResult?
  /// The `inspect` snapshot.
  package var snapshot: HostSnapshot?

  package init(
    id: Int? = nil, event: String? = nil, ok: Bool? = nil, error: String? = nil,
    fields: [String: String]? = nil, receipt: ChatsSendResult? = nil, snapshot: HostSnapshot? = nil
  ) {
    self.id = id
    self.event = event
    self.ok = ok
    self.error = error
    self.fields = fields
    self.receipt = receipt
    self.snapshot = snapshot
  }
}

/// The durable state the driver verifies, read through the real Store and RuntimeAdapter.
package struct HostSnapshot: Codable, Equatable, Sendable {
  /// The Assistant Chat.
  package var chatId: String
  /// The run's turn, by its original send key.
  package var turn: TurnState?
  /// The turn's application task.
  package var task: TaskState?
  /// Every approval in the Chat's conversation.
  package var approvals: [ApprovalState]
  /// Every card in the Chat's conversation.
  package var cards: [CardState]
  /// The committed transcript, oldest first.
  package var messages: [MessageState]
  /// Whether a live generation is visible.
  package var live: Bool
  /// Whether a whole-Chat recovery hold exists.
  package var recoveryHold: Bool
  /// Accepted but unsubmitted inputs.
  package var queued: Int
  /// Durable `tool.completed` facts for the qualification tool.
  package var toolCompletions: [ToolCompletionState]
  /// Durable `tool.completed` facts for the foreground `subagent` delegation tool.
  package var subagentCompletions: [ToolCompletionState]
  /// Durable `tool.completed` facts for the `codemode` tool.
  package var codeModeCompletions: [ToolCompletionState]
  /// Tasks whose parent is the run's turn task: the spawned children.
  package var childTasks: [ChildTaskState]
  /// Live runs in this process.
  package var liveRuns: Int

  package init(
    chatId: String, turn: TurnState?, task: TaskState?, approvals: [ApprovalState],
    cards: [CardState], messages: [MessageState], live: Bool, recoveryHold: Bool, queued: Int,
    toolCompletions: [ToolCompletionState], subagentCompletions: [ToolCompletionState],
    codeModeCompletions: [ToolCompletionState] = [], childTasks: [ChildTaskState], liveRuns: Int
  ) {
    self.chatId = chatId
    self.turn = turn
    self.task = task
    self.approvals = approvals
    self.cards = cards
    self.messages = messages
    self.live = live
    self.recoveryHold = recoveryHold
    self.queued = queued
    self.toolCompletions = toolCompletions
    self.subagentCompletions = subagentCompletions
    self.codeModeCompletions = codeModeCompletions
    self.childTasks = childTasks
    self.liveRuns = liveRuns
  }
}

/// A turn's content-free receipt fields.
package struct TurnState: Codable, Equatable, Sendable {
  /// The original send key.
  package var requestId: String
  /// The user message.
  package var messageId: String
  /// The reply identity.
  package var assistantMessageId: String
  /// The application task.
  package var taskId: String
  /// The turn status.
  package var status: String
  /// The original admission sequence.
  package var writtenSeq: Int64
  /// Whether an uncertain step holds the turn.
  package var recoveryHeld: Bool
  /// The sanitized failure code of a failed turn.
  package var errorCode: String?

  package init(
    requestId: String, messageId: String, assistantMessageId: String, taskId: String,
    status: String, writtenSeq: Int64, recoveryHeld: Bool, errorCode: String?
  ) {
    self.requestId = requestId
    self.messageId = messageId
    self.assistantMessageId = assistantMessageId
    self.taskId = taskId
    self.status = status
    self.writtenSeq = writtenSeq
    self.recoveryHeld = recoveryHeld
    self.errorCode = errorCode
  }
}

/// A task's status fields.
package struct TaskState: Codable, Equatable, Sendable {
  /// The status.
  package var status: String
  /// What a waiting task waits on.
  package var waitingOn: String?
  /// `auto` or `explicit`.
  package var resumeMode: String

  package init(status: String, waitingOn: String?, resumeMode: String) {
    self.status = status
    self.waitingOn = waitingOn
    self.resumeMode = resumeMode
  }
}

/// A spawned child task and the tool ceiling its subagent binding recorded.
package struct ChildTaskState: Codable, Equatable, Sendable {
  /// The child's application task.
  package var id: String
  /// The child task's status.
  package var status: String
  /// The inherited tools the child may call, or nil when no subagent binding names the task.
  package var toolNames: [String]?

  package init(id: String, status: String, toolNames: [String]?) {
    self.id = id
    self.status = status
    self.toolNames = toolNames
  }
}

/// An approval's identity and decision.
package struct ApprovalState: Codable, Equatable, Sendable {
  /// The approval.
  package var id: String
  /// Its status.
  package var status: String
  /// The task it gates.
  package var taskId: String
  /// The gated call.
  package var toolCallId: String
  /// The deciding actor kind, once decided.
  package var decidedBy: String?

  package init(id: String, status: String, taskId: String, toolCallId: String, decidedBy: String?) {
    self.id = id
    self.status = status
    self.taskId = taskId
    self.toolCallId = toolCallId
    self.decidedBy = decidedBy
  }
}

/// A card's identity and status.
package struct CardState: Codable, Equatable, Sendable {
  /// The card.
  package var id: String
  /// Its status.
  package var status: String
  /// The approval it presents.
  package var subjectId: String?

  package init(id: String, status: String, subjectId: String?) {
    self.id = id
    self.status = status
    self.subjectId = subjectId
  }
}

/// A committed transcript message. Text is synthetic qualification content.
package struct MessageState: Codable, Equatable, Sendable {
  /// The message.
  package var id: String
  /// `user` or `bot`.
  package var role: String
  /// The text content.
  package var text: String
  /// The original send key, for user messages.
  package var requestId: String?
  /// The settled stop reason, for bot messages.
  package var stopReason: String?

  package init(id: String, role: String, text: String, requestId: String?, stopReason: String?) {
    self.id = id
    self.role = role
    self.text = text
    self.requestId = requestId
    self.stopReason = stopReason
  }
}

/// One durable tool completion fact.
package struct ToolCompletionState: Codable, Equatable, Sendable {
  /// The completed call.
  package var toolCallId: String
  /// Whether it succeeded.
  package var ok: Bool
  /// The failure code, if any.
  package var errorCode: String?

  package init(toolCallId: String, ok: Bool, errorCode: String?) {
    self.toolCallId = toolCallId
    self.ok = ok
    self.errorCode = errorCode
  }
}
