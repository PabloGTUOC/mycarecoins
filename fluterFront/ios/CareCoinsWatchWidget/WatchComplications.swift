import SwiftUI
import WidgetKit

private func formatShortTime(_ date: Date) -> String {
  let defaults = UserDefaults(suiteName: CareCoinsShared.appGroup)
  let lang = defaults?.string(forKey: CareCoinsShared.languageDefault)
  let df = DateFormatter()
  df.timeStyle = .short
  df.dateStyle = .none
  if let lang = lang, !lang.isEmpty {
    df.locale = Locale(identifier: lang)
  } else {
    df.locale = Locale.current
  }
  return df.string(from: date)
}

struct WatchComplicationEntry: TimelineEntry {
  let date: Date
  let snapshot: QuickSnapshot?
}

struct WatchComplicationProvider: TimelineProvider {
  func placeholder(in context: Context) -> WatchComplicationEntry {
    WatchComplicationEntry(date: .now, snapshot: SnapshotStore.load())
  }

  func getSnapshot(in context: Context, completion: @escaping (WatchComplicationEntry) -> Void) {
    completion(WatchComplicationEntry(date: .now, snapshot: SnapshotStore.load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WatchComplicationEntry>) -> Void) {
    let now = Date()
    guard let snapshot = SnapshotStore.load() else {
      let entry = WatchComplicationEntry(date: now, snapshot: nil)
      completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
      return
    }

    let calendar = Calendar.current
    var entryDates: Set<Date> = [now]

    if let current = snapshot.currentPlanned(now: now),
       let endsAt = current.endsAt, endsAt > now {
      entryDates.insert(endsAt)
    }

    let todayUpcoming = snapshot.upcoming.filter { item in
      calendar.isDate(item.startsAt, inSameDayAs: now) ||
      (item.endsAt != nil && calendar.isDate(item.endsAt!, inSameDayAs: now))
    }
    let futureItems = todayUpcoming.filter { item in
      item.startsAt > now || (item.endsAt != nil && item.endsAt! > now)
    }.sorted { $0.startsAt < $1.startsAt }

    for item in futureItems.prefix(3) {
      if item.startsAt > now {
        entryDates.insert(item.startsAt)
      }
      if let endsAt = item.endsAt, endsAt > now {
        entryDates.insert(endsAt)
      }
    }

    let entries = entryDates.sorted().map { WatchComplicationEntry(date: $0, snapshot: snapshot) }
    completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(30 * 60))))
  }
}

// MARK: - Balance Views

struct WatchCircularBalanceView: View {
  let balance: Int?
  @Environment(\.widgetRenderingMode) private var renderingMode

  var body: some View {
    VStack(spacing: 1) {
      if let balance = balance {
        Text("\(balance)")
          .font(.system(.subheadline, design: .rounded).weight(.bold))
          .privacySensitive()
      } else {
        Text("--")
          .font(.system(.subheadline, design: .rounded).weight(.bold))
      }
      Image(systemName: "circle.fill")
        .font(.system(size: 8))
        .foregroundColor(renderingMode == .fullColor ? Palette.coin : .primary)
    }
    .widgetAccentable()
  }
}

struct WatchCornerBalanceView: View {
  let balance: Int?

  var body: some View {
    if let balance = balance {
      Text("\(balance)")
        .font(.title3.bold())
        .privacySensitive()
        .widgetLabel {
          Text(L10n.t("widget.coins", Int64(balance)))
        }
    } else {
      Text("--")
        .font(.title3.bold())
        .widgetLabel {
          Text(L10n.t("widget.notConnected"))
        }
    }
  }
}

struct WatchInlineBalanceView: View {
  let balance: Int?

  var body: some View {
    if let balance = balance {
      Label {
        Text(L10n.t("widget.coins", Int64(balance)))
          .privacySensitive()
      } icon: {
        Image(systemName: "circle.fill")
      }
    } else {
      Text(L10n.t("widget.notConnected"))
    }
  }
}

struct WatchBalanceEntryView: View {
  let entry: WatchComplicationEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    let balance = entry.snapshot?.balance
    switch family {
    case .accessoryCircular:
      WatchCircularBalanceView(balance: balance)
        .containerBackground(for: .widget) {
          AccessoryWidgetBackground()
        }
    case .accessoryCorner:
      WatchCornerBalanceView(balance: balance)
        .containerBackground(.clear, for: .widget)
    default:
      WatchInlineBalanceView(balance: balance)
        .containerBackground(.clear, for: .widget)
    }
  }
}

public struct WatchBalanceComplication: Widget {
  public let kind: String = "CareCoinsWatchBalance"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
      WatchBalanceEntryView(entry: entry)
    }
    .configurationDisplayName(Text(L10n.t("watch.complication.balance.name")))
    .description(Text(L10n.t("watch.complication.description")))
    .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
  }
}

// MARK: - Next Views

