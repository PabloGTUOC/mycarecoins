import SwiftUI
import WidgetKit

// Phase 0 placeholder (docs/ios-widget-watch-plan.md): proves the target builds, signs
// and embeds. The real widgets replace this file in a later phase.
struct CareCoinsWidgetEntry: TimelineEntry {
  let date: Date
}

struct CareCoinsWidgetProvider: TimelineProvider {
  func placeholder(in context: Context) -> CareCoinsWidgetEntry { CareCoinsWidgetEntry(date: .now) }

  func getSnapshot(in context: Context, completion: @escaping (CareCoinsWidgetEntry) -> Void) {
    completion(CareCoinsWidgetEntry(date: .now))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<CareCoinsWidgetEntry>) -> Void) {
    completion(Timeline(entries: [CareCoinsWidgetEntry(date: .now)], policy: .never))
  }
}

struct CareCoinsWidgetWidget: Widget {
  var body: some WidgetConfiguration {
    StaticConfiguration(kind: "CareCoinsWidget", provider: CareCoinsWidgetProvider()) { _ in
      Text(verbatim: "CareCoins")
        .containerBackground(.fill.tertiary, for: .widget)
    }
    .configurationDisplayName(Text(verbatim: "CareCoins"))
    .supportedFamilies([.systemSmall])
  }
}

@main
struct CareCoinsWidgetBundle: WidgetBundle {
  var body: some Widget {
    CareCoinsWidgetWidget()
  }
}
