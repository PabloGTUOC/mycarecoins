import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
public struct QuickActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var startedAt: Date
    public var stopped: Bool

    public init(startedAt: Date, stopped: Bool = false) {
      self.startedAt = startedAt
      self.stopped = stopped
    }
  }

  public var activityId: String
  public var title: String

  public init(activityId: String, title: String) {
    self.activityId = activityId
    self.title = title
  }
}

@available(iOS 17.0, *)
public enum QuickLiveActivities {
  public static func sync(with snapshot: QuickSnapshot, now: Date = Date()) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      let currentActivities = Activity<QuickActivityAttributes>.activities
      for activity in currentActivities {
        if let running = snapshot.running, activity.attributes.activityId == running.id {
          continue
        }
        Task {
          await activity.end(dismissalPolicy: .immediate)
        }
      }

      if let running = snapshot.running {
        let isAlreadyRunning = currentActivities.contains { $0.attributes.activityId == running.id }
        if !isAlreadyRunning {
          let attributes = QuickActivityAttributes(activityId: running.id, title: running.title)
          let contentState = QuickActivityAttributes.ContentState(
            startedAt: running.startedAt,
            stopped: false
          )
          let staleDate = running.startedAt.addingTimeInterval(4 * 3600)
          let content = ActivityContent(state: contentState, staleDate: staleDate)
          _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
        }
      }
    } catch {
      // Live Activities can be disabled by the user, ignore errors
    }
  }

  public static func endAll() {
    do {
      let currentActivities = Activity<QuickActivityAttributes>.activities
      for activity in currentActivities {
        Task {
          await activity.end(dismissalPolicy: .immediate)
        }
      }
    } catch {
      // ignore
    }
  }
}
#endif
