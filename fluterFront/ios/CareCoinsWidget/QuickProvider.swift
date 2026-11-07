import SwiftUI
import WidgetKit

public struct QuickEntry: TimelineEntry {
  public enum State: Equatable {
    case notConnected
    case ready(QuickSnapshot)
    case empty
  }

  public let date: Date
  public let state: State
  public let lastAction: LastAction?
  public let canUndo: Bool

  public init(
    date: Date,
    state: State,
    lastAction: LastAction? = nil,
    canUndo: Bool = false
  ) {
    self.date = date
    self.state = state
    self.lastAction = lastAction
    self.canUndo = canUndo
  }
}

public struct QuickProvider: TimelineProvider {
  public typealias Entry = QuickEntry

  public static var sampleSnapshot: QuickSnapshot {
    QuickSnapshot(
      family: QuickSnapshot.Family(id: "1", name: "Family"),
      balance: 42,
      needsYou: 1,
      tasks: [
        QuickSnapshot.Task(id: "1", title: "Breakfast routine", type: "care", durationMinutes: 20, coinValue: 20),
        QuickSnapshot.Task(id: "2", title: "Medication", type: "care", durationMinutes: 10, coinValue: 10),
        QuickSnapshot.Task(id: "3", title: "School drop-off", type: "care", durationMinutes: 30, coinValue: 30),
        QuickSnapshot.Task(id: "4", title: "Kitchen tidy-up", type: "household", durationMinutes: 15, coinValue: 15),
      ],
      upcoming: [],
      running: nil,
      serverTime: Date()
    )
  }

  public init() {}

  public func placeholder(in context: Context) -> QuickEntry {
    QuickEntry(date: Date(), state: .ready(Self.sampleSnapshot))
  }

  public func getSnapshot(in context: Context, completion: @escaping (QuickEntry) -> Void) {
    let now = Date()
    if context.isPreview {
      completion(QuickEntry(date: now, state: .ready(Self.sampleSnapshot)))
      return
    }
    if QuickAPI.fromStore() == nil {
      completion(QuickEntry(date: now, state: .notConnected))
      return
    }
    if let snapshot = SnapshotStore.load() {
      let action = SnapshotStore.lastAction(now: now)
      let canUndo = SnapshotStore.canUndo(now: now)
      completion(QuickEntry(date: now, state: .ready(snapshot), lastAction: action, canUndo: canUndo))
    } else {
      completion(QuickEntry(date: now, state: .empty))
    }
  }

  public func getTimeline(in context: Context, completion: @escaping (Timeline<QuickEntry>) -> Void) {
    let now = Date()
    guard let api = QuickAPI.fromStore() else {
      let entry = QuickEntry(date: now, state: .notConnected)
      let timeline = Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60)))
      completion(timeline)
      return
    }

    Task {
      var snapshot: QuickSnapshot?
      do {
        let (fetchedSnap, rawData) = try await api.snapshot()
        SnapshotStore.save(rawData)
        snapshot = fetchedSnap
      } catch {
        snapshot = SnapshotStore.load()
      }

      let state: QuickEntry.State
      if let snap = snapshot {
        state = .ready(snap)
      } else {
        state = .empty
      }

      let action = SnapshotStore.lastAction(now: now)
      let canUndo = SnapshotStore.canUndo(now: now)

      let reloadDate = now.addingTimeInterval(30 * 60)
      var entryDates: Set<Date> = [now]

      if let snap = snapshot {
        if let currentEnds = snap.currentPlanned(now: now)?.endsAt, currentEnds > now && currentEnds <= reloadDate {
          entryDates.insert(currentEnds)
        }

        let upcomingInWindow = snap.upcoming
          .filter { $0.startsAt > now && $0.startsAt <= reloadDate }
          .sorted { $0.startsAt < $1.startsAt }

        for item in upcomingInWindow.prefix(max(3, upcomingInWindow.count)) {
          entryDates.insert(item.startsAt)
          if let endsAt = item.endsAt, endsAt > now && endsAt <= reloadDate {
            entryDates.insert(endsAt)
          }
        }
      }

      var expireDate: Date? = nil
      if let action = action {
        let exp = action.at.addingTimeInterval(SnapshotStore.undoWindow)
        if exp > now {
          expireDate = exp
          if exp <= reloadDate {
            entryDates.insert(exp)
          }
        }
      }

      let entries = entryDates.sorted().map { date in
        let actionForDate = (action != nil && expireDate != nil && date < expireDate!) ? action : nil
        let canUndoForDate = actionForDate != nil ? canUndo : false
        return QuickEntry(date: date, state: state, lastAction: actionForDate, canUndo: canUndoForDate)
      }

      let policy = TimelineReloadPolicy.after(reloadDate)
      let timeline = Timeline(entries: entries, policy: policy)
      completion(timeline)
    }
  }
}