struct WatchRectangularNextView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let snapshot = entry.snapshot {
        if let running = snapshot.running {
          Text(running.title)
            .font(.headline)
            .lineLimit(1)
          Text(running.startedAt, style: .timer)
            .font(.body.monospacedDigit())
            .foregroundColor(Palette.dangerOnDark)
        } else if let planned = snapshot.currentPlanned(now: entry.date) {
          let endTime = planned.endsAt != nil ? formatShortTime(planned.endsAt!) : ""
          Text(L10n.t("widget.nowPlanned", planned.title, endTime))
            .font(.headline)
            .lineLimit(2)
        } else if let next = snapshot.nextUpcoming(now: entry.date) {
          Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
            .font(.headline)
            .lineLimit(2)
        } else if snapshot.tasks.isEmpty {
          Text(L10n.t("widget.noTasks"))
            .font(.caption)
            .lineLimit(2)
        } else {
          Text(L10n.t("watch.nothingPlanned"))
            .font(.caption)
            .lineLimit(2)
        }
      } else {
        Text(L10n.t("widget.notConnected"))
          .font(.headline)
          .lineLimit(1)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct WatchInlineNextView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      if let running = snapshot.running {
        Text("\(running.title) \(Text(running.startedAt, style: .timer))")
      } else if let planned = snapshot.currentPlanned(now: entry.date) {
        Text(L10n.t("widget.nowPlannedShort", planned.title))
      } else if let next = snapshot.nextUpcoming(now: entry.date) {
        Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
      } else if snapshot.tasks.isEmpty {
        Text(L10n.t("widget.noTasks"))
      } else {
        Text(L10n.t("watch.nothingPlanned"))
      }
    } else {
      Text(L10n.t("widget.notConnected"))
    }
  }
}

struct WatchCircularNextView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      if let running = snapshot.running {
        VStack(spacing: 1) {
          Image(systemName: running.type.lowercased() == "care" ? "heart.fill" : "house.fill")
            .font(.caption2)
          Text(running.startedAt, style: .timer)
            .font(.system(.caption2, design: .rounded).monospacedDigit())
            .foregroundColor(Palette.dangerOnDark)
        }
      } else if let planned = snapshot.currentPlanned(now: entry.date) {
        VStack(spacing: 1) {
          Image(systemName: planned.type.lowercased() == "care" ? "heart.fill" : "house.fill")
            .font(.caption2)
          Text(L10n.t("widget.nowPlannedShort", planned.title))
            .font(.system(.caption2, design: .rounded).bold())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      } else if let next = snapshot.nextUpcoming(now: entry.date) {
        VStack(spacing: 1) {
          Image(systemName: next.type.lowercased() == "care" ? "heart.fill" : "house.fill")
            .font(.caption2)
          Text(formatShortTime(next.startsAt))
            .font(.system(.caption2, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
      } else {
        Image(systemName: "checkmark")
          .font(.caption)
      }
    } else {
      Text("--")
        .font(.system(.caption2, design: .rounded))
    }
  }
}

struct WatchCornerNextView: View {
  let entry: WatchComplicationEntry

  var body: some View {
    if let snapshot = entry.snapshot {
      if let running = snapshot.running {
        Image(systemName: running.type.lowercased() == "care" ? "heart.fill" : "house.fill")
          .widgetLabel {
            Text("\(running.title) \(Text(running.startedAt, style: .timer))")
          }
      } else if let planned = snapshot.currentPlanned(now: entry.date) {
        Image(systemName: planned.type.lowercased() == "care" ? "heart.fill" : "house.fill")
          .widgetLabel {
            Text(L10n.t("widget.nowPlannedShort", planned.title))
          }
      } else if let next = snapshot.nextUpcoming(now: entry.date) {
        Image(systemName: next.type.lowercased() == "care" ? "heart.fill" : "house.fill")
          .widgetLabel {
            Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
          }
      } else if snapshot.tasks.isEmpty {
        Text(L10n.t("widget.noTasks"))
      } else {
        Text(L10n.t("watch.nothingPlanned"))
      }
    } else {
      Text("--")
    }
  }
}

struct WatchNextEntryView: View {
  let entry: WatchComplicationEntry
  @Environment(\.widgetFamily) private var family

  var body: some View {
    switch family {
    case .accessoryRectangular:
      WatchRectangularNextView(entry: entry)
        .containerBackground(.clear, for: .widget)
    case .accessoryCircular:
      WatchCircularNextView(entry: entry)
        .containerBackground(for: .widget) {
          AccessoryWidgetBackground()
        }
    case .accessoryCorner:
      WatchCornerNextView(entry: entry)
        .containerBackground(.clear, for: .widget)
    default:
      WatchInlineNextView(entry: entry)
        .containerBackground(.clear, for: .widget)
    }
  }
}

public struct WatchNextComplication: Widget {
  public let kind: String = "CareCoinsWatchNext"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: WatchComplicationProvider()) { entry in
      WatchNextEntryView(entry: entry)
    }
    .configurationDisplayName(Text(L10n.t("watch.complication.next.name")))
    .description(Text(L10n.t("watch.complication.description")))
    .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular, .accessoryCorner])
  }
}
