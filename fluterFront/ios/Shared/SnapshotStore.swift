import Foundation
import WidgetKit

public struct LastAction: Codable, Equatable {
  public enum Kind: String, Codable {
    case started, logged, stopped, undone, failed, cancelled
  }

  public let kind: Kind
  public let taskId: String?
  public let activityId: String?
  public let clientRef: String?
  public let message: String?
  public let at: Date

  public init(
    kind: Kind,
    taskId: String? = nil,
    activityId: String? = nil,
    clientRef: String? = nil,
    message: String? = nil,
    at: Date = Date()
  ) {
    self.kind = kind
    self.taskId = taskId
    self.activityId = activityId
    self.clientRef = clientRef
    self.message = message
    self.at = at
  }
}

public enum SnapshotStore {
  public static let lastActionFile = "lastAction.json"
  public static let undoWindow: TimeInterval = 30.0

  private static var containerURL: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CareCoinsShared.appGroup)
  }

  public static func load() -> QuickSnapshot? {
    guard let containerURL = containerURL else { return nil }
    let fileURL = containerURL.appendingPathComponent(CareCoinsShared.snapshotFile)
    guard let data = try? Data(contentsOf: fileURL) else { return nil }
    return try? JSONDecoder.quick.decode(QuickSnapshot.self, from: data)
  }

  @discardableResult
  public static func save(_ data: Data) -> Bool {
    guard (try? JSONDecoder.quick.decode(QuickSnapshot.self, from: data)) != nil else {
      return false
    }
    guard let containerURL = containerURL else { return false }
    let fileURL = containerURL.appendingPathComponent(CareCoinsShared.snapshotFile)
    do {
      try data.write(to: fileURL, options: .atomic)
      return true
    } catch {
      return false
    }
  }

  public static func recordAction(_ action: LastAction) {
    guard let containerURL = containerURL else { return }
    let fileURL = containerURL.appendingPathComponent(lastActionFile)
    guard let data = try? JSONEncoder.quick.encode(action) else { return }
    try? data.write(to: fileURL, options: .atomic)
  }

  public static func lastAction(now: Date = Date()) -> LastAction? {
    guard let containerURL = containerURL else { return nil }
    let fileURL = containerURL.appendingPathComponent(lastActionFile)
    guard let data = try? Data(contentsOf: fileURL),
          let action = try? JSONDecoder.quick.decode(LastAction.self, from: data) else {
      return nil
    }
    let elapsed = now.timeIntervalSince(action.at)
    if elapsed >= 0 && elapsed <= undoWindow {
      return action
    }
    return nil
  }

  public static func clearLastAction() {
    guard let containerURL = containerURL else { return }
    let fileURL = containerURL.appendingPathComponent(lastActionFile)
    try? FileManager.default.removeItem(at: fileURL)
  }

  public static func canUndo(now: Date = Date()) -> Bool {
    guard let action = lastAction(now: now) else { return false }
    guard action.kind == .started || action.kind == .logged else { return false }
    guard let ref = action.clientRef, !ref.isEmpty else { return false }
    return true
  }

  public static func reloadWidgets() {
    WidgetCenter.shared.reloadAllTimelines()
  }
}
