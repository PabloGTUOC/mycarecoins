#if canImport(ActivityKit)
import ActivityKit
#endif
#if canImport(AppIntents)
import AppIntents
#endif
import Foundation
import WidgetKit

@available(iOS 17.0, *)
func widgetMessage(for error: Error) -> String {
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

@available(iOS 17.0, *)
@discardableResult
private func refreshSnapshot(api: QuickAPI) async -> QuickSnapshot? {
  if let (snapshot, data) = try? await api.snapshot() {
    SnapshotStore.save(data)
    return snapshot
  }
  return nil
}

@available(iOS 17.0, *)
public struct StartTaskIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Start Task"
  public static var isDiscoverable = false

  @Parameter(title: "Task ID")
  public var taskId: String

  public init() {}

  public init(taskId: String) {
    self.taskId = taskId
  }

  public func perform() async throws -> some IntentResult {
    guard let api = QuickAPI.fromStore() else {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      return .result()
    }
    let clientRef = QuickAPI.newClientRef()
    do {
      let result = try await api.start(templateId: taskId, clientRef: clientRef)
      SnapshotStore.recordAction(LastAction(kind: .started, taskId: taskId, activityId: result.activity?.id, clientRef: clientRef))
      if let snapshot = await refreshSnapshot(api: api) {
        #if canImport(ActivityKit)
        QuickLiveActivities.sync(with: snapshot, now: Date())
        #endif
      }
    } catch {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: widgetMessage(for: error)))
    }
    return .result()
  }
}

@available(iOS 17.0, *)
public struct DoneTaskIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Done Task"
  public static var isDiscoverable = false

  @Parameter(title: "Task ID")
  public var taskId: String

  public init() {}

  public init(taskId: String) {
    self.taskId = taskId
  }

  public func perform() async throws -> some IntentResult {
    guard let api = QuickAPI.fromStore() else {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      return .result()
    }
    let clientRef = QuickAPI.newClientRef()
    do {
      if taskId.isEmpty {
        let title = L10n.t("widget.title.care")
        let result = try await api.startNow(type: "care", title: title, clientRef: clientRef)
        SnapshotStore.recordAction(LastAction(kind: .started, activityId: result.activity?.id, clientRef: clientRef))
      } else {
        _ = try await api.done(templateId: taskId, clientRef: clientRef)
        SnapshotStore.recordAction(LastAction(kind: .logged, taskId: taskId, clientRef: clientRef))
      }
      if let snapshot = await refreshSnapshot(api: api) {
        #if canImport(ActivityKit)
        QuickLiveActivities.sync(with: snapshot, now: Date())
        #endif
      }
    } catch {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: widgetMessage(for: error)))
    }
    return .result()
  }
}

@available(iOS 17.0, *)
public struct StartNowIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Start Now"
  public static var isDiscoverable = false

  @Parameter(title: "Type")
  public var type: String

  public init() {}

  public init(type: String) {
    self.type = type
  }

  public func perform() async throws -> some IntentResult {
    guard let api = QuickAPI.fromStore() else {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      return .result()
    }
    let clientRef = QuickAPI.newClientRef()
    let title = L10n.t("widget.title.\(type)")
    do {
      let result = try await api.startNow(type: type, title: title, clientRef: clientRef)
      SnapshotStore.recordAction(LastAction(kind: .started, activityId: result.activity?.id, clientRef: clientRef))
      if let snapshot = await refreshSnapshot(api: api) {
        #if canImport(ActivityKit)
        QuickLiveActivities.sync(with: snapshot, now: Date())
        #endif
      }
    } catch {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: widgetMessage(for: error)))
    }
    return .result()
  }
}

@available(iOS 17.0, *)
public struct StopTaskIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Stop Task"
  public static var isDiscoverable = false

  @Parameter(title: "Activity ID")
  public var activityId: String

  public init() {}

  public init(activityId: String) {
    self.activityId = activityId
  }

  public func perform() async throws -> some IntentResult {
    guard let api = QuickAPI.fromStore() else {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      return .result()
    }
    do {
      _ = try await api.stop(activityId: activityId)
      SnapshotStore.recordAction(LastAction(kind: .stopped, activityId: activityId))
      if let snapshot = await refreshSnapshot(api: api) {
        #if canImport(ActivityKit)
        QuickLiveActivities.sync(with: snapshot, now: Date())
        #endif
      } else {
        #if canImport(ActivityKit)
        QuickLiveActivities.endAll()
        #endif
      }
    } catch {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: widgetMessage(for: error)))
    }
    return .result()
  }
}

@available(iOS 17.0, *)
public struct UndoIntent: LiveActivityIntent {
  public static var title: LocalizedStringResource = "Undo"
  public static var isDiscoverable = false

  @Parameter(title: "Client Ref")
  public var clientRef: String

  public init() {}

  public init(clientRef: String) {
    self.clientRef = clientRef
  }

  public func perform() async throws -> some IntentResult {
    guard let api = QuickAPI.fromStore() else {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: L10n.t("widget.error.revoked")))
      return .result()
    }
    do {
      _ = try await api.undo(clientRef: clientRef)
      SnapshotStore.recordAction(LastAction(kind: .undone, clientRef: clientRef))
      if let snapshot = await refreshSnapshot(api: api) {
        #if canImport(ActivityKit)
        QuickLiveActivities.sync(with: snapshot, now: Date())
        #endif
      } else {
        #if canImport(ActivityKit)
        QuickLiveActivities.endAll()
        #endif
      }
    } catch {
      SnapshotStore.recordAction(LastAction(kind: .failed, message: widgetMessage(for: error)))
    }
    return .result()
  }
}
