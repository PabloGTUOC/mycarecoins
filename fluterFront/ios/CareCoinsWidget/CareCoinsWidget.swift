import SwiftUI
import WidgetKit

@main
struct CareCoinsWidgetBundle: WidgetBundle {
  var body: some Widget {
    QuickTasksWidget()
    BalanceWidget()
  }
}
