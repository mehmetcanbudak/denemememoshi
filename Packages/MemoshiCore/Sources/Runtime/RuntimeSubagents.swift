import Chord
import Foundation
import MemoshiProtocol
import MemoshiStore
import PiAI
import PiCore
import PiDurable

/// The SDK's §7.3 pattern, not an app Session or a second Harness. Spawn identity is committed
/// with ownership and configuration; a replay finds that same child before submitting again.
struct RuntimeSubagents: Sendable {
  static let name: PiCore.JSONString = "memoshi.subagents"
  static let foregroundName = "subagent"
  static let backgroundName = "subagent_background"
  static let anchorName: PiCore.JSONString = "memoshi.subagent.anchor"
  static let identityKind: PiCore.JSONString = "memoshi.subagent.identity"
  static let names: Set<String> = [foregroundName, backgroundName]
  static let parameters: MemoshiProtocol.JSONValue = [
    "type": "object",
    "properties": ["task": ["type": "string", "minLength": 1, "maxLength": 32_768]],
    "required": ["task"], "additionalProperties": false,
  ]

  let configuration: RuntimeSubagentConfiguration
  let store: Store
  let chat: ChatSummary
  let fence: ConversationFence

  struct Arguments: Codable, Sendable { let task: String }
  struct BackgroundInput: Codable, Sendable {
    let taskId: MemoshiProtocol.TaskID
    let originalTaskId: MemoshiProtocol.TaskID
    let sourceToolTaskId: Int
    let task: String
  }

  func tools() -> [RuntimeExtensionTool] { Self.tools(configuration) }

  static func tools(_ configuration: RuntimeSubagentConfiguration) -> [RuntimeExtensionTool] {
    let enabled =
      (configuration.foreground ? [Self.foregroundName] : [])
      + (configuration.persistentBackground ? [Self.backgroundName] : [])
    return enabled.map { name in
      RuntimeExtensionTool(
        name: name, source: .subagent, parameters: Self.parameters,
        deferred: false,
        policy: RuntimeExtensionToolPolicy(
          operation: .selfState,
          replaySafe: true, outputExposure: Exposure(untrusted: false, privateData: false),
          authorize: { _ in true }), prepare: nil)
    }
  }

  func definition() throws -> PiDurable.Extension {
    let backgroundTask = anchor()
    let registrations = try tools().map { entry in
      PiDurable.ToolRegistration(
        name: PiCore.JSONString(entry.name),
        description: PiCore.JSONString(
          entry.name == Self.foregroundName
            ? "Delegate a self-contained task to a foreground child and wait for its answer."
            : "Start a persistent background child. Returns its task ID; parent Stop does not stop it."
        ),
        parameters: try ToolJSON.sdk(Self.parameters), replay: .safe, callers: [.model],
        execute: { arguments, api, context in
          // A child cannot re-enable delegation through Code Mode, tool search or model args.
          guard api.conversationId == .root else { throw RuntimeToolError.notAuthorized }
          let input = try arguments.decode(Arguments.self)
          guard !input.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            input.task.count <= 32_768
          else { throw RuntimeToolError.invalidArguments }
          let background = entry.name == Self.backgroundName
          let taskID = try await RuntimeTaskScope.taskID(
            api, store: store, chat: chat, fence: fence,
            context: context)
          let parent = try await api.agent(context: context)
          guard parent.model != nil else { throw RuntimeToolError.unavailable }
          let candidate = try IDGenerator.shared.objectID(MemoshiProtocol.TaskIDKind.self)
          let createdAt = IDGenerator.nowMilliseconds()
          let source = api.taskId
          let binding = try await api.commit(
            { tx -> RuntimeSubagentBinding in
              var owner = source
              if background {
                var cursor: PiDurable.Cursor?
                var existing: PiDurable.TaskId?
                repeat {
                  let page = try await tx.scanTasks(
                    .init(conversationId: .root, kind: Self.anchorName),
                    limit: 128, cursor: cursor)
                  existing =
                    page.items.first(where: {
                      $0.input?["sourceToolTaskId"]?.numberValue == Double(source.rawValue)
                    })?.id
                  cursor = page.next
                } while existing == nil && cursor != nil
                if let existing { owner = existing }
              }
              if let child = try await tx.scanConversations(.init(ownerTaskId: owner), limit: 1)
                .items.first
              {
                guard
                  let identity = try await tx.scanEntries(
                    .init(conversationId: child.id, order: .ascending),
                    limit: 1
                  ).items.first, identity.kind == Self.identityKind, let data = identity.data
                else { throw RuntimeError.projectionFailed }
                return try data.decode(RuntimeSubagentBinding.self)
              }
              if background && owner == source {
                owner = try await tx.createTask(
                  backgroundTask,
                  input: try PiCore.JSONValue(
                    encoding:
                      BackgroundInput(
                        taskId: candidate, originalTaskId: taskID,
                        sourceToolTaskId: source.rawValue, task: input.task)),
                  options: .init(ownership: .conversation, conversationId: .root, background: true))
              }
              let child = try await tx.createConversation(ownership: .task(owner))
              if background {
                guard var anchor = tx.stagedTasks().first(where: { $0.id == owner }) else {
                  throw RuntimeError.projectionFailed
                }
                anchor.lifecycle = .pending(
                  checkpoint: ["phase": "run", "conversationId": child.id.json],
                  memos: anchor.memos)
                try tx.setTask(anchor)
              }
              var seen = Set<PiCore.JSONString>()
              let inherited = (parent.callable + parent.tools + parent.deferred).compactMap {
                tool -> PiCore.JSONString? in
                let name = tool.name
                guard seen.insert(name).inserted, !Self.names.contains(name.displayString),
                  configuration.childTools?.contains(name.displayString) ?? true
                else { return nil }
                return name
              }
              let visible = parent.tools.map(\.name).filter { inherited.contains($0) }
              let instructions =
                (parent.instructions ?? "")
                + "\nYou are a child of the owning Memoshi conversation. Complete only the supplied task. You cannot delegate or change your capabilities."
              try await PiDurable.configure(
                tx, conversationId: child.id,
                change: .init(
                  model: parent.model.map { .set($0) }, thinkingLevel: .set(parent.thinkingLevel),
                  extensions: .set(
                    .names(parent.extensions.map(\.name).filter { $0 != Self.name })),
                  tools: .set(.names(inherited)), modelTools: .set(.names(visible)),
                  instructions: .set(instructions), cwd: parent.cwd.map { .set($0) } ?? .clear))
              let binding = RuntimeSubagentBinding(
                taskId: candidate, conversationId: chat.id,
                originalTaskId: taskID, piOwnerTaskId: owner.rawValue,
                piConversationId: child.id.rawValue,
                sourceToolTaskId: source.rawValue, background: background,
                requestId: "subagent:\(owner.rawValue)", createdAt: createdAt,
                toolNames: inherited.map(\.displayString).sorted())
              _ = try await tx.appendEntry(
                child.id,
                .init(
                  kind: Self.identityKind,
                  data: try PiCore.JSONValue(encoding: binding)))
              return binding
            }, context: context)
          _ = try await store.ensureRuntimeSubagent(
            binding, fence: fence, at: IDGenerator.nowMilliseconds())
          try await api.details(
            [
              "conversationId": .number(Double(binding.piConversationId)),
              "taskId": .string(binding.taskId.rawValue),
            ], context: context)
          if background {
            return .init(output: [
              .text(
                .init(
                  text: PiCore.JSONString(
                    "Background child started: " + binding.taskId.rawValue)))
            ])
          }
          guard
            let child = try await api.conversation(
              ConversationId(binding.piConversationId), context: context)
          else { throw RuntimeError.projectionFailed }
          let submission = try await child.submit(
            .init(
              content: .text(PiCore.JSONString(input.task)),
              requestId: PiCore.JSONString(binding.requestId)), context: context)
          let settled = try await submission.wait(context: context)
          guard settled.status == .done, let answer = settled.answer,
            let entry = try await api.getEntry(answer, context: context),
            entry.conversationId == ConversationId(binding.piConversationId),
            let message = entry.model?.first?.assistantMessage,
            message.stopReason != .aborted, message.stopReason != .error
          else {
            return .init(output: [.text(.init(text: "The child did not complete."))], isError: true)
          }
          return .init(output: [.text(.init(text: PiCore.JSONString(RuntimeAdapter.text(message))))]
          )
        })
    }
    return PiDurable.Extension(name: Self.name, tools: registrations, tasks: [backgroundTask])
  }

