import SwiftUI
import WidgetKit

@main
struct CareCoinsWidgetBundle: WidgetBundle {
  var body: some Widget {
    QuickTasksWidget()
    BalanceWidget()
    #if canImport(ActivityKit)
    QuickLiveActivityWidget()
    #endif
    StartCareNowControl()
    LogTopTaskControl()
  }
}
