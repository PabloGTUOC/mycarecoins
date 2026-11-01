import Foundation
import Observation
import WatchKit

public struct PendingAction: Codable, Identifiable, Equatable {
  public enum Kind: String, Codable {
    case start
    case done
    case finish
    case startNow
    case stop
  }

  public let id: String
  public let kind: Kind
  public let taskId: String?
  public let activityId: String?
  public let type: String?
  public let title: String?
  public let clientRef: String?
  public let createdAt: Date

  public init(
    id: String? = nil,
    kind: Kind,
    taskId: String? = nil,
    activityId: String? = nil,
    type: String? = nil,
    title: String? = nil,
    clientRef: String? = nil,
    createdAt: Date = Date()
  ) {
    self.id = id ?? clientRef ?? UUID().uuidString
    self.kind = kind
    self.taskId = taskId
    self.activityId = activityId
    self.type = type
    self.title = title
    self.clientRef = clientRef
    self.createdAt = createdAt
  }
}

@MainActor
@Observable
public final class WatchStore {
  public static let shared = WatchStore()

  public var snapshot: QuickSnapshot?
  public var connected: Bool = false
  public var pending: [PendingAction] = []
  public var lastAction: LastAction?
  public var isRefreshing: Bool = false

  public var canUndo: Bool {
    SnapshotStore.canUndo(now: Date())
  }

  public init() {
    reloadFromDisk()
  }

  public func reloadFromDisk() {
    self.snapshot = SnapshotStore.load()
    self.connected = QuickAPI.fromStore() != nil
    self.lastAction = SnapshotStore.lastAction()
    self.pending = loadPendingQueue()
  }

  public func refresh() async {
    guard !isRefreshing else { return }
    isRefreshing = true
    defer { isRefreshing = false }

    guard let api = QuickAPI.fromStore() else {
      reloadFromDisk()
      return
    }

    do {
      let (_, data) = try await api.snapshot()
      SnapshotStore.save(data)
      reloadFromDisk()
      await flushQueue()
    } catch let QuickAPIError.server(status, _, _, _) where status == 401 {
      CareCoinsShared.disconnectLocally()
      reloadFromDisk()
    } catch QuickAPIError.network {
      await flushQueue()
    } catch {
      // Ignore other errors during background/pull refresh
    }
  }