  /// A conversation-owned background anchor owns the child. Its run/report checkpoints and
  /// request key survive parent cancellation and process restart; report holds entry references,
  /// not a duplicated transcript. Aborting this anchor cascades only into its own child.
  private func anchor() -> PiDurable.AnyTaskDefinition {
    PiDurable.AnyTaskDefinition(
      name: Self.anchorName, version: 1,
      initial: { _ in ["phase": "run"] },
      phases: [
        "run": { task, runtime, context in
          guard let value = task.state.checkpoint?["conversationId"],
            let input = try task.input?.decode(BackgroundInput.self),
            let child = try await runtime.conversation(
              ConversationId(try value.decode(Int.self)), context: context)
          else { throw RuntimeError.projectionFailed }
          let submission = try await child.submit(
            .init(
              content: .text(PiCore.JSONString(input.task)),
              requestId: PiCore.JSONString("subagent:\(task.id.rawValue)")), context: context)
          let settled = try await submission.wait(context: context)
          try await runtime.commit(
            { _ in
              .running(checkpoint: [
                "phase": "report",
                "submissionId": .number(Double(settled.id.rawValue)),
              ])
            }, context: context)
        },
        "report": { task, runtime, context in
          guard let value = task.state.checkpoint?["submissionId"],
            let submission = try await runtime.getSubmission(
              SubmissionId(try value.decode(Int.self)), context: context),
            submission.isSettled
          else { throw RuntimeError.projectionFailed }
          var succeeded = false
          if let answer = submission.answer,
            let entry = try await runtime.getEntry(answer, context: context),
            let message = entry.model?.first?.assistantMessage
          {
            succeeded = message.stopReason != .aborted && message.stopReason != .error
          }
          let success = succeeded && submission.status == .done
          let report: PiCore.JSONValue = [
            "conversationId": .number(Double(submission.conversationId.rawValue)),
            "submissionId": .number(Double(submission.id.rawValue)),
            "answer": submission.answer.map { .number(Double($0.rawValue)) } ?? .null,
          ]
          try await runtime.commit(
            { tx in
              _ = try await tx.appendEntry(
                .root, .init(kind: "memoshi.subagent.report", data: report))
              return .terminal(
                outcome: success
                  ? .completed(result: report)
                  : .failed(error: .init(message: "The child did not complete."), result: report))
            }, context: context)
        },
      ],
      abort: { _, runtime, context in
        try await runtime.commit(
          { _ in .terminal(outcome: .aborted(reason: "user")) }, context: context)
      })
  }
}
