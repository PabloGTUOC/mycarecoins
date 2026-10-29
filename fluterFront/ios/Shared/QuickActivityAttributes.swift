import Foundation

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
public struct QuickActivityAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    public var startedAt: Date
    public var plannedEnd: Date?      // nil for an unplanned running task; set for a started template
    public var stopped: Bool          // true once stopped or finished, just before ending

    public init(startedAt: Date, plannedEnd: Date? = nil, stopped: Bool = false) {
      self.startedAt = startedAt
      self.plannedEnd = plannedEnd
      self.stopped = stopped
    }
  }

  public var activityId: String       // the server instance id
  public var title: String
  public var kind: String             // "running" (unplanned, Stop) or "started" (template, Done)

  public init(activityId: String, title: String, kind: String) {
    self.activityId = activityId
    self.title = title
    self.kind = kind
  }
}

@available(iOS 17.0, *)
public enum QuickLiveActivities {
  public static func sync(with snapshot: QuickSnapshot, now: Date = Date()) {
    guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
    do {
      let wanted: (activityId: String, title: String, kind: String, startedAt: Date, plannedEnd: Date?)?
      if let running = snapshot.running {
        wanted = (activityId: running.id, title: running.title, kind: "running", startedAt: running.startedAt, plannedEnd: nil)
      } else if let started = snapshot.startedTask(now: now) {
        wanted = (activityId: started.id, title: started.title, kind: "started", startedAt: started.startsAt, plannedEnd: started.endsAt)
      } else {
        wanted = nil
      }

      let currentActivities = Activity<QuickActivityAttributes>.activities
      for activity in currentActivities {
        if let wanted = wanted, activity.attributes.activityId == wanted.activityId {
          continue
        }
        Task {
          await activity.end(dismissalPolicy: .immediate)
        }
      }

      if let wanted = wanted {
        let isAlreadyRunning = currentActivities.contains { $0.attributes.activityId == wanted.activityId }
        if !isAlreadyRunning {
          let attributes = QuickActivityAttributes(activityId: wanted.activityId, title: wanted.title, kind: wanted.kind)
          let contentState = QuickActivityAttributes.ContentState(
            startedAt: wanted.startedAt,
            plannedEnd: wanted.plannedEnd,
            stopped: false
          )
          let staleDate = wanted.plannedEnd ?? wanted.startedAt.addingTimeInterval(4 * 3600)
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
