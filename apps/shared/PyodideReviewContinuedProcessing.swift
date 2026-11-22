#if os(iOS)
  import BackgroundTasks
  import Foundation

  /// Only a framework launch callback grants continued processing. Request submission, a
  /// foreground scene and an elapsed timer are deliberately not treated as such a grant.
  @MainActor
  final class PyodideReviewContinuedProcessing {
    enum Event {
      case requested(String)
      case submitted
      case granted
      case refused(Int)
      case configurationMissing
      case registrationRefused
      case launchNotObserved
      case expired
      case cancelled
      case completed(Bool)
    }

    private var identifier: String?
    private var running: BGContinuedProcessingTask?
    private var launchDeadline: Task<Void, Never>?
    private var handler: (@MainActor (Event) -> Void)?

    func request(handler: @escaping @MainActor (Event) -> Void) {
      guard identifier == nil else { return }
      guard let bundleID = Bundle.main.bundleIdentifier,
        let permitted = Bundle.main.object(
          forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
          as? [String], permitted.contains(bundleID + ".python.*")
      else {
        handler(.configurationMissing)
        return
      }
      let identifier = bundleID + ".python.review." + UUID().uuidString.lowercased()
      self.identifier = identifier
      self.handler = handler
      let registered = BGTaskScheduler.shared.register(
        forTaskWithIdentifier: identifier, using: .main
      ) { [weak self] task in
        MainActor.assumeIsolated {
          guard let self else {
            task.setTaskCompleted(success: false)
            return
          }
          self.launched(task, identifier: identifier)
        }
      }
      guard registered else {
        self.identifier = nil
        self.handler = nil
        handler(.registrationRefused)
        return
      }
      handler(.requested(identifier))
      // SDK 27 explicitly prohibits submission on the main thread. Each identifier is unique;
      // registration is never repeated, and this adapter cancels only its own request.
      Task.detached { [weak self] in
        guard await self?.isCurrent(identifier) == true else { return }
        let request = BGContinuedProcessingTaskRequest(
          identifier: identifier, title: String(localized: "Python S6 review"),
          subtitle: String(localized: "Waiting for the system to start the measurement"))
        request.strategy = .fail
        do {
          try await BGTaskScheduler.shared.submitTaskRequest(request)
          await self?.submitted(identifier)
        } catch {
          await self?.refused(identifier, code: (error as NSError).code)
        }
      }
      launchDeadline = Task { [weak self] in
        do { try await Task.sleep(for: .seconds(20)) } catch { return }
        guard let self, self.identifier == identifier, self.running == nil else { return }
        self.endPending(.launchNotObserved)
      }
    }

    func cellStarted() {
      // Observed bridge execution, not an invented percentage of a CPU-bound pandas loop.
      running?.progress.completedUnitCount = 1
      running?.updateTitle(
        String(localized: "Python S6 review"), subtitle: String(localized: "Pandas cell started"))
    }

    func cellReturned() {
      running?.progress.completedUnitCount = 2
      running?.updateTitle(
        String(localized: "Python S6 review"),
        subtitle: String(localized: "Saving actual observations"))
    }

    func finish(success: Bool) {
      guard let task = running else {
        if identifier != nil { endPending(.cancelled) }
        return
      }
      running = nil
      identifier = nil
      launchDeadline?.cancel()
      launchDeadline = nil
      let handler = handler
      self.handler = nil
      if success { task.progress.completedUnitCount = 3 }
      task.setTaskCompleted(success: success)
      handler?(.completed(success))
    }

    func cancel() {
      if running != nil {
        finish(success: false)
      } else if identifier != nil {
        endPending(.cancelled)
      }
    }

    private func isCurrent(_ identifier: String) -> Bool { self.identifier == identifier }

    private func submitted(_ identifier: String) {
      guard self.identifier == identifier else {
        // Submission may finish after Close/Cancel. Cancel that late request as well.
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        return
      }
      handler?(.submitted)
    }

    private func refused(_ identifier: String, code: Int) {
      guard self.identifier == identifier, running == nil else { return }
      endPending(.refused(code))
    }

    private func launched(_ task: BGTask, identifier: String) {
      guard self.identifier == identifier, running == nil,
        let task = task as? BGContinuedProcessingTask
      else {
        task.setTaskCompleted(success: false)
        return
      }
      launchDeadline?.cancel()
      launchDeadline = nil
      running = task
      task.progress.totalUnitCount = 3
      task.progress.completedUnitCount = 0
      task.expirationHandler = { [weak self] in
        Task { @MainActor in self?.expired(identifier) }
      }
      handler?(.granted)
    }

    private func expired(_ identifier: String) {
      guard self.identifier == identifier, let task = running else { return }
      running = nil
      self.identifier = nil
      let handler = handler
      self.handler = nil
      // The owner tears down Python synchronously before the framework is told to suspend us.
      handler?(.expired)
      task.setTaskCompleted(success: false)
    }

    private func endPending(_ event: Event) {
      guard let identifier else { return }
      self.identifier = nil
      launchDeadline?.cancel()
      launchDeadline = nil
      BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
      let handler = handler
      self.handler = nil
      handler?(event)
    }
  }
#endif
