import Foundation
import MemoshiProtocol

/// Decodes each batch member independently, so one invalid request does not discard its siblings.
struct RPCRequest: Decodable, Sendable {
  enum Operation: Sendable {
    case hello(SystemHelloParams)
    case ping
    case status
    case subscribe(EventsSubscribeParams)
    case focus(EventsFocusParams)
    case unsubscribe
    case bots(BotsListParams)
    case bot(BotsGetParams)
    case createBot(BotsCreateParams)
    case updateBot(BotsUpdateParams)
    case createSession(SessionsCreateParams)
    case deleteSession(SessionsDeleteParams)
    case trash
    case restoreSession(TrashRestoreParams)
    case emptyTrash(TrashEmptyParams)
    case grants(BotsGrantsListParams)
    case updateGrant(BotsGrantsUpdateParams)
    case revokeGrant(BotsGrantsRevokeParams)
    case task(TasksGetParams)
    case abortTask(TasksAbortParams)
    case taskGraph(TasksGraphParams)
    case taskHistory(TasksHistoryParams)
    case approvals(ApprovalsListParams)
    case cards(CardsListParams)
    case card(CardsGetParams)
    case respondToCard(CardsRespondParams)
    case chats
    case history(ChatsHistoryParams)
    case send(ChatsSendParams)
    case abort(ChatsAbortParams)
    case providers
    case configure(ModelsProvidersConfigureParams)
    case models
    case cancel(JSONRPCID)
    case unsupported
    case notification
    case invalidRequest
    case invalidParams
  }

  let id: JSONRPCID?
  let method: String?
  let operation: Operation

  private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

  init(from decoder: any Decoder) throws {
    guard let container = try? decoder.container(keyedBy: CodingKeys.self),
      (try? container.decode(String.self, forKey: .jsonrpc)) == "2.0",
      let method = try? container.decode(String.self, forKey: .method), method.isEmpty == false
    else {
      self.init(id: nil, method: nil, operation: .invalidRequest)
      return
    }
    guard container.contains(.id) else {
      if method == SystemCancelNotification.method,
        let cancel = try? SystemCancelNotification(from: decoder),
        cancel.id.rawValue.hasPrefix("c:")
      {
        self.init(id: nil, method: method, operation: .cancel(cancel.id))
      } else {
        self.init(id: nil, method: method, operation: .notification)
      }
      return
    }
    guard let id = try? container.decode(JSONRPCID.self, forKey: .id),
      id.rawValue.hasPrefix("c:")
    else {
      self.init(id: nil, method: method, operation: .invalidRequest)
      return
    }
    let operation: Operation
    do {
      switch method {
      case SystemHello.name:
        operation = .hello(try container.decode(SystemHelloParams.self, forKey: .params))
      case SystemPing.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .ping
      case SystemStatus.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .status
      case EventsSubscribe.name:
        operation = .subscribe(try container.decode(EventsSubscribeParams.self, forKey: .params))
      case EventsFocus.name:
        operation = .focus(try container.decode(EventsFocusParams.self, forKey: .params))
      case EventsUnsubscribe.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .unsubscribe
      case BotsList.name:
        operation = .bots(try container.decode(BotsListParams.self, forKey: .params))
      case BotsGet.name:
        operation = .bot(try container.decode(BotsGetParams.self, forKey: .params))
      case BotsCreate.name:
        operation = .createBot(try container.decode(BotsCreateParams.self, forKey: .params))
      case BotsUpdate.name:
        operation = .updateBot(try container.decode(BotsUpdateParams.self, forKey: .params))
      case SessionsCreate.name:
        operation = .createSession(
          try container.decode(SessionsCreateParams.self, forKey: .params))
      case SessionsDelete.name:
        operation = .deleteSession(try container.decode(SessionsDeleteParams.self, forKey: .params))
      case TrashList.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .trash
      case TrashRestore.name:
        operation = .restoreSession(try container.decode(TrashRestoreParams.self, forKey: .params))
      case TrashEmpty.name:
        operation = .emptyTrash(try container.decode(TrashEmptyParams.self, forKey: .params))
      case BotsGrantsList.name:
        operation = .grants(try container.decode(BotsGrantsListParams.self, forKey: .params))
      case BotsGrantsUpdate.name:
        operation = .updateGrant(
          try container.decode(BotsGrantsUpdateParams.self, forKey: .params))
      case BotsGrantsRevoke.name:
        operation = .revokeGrant(
          try container.decode(BotsGrantsRevokeParams.self, forKey: .params))
      case ChatsList.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .chats
      case ChatsHistory.name:
        operation = .history(try container.decode(ChatsHistoryParams.self, forKey: .params))
      case ChatsSend.name:
        operation = .send(try container.decode(ChatsSendParams.self, forKey: .params))
      case ChatsAbort.name:
        operation = .abort(try container.decode(ChatsAbortParams.self, forKey: .params))
      case ModelsProvidersList.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .providers
      case ModelsProvidersConfigure.name:
        operation = .configure(
          try container.decode(ModelsProvidersConfigureParams.self, forKey: .params))
      case ModelsList.name:
        _ = try container.decode(EmptyParams.self, forKey: .params)
        operation = .models
      case TasksGet.name:
        operation = .task(try container.decode(TasksGetParams.self, forKey: .params))
      case TasksAbort.name:
        operation = .abortTask(try container.decode(TasksAbortParams.self, forKey: .params))
      case TasksGraph.name:
        operation = .taskGraph(try container.decode(TasksGraphParams.self, forKey: .params))
      case TasksHistory.name:
        operation = .taskHistory(try container.decode(TasksHistoryParams.self, forKey: .params))
      case ApprovalsList.name:
        operation = .approvals(try container.decode(ApprovalsListParams.self, forKey: .params))
      case CardsList.name:
        operation = .cards(try container.decode(CardsListParams.self, forKey: .params))
      case CardsGet.name:
        operation = .card(try container.decode(CardsGetParams.self, forKey: .params))
      case CardsRespond.name:
        operation = .respondToCard(try container.decode(CardsRespondParams.self, forKey: .params))
      default:
        operation = .unsupported
      }
    } catch {
      self.init(id: id, method: method, operation: .invalidParams)
      return
    }
    self.init(id: id, method: method, operation: operation)
  }

  private init(id: JSONRPCID?, method: String?, operation: Operation) {
    self.id = id
    self.method = method
    self.operation = operation
  }
}

struct RPCFrame: Decodable, Sendable {
  enum FrameError: Error { case invalidBatch }
  let requests: [RPCRequest]
  let isBatch: Bool

  init(from decoder: any Decoder) throws {
    if var array = try? decoder.unkeyedContainer() {
      guard array.count != 0, (array.count ?? 0) <= 32 else { throw FrameError.invalidBatch }
      var requests: [RPCRequest] = []
      while array.isAtEnd == false {
        guard requests.count < 32 else { throw FrameError.invalidBatch }
        requests.append(try array.decode(RPCRequest.self))
      }
      self.requests = requests
      self.isBatch = true
    } else {
      self.requests = [try RPCRequest(from: decoder)]
      self.isBatch = false
    }
  }
}
