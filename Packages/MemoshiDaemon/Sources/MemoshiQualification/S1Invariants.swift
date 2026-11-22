import Foundation
import MemoshiProtocol

/// Original, unmodified send parameters and the actual first admission receipt.
package struct S1SubmittedTurn: Codable, Sendable {
  package var token: String
  package var params: ChatsSendParams
  package var receipt: ChatsSendResult
}

package enum S1Invariants {
  package static func replay(_ original: ChatsSendResult, _ replay: ChatsSendResult) throws {
    guard replay.replayed == true, replay.messageId == original.messageId,
      replay.taskId == original.taskId, replay.writtenSeq == original.writtenSeq,
      replay.sideThreadId == original.sideThreadId
    else {
      throw DriverError.invalid("S1 replay changed the original receipt or omitted replayed=true")
    }
  }

  package static func settled(_ turns: [TurnState], originals: [S1SubmittedTurn]) throws {
    guard turns.count == originals.count,
      Set(turns.map(\.requestId)).count == originals.count,
      Set(turns.map(\.assistantMessageId)).count == originals.count
    else { throw DriverError.invalid("S1 turn identity set is not one-to-one") }
    let byRequest = Dictionary(uniqueKeysWithValues: turns.map { ($0.requestId, $0) })
    for original in originals {
      guard let turn = byRequest[original.params.requestId.rawValue], turn.status == "done",
        !turn.recoveryHeld, turn.errorCode == nil,
        turn.messageId == original.receipt.messageId.rawValue,
        turn.taskId == original.receipt.taskId.rawValue,
        turn.writtenSeq == original.receipt.writtenSeq
      else {
        throw DriverError.invalid("S1 turn did not settle under its original durable identity")
      }
    }
  }

  package static func history(
    _ history: ChatsHistoryResult, conversation: ConversationID,
    originals: [S1SubmittedTurn], turns: [TurnState]
  ) throws {
    guard history.live == nil, history.recovery == nil, history.queued?.isEmpty != false,
      history.nextBefore == nil, history.items.count == originals.count * 2,
      history.items.allSatisfy({ $0.conversationId == conversation }),
      Set(history.items.map(\.id)).count == history.items.count,
      Set(turns.map(\.requestId)).count == turns.count
    else {
      throw DriverError.invalid(
        "S1 history has extra, missing, cross-conversation or unsettled messages")
    }
    let byRequest = Dictionary(uniqueKeysWithValues: turns.map { ($0.requestId, $0) })
    for original in originals {
      guard original.params.chatId == conversation,
        let turn = byRequest[original.params.requestId.rawValue]
      else { throw DriverError.invalid("S1 history proof lacks its original turn") }
      let user = history.items.filter { $0.role == .user && $0.taskId == original.receipt.taskId }
      let answer = history.items.filter { $0.role == .bot && $0.taskId == original.receipt.taskId }
      guard user.count == 1, answer.count == 1,
        user[0].id == original.receipt.messageId,
        user[0].requestId == original.params.requestId,
        user[0].content == original.params.content,
        answer[0].id.rawValue == turn.assistantMessageId,
        answer[0].stopReason == .stop,
        text(answer[0]) == S1Provider.finalText(original.token)
      else {
        throw DriverError.invalid(
          "S1 history is not exactly one original user and one settled answer per turn")
      }
    }
  }

  package static func text(_ message: ChatMessage) -> String {
    message.content.compactMap {
      if case .text(let part) = $0 { part.text } else { nil }
    }.joined()
  }
}
