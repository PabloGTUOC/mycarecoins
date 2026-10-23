import SwiftUI
import WidgetKit

// Phase 0 placeholder (docs/ios-widget-watch-plan.md): proves the target builds, signs
// and embeds. The real widgets replace this file in a later phase.
struct CareCoinsWatchWidgetEntry: TimelineEntry {
  let date: Date
}

struct CareCoinsWatchWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> CareCoinsWatchWidgetEntry { CareCoinsWatchWidgetEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (CareCoinsWatchWidgetEntry) -> Void) {
    completion(CareCoinsWatchWidgetEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CareCoinsWatchWidgetEntry>) -> Void) {
    completion(Timeline(entries: [CareCoinsWatchWidgetEntry(date: .now)], policy: .never))
  }
}

struct CareCoinsWatchWidgetWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CareCoinsWatchWidget", provider: CareCoinsWatchWidgetProvider()) { _ in
      Text(verbatim: "CareCoins")
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(Text(verbatim: "CareCoins"))
    .supportedFamilies([.accessoryCircular])
  }
}

@main
struct CareCoinsWatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    CareCoinsWatchWidgetWidget()
  }
}