  public func start(task: QuickSnapshot.Task) async {
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    let clientRef = QuickAPI.newClientRef()
    do {
      let result = try await api.start(templateId: task.id, clientRef: clientRef)
      recordAction(LastAction(kind: .started, taskId: task.id, activityId: result.activity?.id, clientRef: clientRef))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch QuickAPIError.network {
      enqueuePending(PendingAction(kind: .start, taskId: task.id, clientRef: clientRef))
      WKInterfaceDevice.current().play(.notification)
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func done(task: QuickSnapshot.Task) async {
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    let clientRef = QuickAPI.newClientRef()
    do {
      _ = try await api.done(templateId: task.id, clientRef: clientRef)
      recordAction(LastAction(kind: .logged, taskId: task.id, clientRef: clientRef))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch QuickAPIError.network {
      enqueuePending(PendingAction(kind: .done, taskId: task.id, clientRef: clientRef))
      WKInterfaceDevice.current().play(.notification)
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func finish(upcomingId: String) async {
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    do {
      _ = try await api.finish(activityId: upcomingId)
      recordAction(LastAction(kind: .logged, activityId: upcomingId))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch QuickAPIError.network {
      enqueuePending(PendingAction(kind: .finish, activityId: upcomingId))
      WKInterfaceDevice.current().play(.notification)
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func startNow(type: String, title: String) async {
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    let clientRef = QuickAPI.newClientRef()
    let effectiveTitle = title.isEmpty ? L10n.t("widget.title.\(type)") : title
    do {
      let result = try await api.startNow(type: type, title: effectiveTitle, clientRef: clientRef)
      recordAction(LastAction(kind: .started, activityId: result.activity?.id, clientRef: clientRef))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch QuickAPIError.network {
      enqueuePending(PendingAction(kind: .startNow, type: type, title: effectiveTitle, clientRef: clientRef))
      WKInterfaceDevice.current().play(.notification)
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func stop(runningId: String) async {
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    do {
      _ = try await api.stop(activityId: runningId)
      recordAction(LastAction(kind: .stopped, activityId: runningId))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch QuickAPIError.network {
      enqueuePending(PendingAction(kind: .stop, activityId: runningId))
      WKInterfaceDevice.current().play(.notification)
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func undo() async {
    guard canUndo, let ref = lastAction?.clientRef, !ref.isEmpty else { return }
    guard let api = QuickAPI.fromStore() else {
      recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      WKInterfaceDevice.current().play(.failure)
      return
    }
    do {
      _ = try await api.undo(clientRef: ref)
      recordAction(LastAction(kind: .undone, clientRef: ref))
      WKInterfaceDevice.current().play(.success)
      await refresh()
    } catch {
      recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      WKInterfaceDevice.current().play(.failure)
    }
  }

  public func flushQueue() async {
    let cutoff = Date().addingTimeInterval(-12 * 3600)
    pending.removeAll { $0.createdAt < cutoff }
    savePendingQueue(pending)

    guard let api = QuickAPI.fromStore() else { return }

    while !pending.isEmpty {
      let item = pending[0]
      do {
        switch item.kind {
        case .start:
          guard let taskId = item.taskId else {
            pending.removeFirst()
            savePendingQueue(pending)
            continue
          }
          let ref = item.clientRef ?? QuickAPI.newClientRef()
          let result = try await api.start(templateId: taskId, clientRef: ref)
          recordAction(LastAction(kind: .started, taskId: taskId, activityId: result.activity?.id, clientRef: ref))
        case .done:
          guard let taskId = item.taskId else {
            pending.removeFirst()
            savePendingQueue(pending)
            continue
          }
          let ref = item.clientRef ?? QuickAPI.newClientRef()
          _ = try await api.done(templateId: taskId, clientRef: ref)
          recordAction(LastAction(kind: .logged, taskId: taskId, clientRef: ref))
        case .finish:
          guard let activityId = item.activityId else {
            pending.removeFirst()
            savePendingQueue(pending)
            continue
          }
          _ = try await api.finish(activityId: activityId)
          recordAction(LastAction(kind: .logged, activityId: activityId))
        case .startNow:
          let type = item.type ?? "care"
          let title = item.title ?? L10n.t("widget.title.\(type)")
          let ref = item.clientRef ?? QuickAPI.newClientRef()
          let result = try await api.startNow(type: type, title: title, clientRef: ref)
          recordAction(LastAction(kind: .started, activityId: result.activity?.id, clientRef: ref))
        case .stop:
          guard let activityId = item.activityId else {
            pending.removeFirst()
            savePendingQueue(pending)
            continue
          }
          _ = try await api.stop(activityId: activityId)
          recordAction(LastAction(kind: .stopped, activityId: activityId))
        }
        pending.removeFirst()
        savePendingQueue(pending)
      } catch QuickAPIError.network {
        break
      } catch {
        pending.removeFirst()
        savePendingQueue(pending)
        recordAction(LastAction(kind: .failed, message: watchMessage(for: error)))
      }
    }
  }

  public func recordAction(_ action: LastAction) {
    SnapshotStore.recordAction(action)
    self.lastAction = action
  }

  private func enqueuePending(_ action: PendingAction) {
    pending.append(action)
    savePendingQueue(pending)
  }

  private func watchMessage(for error: Error) -> String {
    if let apiError = error as? QuickAPIError {
      switch apiError {
      case .server(let status, let code, _, let params):
        if code == "scheduleOverlap" {
          let title = params["title"] ?? ""
          return L10n.t("widget.error.overlap", title)
        } else if code == "quickTaskAlreadyRunning" {
          let title = params["title"] ?? ""
          return L10n.t("widget.error.alreadyRunning", title)
        } else if code == "quickUndoExpired" {
          return L10n.t("widget.error.undoExpired")
        } else if status == 401 {
          return L10n.t("widget.error.revoked")
        } else {
          return L10n.t("widget.error.generic")
        }
      case .notConnected:
        return L10n.t("widget.error.revoked")
      case .network:
        return L10n.t("widget.error.generic")
      }
    }
    return L10n.t("widget.error.generic")
  }

  private func appGroupFileURL(_ filename: String) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CareCoinsShared.appGroup)?
      .appendingPathComponent(filename)
  }

  private func loadPendingQueue() -> [PendingAction] {
    guard let fileURL = appGroupFileURL("pendingActions.json"),
          let data = try? Data(contentsOf: fileURL),
          let queue = try? JSONDecoder.quick.decode([PendingAction].self, from: data) else {
      return []
    }
    let cutoff = Date().addingTimeInterval(-12 * 3600)
    let valid = queue.filter { $0.createdAt >= cutoff }
    if valid.count != queue.count {
      savePendingQueue(valid)
    }
    return valid
  }

  private func savePendingQueue(_ queue: [PendingAction]) {
    guard let fileURL = appGroupFileURL("pendingActions.json"),
          let data = try? JSONEncoder.quick.encode(queue) else {
      return
    }
    try? data.write(to: fileURL, options: .atomic)
  }
}
