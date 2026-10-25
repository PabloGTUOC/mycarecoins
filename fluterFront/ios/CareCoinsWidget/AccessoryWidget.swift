import SwiftUI
import WidgetKit

struct CircularBalanceView: View {
  let balance: Int
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    VStack(spacing: 1) {
      Image(systemName: "circle.fill")
        .font(.system(size: 10))
        .foregroundColor(renderingMode == .fullColor ? Palette.coin : .primary)
      Text("\(balance)")
        .font(.system(.subheadline, design: .rounded).weight(.bold))
        .privacySensitive()
    }
    .widgetAccentable()
  }
}

struct RectangularBalanceView: View {
  let balance: Int
  let needsYou: Int

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 4) {
        Image(systemName: "circle.fill")
          .font(.system(size: 8))
        Text(L10n.t("widget.coins", Int64(balance)))
          .font(.headline)
          .privacySensitive()
      }
      if needsYou > 0 {
        Text(L10n.t("widget.needsYou", Int64(needsYou)))
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
  }
}

struct InlineBalanceView: View {
  let balance: Int

  var body: some View {
    Label {
      Text(L10n.t("widget.coins", Int64(balance)))
        .privacySensitive()
    } icon: {
      Image(systemName: "circle.fill")
    }
  }
}

public struct BalanceEntryView: View {
  let entry: QuickEntry
  @Environment(\.widgetFamily) var family

  public init(entry: QuickEntry) {
    self.entry = entry
  }

  var balance: Int {
    switch entry.state {
    case .ready(let snap): return snap.balance
    default: return 0
    }
  }

  var needsYou: Int {
    switch entry.state {
    case .ready(let snap): return snap.needsYou
    default: return 0
    }
  }

  public var body: some View {
    switch family {
    case .accessoryCircular:
      CircularBalanceView(balance: balance)
        .containerBackground(for: .widget) {
          AccessoryWidgetBackground()
        }
    case .accessoryRectangular:
      RectangularBalanceView(balance: balance, needsYou: needsYou)
        .containerBackground(.clear, for: .widget)
    default:
      InlineBalanceView(balance: balance)
        .containerBackground(.clear, for: .widget)
    }
  }
}

public struct BalanceWidget: Widget {
  public let kind: String = "CareCoinsBalance"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickProvider()) { entry in
      BalanceEntryView(entry: entry)
    }
    .configurationDisplayName(Text(L10n.t("widget.balance.name")))
    .description(Text(L10n.t("widget.balance.description")))
    .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}
