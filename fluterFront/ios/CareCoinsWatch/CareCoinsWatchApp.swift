import SwiftUI
import WatchKit

@main
struct CareCoinsWatchApp: App {
  @State private var store = WatchStore.shared
  @Environment(\.scenePhase) private var phase

  init() {
    WatchConnector.shared.activate()
    WatchReminders.setupAtLaunch()
  }

  var body: some Scene {
    WindowGroup {
      WatchRootView()
        .environment(store)
    }
    .onChange(of: phase) { _, newPhase in
      if newPhase == .active {
        store.reloadFromDisk()
        WatchReminders.reschedule(from: store.snapshot, now: .now)
        SnapshotStore.reloadWidgets()
        Task {
          await store.refresh()
          scheduleNextBackgroundRefresh()
        }
      }
    }
    .backgroundTask(.appRefresh("carecoins.refresh")) {
      await store.refresh()
      scheduleNextBackgroundRefresh()
    }
  }

  private func scheduleNextBackgroundRefresh() {
    let nextDate = Date().addingTimeInterval(30 * 60)
    WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: nextDate, userInfo: nil) { _ in }
  }
}
