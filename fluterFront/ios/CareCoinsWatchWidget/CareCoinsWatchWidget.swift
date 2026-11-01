import SwiftUI
import WidgetKit

@main
struct CareCoinsWatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    WatchBalanceComplication()
    WatchNextComplication()
  }
}
