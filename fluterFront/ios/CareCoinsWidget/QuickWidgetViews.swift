import SwiftUI
import WidgetKit

func formatShortTime(_ date: Date) -> String {
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

private let widgetDeepLinkURL = URL(string: "carecoins://open")!

private func softFill(_ fullColorFill: Color, renderingMode: WidgetRenderingMode) -> Color {
  renderingMode == .fullColor ? fullColorFill : Color.secondary.opacity(0.18)
}

private func tileFill(_ colorScheme: ColorScheme, renderingMode: WidgetRenderingMode) -> Color {
  renderingMode == .fullColor ? Palette.widgetTile(colorScheme) : Color.secondary.opacity(0.12)
}

private func inkColor(_ fullColorInk: Color, renderingMode: WidgetRenderingMode) -> Color {
  renderingMode == .fullColor ? fullColorInk : Color.primary
}

// MARK: - Coin Glyph & Header

struct CoinGlyph: View {
  var size: CGFloat = 13
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    let innerSize = round(size * 0.62)
    let strokeWidth = max(1.2, size * 0.115)
    ZStack {
      Circle()
        .fill(renderingMode == .fullColor ? Palette.coin : Color.secondary.opacity(0.28))
      Circle()
        .strokeBorder(
          renderingMode == .fullColor ? Palette.coinRing : Color.primary,
          lineWidth: strokeWidth
        )
        .frame(width: innerSize, height: innerSize)
    }
    .frame(width: size, height: size)
    .widgetAccentable()
  }
}

struct CoinPill: View {
  let balance: Int
  var height: CGFloat = 20
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    HStack(spacing: 5) {
      CoinGlyph(size: 13)
      Text("\(balance)")
        .font(.subheadline.bold())
        .monospacedDigit()
        .foregroundColor(inkColor(Palette.coinInk(colorScheme), renderingMode: renderingMode))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
    .padding(.horizontal, 8)
    .frame(height: height)
    .background(
      Capsule()
        .fill(softFill(Palette.coinSoft(colorScheme), renderingMode: renderingMode))
    )
    .privacySensitive()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.t("widget.a11y.balance", Int64(balance)))
  }
}

struct NeedsYouBadge: View {
  let needsYou: Int
  var isSmall: Bool = false
  var height: CGFloat = 20
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    let label = L10n.t("widget.needsYou", Int64(needsYou))
    if isSmall {
      Text("\(needsYou)")
        .font(.caption2.bold())
        .monospacedDigit()
        .foregroundColor(renderingMode == .fullColor ? .white : .primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: height, height: height)
        .background(
          Circle()
            .fill(renderingMode == .fullColor ? Palette.primary : Color.secondary.opacity(0.24))
            .widgetAccentable()
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    } else {
      Text(label)
        .font(.caption.bold())
        .monospacedDigit()
        .foregroundColor(inkColor(Palette.primaryInk(colorScheme), renderingMode: renderingMode))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 8)
        .frame(height: height)
        .background(
          Capsule()
            .fill(softFill(Palette.primarySoft(colorScheme), renderingMode: renderingMode))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }
  }
}

struct HeaderRow: View {
  let balance: Int
  var needsYou: Int = 0
  var isSmall: Bool = false
  var height: CGFloat = 20

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      CoinPill(balance: balance, height: height)
      Spacer(minLength: 4)
      if needsYou > 0 {
        NeedsYouBadge(needsYou: needsYou, isSmall: isSmall, height: height)
      }
    }
    .frame(height: height)
  }
}

// MARK: - Pills, Rows & Banners

struct NowPlannedPill: View {
  let planned: QuickSnapshot.Upcoming
  var shortForm: Bool = false
  var height: CGFloat = 32
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  private var symbol: String {
    planned.type.lowercased() == "household" ? "house.fill" : "heart.fill"
  }

  private var pillText: String {
    if shortForm {
      return L10n.t("widget.nowPlannedShort", planned.title)
    } else {
      let endTime = planned.endsAt != nil ? formatShortTime(planned.endsAt!) : ""
      return L10n.t("widget.nowPlanned", planned.title, endTime)
    }
  }

  var body: some View {
    let ink = inkColor(Palette.primaryInk(colorScheme), renderingMode: renderingMode)
    HStack(spacing: 6) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(ink)
        .widgetAccentable()
      Text(pillText)
        .font(.caption.weight(.semibold))
        .foregroundColor(ink)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .truncationMode(.tail)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(
      Capsule()
        .fill(softFill(Palette.primarySoft(colorScheme), renderingMode: renderingMode))
    )
  }
}

struct TaskRow: View {
  let task: QuickSnapshot.Task
  var isSmall: Bool = false
  var rowHeight: CGFloat = 44
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  private var isHousehold: Bool {
    task.type.lowercased() == "household"
  }

  var body: some View {
    let btnSize: CGFloat = isSmall ? min(28, rowHeight - 6) : min(32, rowHeight - 4)
    let iconCircleSize: CGFloat = min(28, rowHeight - 6)
    let metaText = L10n.t("widget.row.meta", Int64(task.durationMinutes), Int64(task.coinValue))

    HStack(alignment: .center, spacing: isSmall ? 6 : 8) {
      if !isSmall {
        let soft = isHousehold ? Palette.warningSoft(colorScheme) : Palette.primarySoft(colorScheme)
        let ink = isHousehold ? Palette.warningInk(colorScheme) : Palette.primaryInk(colorScheme)
        let symbol = isHousehold ? "house.fill" : "heart.fill"

        ZStack {
          Circle()
            .fill(softFill(soft, renderingMode: renderingMode))
          Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(inkColor(ink, renderingMode: renderingMode))
            .widgetAccentable()
        }
        .frame(width: iconCircleSize, height: iconCircleSize)
      }

      VStack(alignment: .leading, spacing: 0) {
        Text(task.title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(Palette.widgetText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
          .truncationMode(.tail)
        Text(metaText)
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .truncationMode(.tail)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      HStack(spacing: 6) {
        Button(intent: StartTaskIntent(taskId: task.id)) {
          ZStack {
            Circle()
              .fill(renderingMode == .fullColor ? Palette.primary : Color.secondary.opacity(0.24))
              .widgetAccentable()
            Image(systemName: "play.fill")
              .font(.system(size: isSmall ? 11 : 12, weight: .bold))
              .foregroundColor(renderingMode == .fullColor ? .white : .primary)
          }
          .frame(width: btnSize, height: btnSize)
        }
        .buttonStyle(.plain)
        .frame(width: btnSize, height: btnSize)
        .contentShape(Circle())
        .accessibilityLabel(L10n.t("widget.a11y.start", task.title, Int64(task.durationMinutes)))

        Button(intent: DoneTaskIntent(taskId: task.id)) {
          ZStack {
            Circle()
              .fill(softFill(Palette.successSoft(colorScheme), renderingMode: renderingMode))
            Image(systemName: "checkmark")
              .font(.system(size: isSmall ? 11 : 12, weight: .bold))
              .foregroundColor(inkColor(Palette.successInk(colorScheme), renderingMode: renderingMode))
              .widgetAccentable()
          }
          .frame(width: btnSize, height: btnSize)
        }
        .buttonStyle(.plain)
        .frame(width: btnSize, height: btnSize)
        .contentShape(Circle())
        .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
      }
    }
    .padding(.horizontal, isSmall ? 8 : 10)
    .frame(maxWidth: .infinity)
    .frame(height: rowHeight)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(tileFill(colorScheme, renderingMode: renderingMode))
    )
  }
}

struct RunningBanner: View {
  let running: QuickSnapshot.Running
  var height: CGFloat = 52
  var isSmall: Bool = false
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  private var labelText: String {
    let typeLower = running.type.lowercased()
    let trimmed = running.title.trimmingCharacters(in: .whitespacesAndNewlines)
    let categoryTitle: String
    if typeLower == "household" {
      categoryTitle = L10n.t("widget.title.household")
    } else if typeLower == "care" || trimmed.isEmpty {
      categoryTitle = L10n.t("widget.title.care")
    } else {
      categoryTitle = running.title
    }
    return L10n.t("widget.running.label", categoryTitle)
  }

  var body: some View {
    let start = min(running.startedAt, Date())
    let end = start.addingTimeInterval(24 * 3600)
    let stopHeight: CGFloat = isSmall ? 28 : min(32, height - 12)

    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(labelText)
          .font(.caption2.weight(.medium))
          .foregroundColor(renderingMode == .fullColor ? Color.white.opacity(0.85) : .secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .truncationMode(.tail)
        Text(timerInterval: start...end, countsDown: false)
          .font(.system(size: isSmall ? 16 : 19, weight: .bold, design: .rounded))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .foregroundColor(renderingMode == .fullColor ? .white : .primary)
      }
      Spacer(minLength: 4)
      Button(intent: StopTaskIntent(activityId: running.id)) {
        HStack(spacing: 4) {
          Image(systemName: "stop.fill")
            .font(.system(size: 10, weight: .bold))
            .widgetAccentable()
          Text(L10n.t("widget.stop"))
            .font(.caption.weight(.bold))
            .lineLimit(1)
        }
        .foregroundColor(renderingMode == .fullColor ? Palette.primaryInk : .primary)
        .padding(.horizontal, isSmall ? 8 : 11)
        .frame(height: stopHeight)
        .background(
          Capsule()
            .fill(renderingMode == .fullColor ? Color.white : Color.secondary.opacity(0.24))
        )
      }
      .buttonStyle(.plain)
      .frame(height: stopHeight)
      .contentShape(Capsule())
      .accessibilityLabel(L10n.t("widget.stop"))
    }
    .padding(.horizontal, isSmall ? 10 : 12)
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(renderingMode == .fullColor ? Palette.primary : Color.secondary.opacity(0.18))
    )
  }
}

struct NowButtonsRow: View {
  var height: CGFloat = 36
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    HStack(spacing: 6) {
      Button(intent: StartNowIntent(type: "care")) {
        HStack(spacing: 5) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 13, weight: .semibold))
            .widgetAccentable()
          Text(L10n.t("widget.careNow"))
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundColor(inkColor(Palette.primaryInk(colorScheme), renderingMode: renderingMode))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
          Capsule()
            .fill(softFill(Palette.primarySoft(colorScheme), renderingMode: renderingMode))
        )
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .contentShape(Capsule())
      .accessibilityLabel(L10n.t("widget.careNow"))

      Button(intent: StartNowIntent(type: "household")) {
        HStack(spacing: 5) {
          Image(systemName: "house.fill")
            .font(.system(size: 13, weight: .semibold))
            .widgetAccentable()
          Text(L10n.t("widget.householdNow"))
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .foregroundColor(inkColor(Palette.warningInk(colorScheme), renderingMode: renderingMode))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background(
          Capsule()
            .fill(softFill(Palette.warningSoft(colorScheme), renderingMode: renderingMode))
        )
      }
      .buttonStyle(.plain)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .contentShape(Capsule())
      .accessibilityLabel(L10n.t("widget.householdNow"))
    }
    .frame(height: height)
  }
}

struct FeedbackChip: View {
  let action: LastAction
  let canUndo: Bool
  var height: CGFloat = 28
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var isFailure: Bool {
    action.kind == .failed
  }

  var chipText: String {
    switch action.kind {
    case .started: return L10n.t("widget.started")
    case .logged: return L10n.t("widget.logged")
    case .stopped: return L10n.t("widget.stopped")
    case .undone: return L10n.t("widget.undone")
    case .failed: return action.message ?? L10n.t("widget.error.generic")
    }
  }

  var body: some View {
    let soft = isFailure ? Palette.dangerSoft(colorScheme) : Palette.successSoft(colorScheme)
    let ink = isFailure ? Palette.dangerInk(colorScheme) : Palette.successInk(colorScheme)

    HStack(spacing: 6) {
      Image(systemName: isFailure ? "exclamationmark.circle.fill" : "checkmark")
        .font(.system(size: 11, weight: .bold))
        .foregroundColor(inkColor(ink, renderingMode: renderingMode))
        .widgetAccentable()
      Text(chipText)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundColor(inkColor(ink, renderingMode: renderingMode))
        .truncationMode(.tail)
      Spacer(minLength: 4)
      if canUndo, let ref = action.clientRef, !ref.isEmpty {
        Button(intent: UndoIntent(clientRef: ref)) {
          Text(L10n.t("widget.undo"))
            .font(.caption.weight(.bold))
            .foregroundColor(inkColor(Palette.primaryInk(colorScheme), renderingMode: renderingMode))
            .padding(.horizontal, 4)
            .frame(height: height - 4)
        }
        .buttonStyle(.plain)
        .frame(height: height - 4)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.t("widget.undo"))
        .widgetAccentable()
      }
    }
    .padding(.horizontal, 10)
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .background(
      Capsule()
        .fill(softFill(soft, renderingMode: renderingMode))
    )
  }
}

struct NoTasksTile: View {
  var height: CGFloat = 44
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    Text(L10n.t("widget.noTasks"))
      .font(.caption.weight(.medium))
      .foregroundColor(Palette.widgetSecondaryText(colorScheme))
      .multilineTextAlignment(.center)
      .lineLimit(2)
      .minimumScaleFactor(0.75)
      .padding(.horizontal, 10)
      .frame(maxWidth: .infinity)
      .frame(height: height)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(tileFill(colorScheme, renderingMode: renderingMode))
      )
  }
}

struct NextUpcomingRow: View {
  let next: QuickSnapshot.Upcoming
  var height: CGFloat = 16
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
      .font(.caption.weight(.medium))
      .foregroundColor(Palette.widgetSecondaryText(colorScheme))
      .lineLimit(1)
      .minimumScaleFactor(0.75)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(height: height)
  }
}

struct SeeAllTasksRow: View {
  var height: CGFloat = 20
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    let ink = inkColor(Palette.primaryInk(colorScheme), renderingMode: renderingMode)
    Link(destination: widgetDeepLinkURL) {
      HStack(spacing: 3) {
        Text(L10n.t("widget.allTasks"))
          .font(.caption.weight(.bold))
          .foregroundColor(ink)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .bold))
          .foregroundColor(ink)
          .widgetAccentable()
        Spacer(minLength: 0)
      }
      .frame(height: height)
    }
  }
}

// MARK: - Layout Computation

struct WidgetLayoutSpec {
  let gap: CGFloat
  let headerHeight: CGFloat
  let runningHeight: CGFloat
  let nowHeight: CGFloat
  let chipHeight: CGFloat
  let rowHeight: CGFloat
  let footerHeight: CGFloat
  let nextHeight: CGFloat
  let seeAllHeight: CGFloat
  let visibleTasks: Int
  let showFooter: Bool
  let showNext: Bool
  let showSeeAll: Bool
}

func computeWidgetLayout(
  family: WidgetFamily,
  availableHeight: CGFloat,
  taskCount: Int,
  hasRunning: Bool,
  hasNowPlanned: Bool,
  hasLastAction: Bool,
  hasNextUpcoming: Bool
) -> WidgetLayoutSpec {
  let gap: CGFloat = 6
  let fallbackH: CGFloat = (family == .systemLarge) ? 330 : 134
  let H: CGFloat = availableHeight > 40 ? availableHeight : fallbackH

  switch family {
  case .systemSmall:
    let headerH: CGFloat = 20
    if hasRunning {
      let runH: CGFloat = hasLastAction ? 44 : 50
      let chipH: CGFloat = hasLastAction ? 24 : 0
      let vis = min(1, taskCount)
      let rowH: CGFloat = hasLastAction ? 34 : 40
      return WidgetLayoutSpec(
        gap: gap,
        headerHeight: headerH,
        runningHeight: runH,
        nowHeight: 0,
        chipHeight: chipH,
        rowHeight: rowH,
        footerHeight: 0,
        nextHeight: 0,
        seeAllHeight: 0,
        visibleTasks: vis,
        showFooter: false,
        showNext: false,
        showSeeAll: false
      )
    } else {
      let extraBars = (hasNowPlanned ? 1 : 0) + (hasLastAction ? 1 : 0)
      let nowH: CGFloat = hasNowPlanned ? 26 : 0
      let chipH: CGFloat = hasLastAction ? 26 : 0
      let vis: Int
      let rowH: CGFloat
      if extraBars >= 2 {
        vis = min(1, taskCount)
        rowH = 40
      } else if extraBars == 1 {
        vis = min(2, taskCount)
        let rowsOrTile = max(1, vis)
        let rem = H - headerH - gap - 26 - CGFloat(rowsOrTile) * gap
        rowH = min(40, max(34, floor(rem / CGFloat(rowsOrTile))))
      } else {
        vis = min(2, taskCount)
        let rowsOrTile = max(1, vis)
        let rem = H - headerH - CGFloat(rowsOrTile) * gap - 8
        rowH = min(44, max(40, floor(rem / CGFloat(rowsOrTile))))
      }
      return WidgetLayoutSpec(
        gap: gap,
        headerHeight: headerH,
        runningHeight: 0,
        nowHeight: nowH,
        chipHeight: chipH,
        rowHeight: rowH,
        footerHeight: 0,
        nextHeight: 0,
        seeAllHeight: 0,
        visibleTasks: vis,
        showFooter: false,
        showNext: false,
        showSeeAll: false
      )
    }

  case .systemMedium:
    if hasRunning {
      let headerH: CGFloat = 18
      let runH: CGFloat = hasLastAction ? 44 : 50
      let chipH: CGFloat = hasLastAction ? 24 : 0
      let vis = min(1, taskCount)
      let used = headerH + gap + runH + (hasLastAction ? gap + chipH : 0) + gap
      let rowH = min(44, max(33, floor(H - used)))
      return WidgetLayoutSpec(
        gap: gap,
        headerHeight: headerH,
        runningHeight: runH,
        nowHeight: 0,
        chipHeight: chipH,
        rowHeight: rowH,
        footerHeight: 0,
        nextHeight: 0,
        seeAllHeight: 0,
        visibleTasks: vis,
        showFooter: false,
        showNext: false,
        showSeeAll: false
      )
    } else {
      let extraBars = (hasNowPlanned ? 1 : 0) + (hasLastAction ? 1 : 0)
      if extraBars == 0 {
        let vis = min(2, taskCount)
        let rowsOrTile = max(1, vis)
        if rowsOrTile == 1 {
          return WidgetLayoutSpec(
            gap: gap,
            headerHeight: 20,
            runningHeight: 0,
            nowHeight: 0,
            chipHeight: 0,
            rowHeight: 44,
            footerHeight: 36,
            nextHeight: 0,
            seeAllHeight: 0,
            visibleTasks: vis,
            showFooter: true,
            showNext: false,
            showSeeAll: false
          )
        } else {
          let totalGaps = 3 * gap
          let avail = H - totalGaps
          let headerH = min(22, max(18, floor(avail * 0.16)))
          let footerH = min(36, max(28, floor((avail - headerH) * 0.29)))
          let rowH = min(44, max(34, floor((avail - headerH - footerH) / 2)))
          return WidgetLayoutSpec(
            gap: gap,
            headerHeight: headerH,
            runningHeight: 0,
            nowHeight: 0,
            chipHeight: 0,
            rowHeight: rowH,
            footerHeight: footerH,
            nextHeight: 0,
            seeAllHeight: 0,
            visibleTasks: vis,
            showFooter: true,
            showNext: false,
            showSeeAll: false
          )
        }
      } else if extraBars == 1 {
        // Medium + Now line (or Chip): keep 2 task rows; drop the footer before dropping a row if they don't fit.
        let vis = min(2, taskCount)
        let rowsOrTile = max(1, vis)
        let headerH: CGFloat = 18
        let barH: CGFloat = 26
        let minWithFooter: CGFloat = headerH + barH + CGFloat(rowsOrTile) * 34 + 28 + CGFloat(rowsOrTile + 2) * gap
        let showFooter = H >= minWithFooter
        let footerH: CGFloat = showFooter ? 28 : 0
        let totalItems = 2 + rowsOrTile + (showFooter ? 1 : 0)
        let totalGaps = CGFloat(totalItems - 1) * gap
        let availForRows = H - headerH - barH - footerH - totalGaps
        let rowH = min(44, max(34, floor(availForRows / CGFloat(rowsOrTile))))
        return WidgetLayoutSpec(
          gap: gap,
          headerHeight: headerH,
          runningHeight: 0,
          nowHeight: hasNowPlanned ? barH : 0,
          chipHeight: hasLastAction ? barH : 0,
          rowHeight: rowH,
          footerHeight: footerH,
          nextHeight: 0,
          seeAllHeight: 0,
          visibleTasks: vis,
          showFooter: showFooter,
          showNext: false,
          showSeeAll: false
        )
      } else {
        // Both Now line and Chip present on medium
        let vis = min(1, taskCount)
        let headerH: CGFloat = 18
        let barH: CGFloat = 25
        let totalGaps = 3 * gap
        let rowH = min(44, max(34, floor(H - headerH - 2 * barH - totalGaps)))
        return WidgetLayoutSpec(
          gap: gap,
          headerHeight: headerH,
          runningHeight: 0,
          nowHeight: barH,
          chipHeight: barH,
          rowHeight: rowH,
          footerHeight: 0,
          nextHeight: 0,
          seeAllHeight: 0,
          visibleTasks: vis,
          showFooter: false,
          showNext: false,
          showSeeAll: false
        )
      }
    }

  default:
    // Large widget: up to 5 rows + footer + optional Next line
    let headerH: CGFloat = 20
    let showFooter = !hasRunning
    let footerH: CGFloat = showFooter ? 36 : 0
    let runH: CGFloat = hasRunning ? 54 : 0
    let nowH: CGFloat = (!hasRunning && hasNowPlanned) ? 32 : 0
    let chipH: CGFloat = hasLastAction ? 28 : 0
    let nextH: CGFloat = 16
    let seeAllH: CGFloat = 20

    var fixedH = headerH
    if hasRunning {
      fixedH += gap + runH
    } else if hasNowPlanned {
      fixedH += gap + nowH
    }
    if hasLastAction {
      fixedH += gap + chipH
    }
    if showFooter {
      fixedH += gap + footerH
    }

    let remForBody = H - fixedH
    let maxSlots = min(5, max(1, Int(floor((remForBody + 4) / (42 + gap)))))
    let vis = min(maxSlots, taskCount)
    let rowsOrTile = max(1, vis)

    var rowH: CGFloat = min(44, max(40, floor((remForBody - CGFloat(rowsOrTile) * gap) / CGFloat(rowsOrTile))))
    var usedByRows = CGFloat(rowsOrTile) * (rowH + gap)
    var spare = remForBody - usedByRows

    var showNext = false
    if hasNextUpcoming {
      if spare >= (nextH + gap) {
        showNext = true
        spare -= (nextH + gap)
      } else {
        let tryRowH = floor((remForBody - (nextH + gap) - CGFloat(rowsOrTile) * gap) / CGFloat(rowsOrTile))
        if tryRowH >= 41 {
          rowH = min(44, tryRowH)
          usedByRows = CGFloat(rowsOrTile) * (rowH + gap)
          spare = remForBody - usedByRows - (nextH + gap)
          showNext = true
        }
      }
    }

    let showSeeAll = (taskCount > 0 && taskCount < maxSlots && spare >= (seeAllH + gap))

    return WidgetLayoutSpec(
      gap: gap,
      headerHeight: headerH,
      runningHeight: runH,
      nowHeight: nowH,
      chipHeight: chipH,
      rowHeight: rowH,
      footerHeight: footerH,
      nextHeight: nextH,
      seeAllHeight: seeAllH,
      visibleTasks: vis,
      showFooter: showFooter,
      showNext: showNext,
      showSeeAll: showSeeAll
    )
  }
}

#if DEBUG
private func recordDebugHeight(_ height: CGFloat, key: String) -> Color {
  UserDefaults(suiteName: CareCoinsShared.appGroup)?.set(Double(height), forKey: key)
  return Color.clear
}
#endif

// MARK: - Family Views

struct ConnectedFamilyWidgetView: View {
  let family: WidgetFamily
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    let isSmall = (family == .systemSmall)
    let running = snapshot.running
    let hasRunning = running != nil
    let planned = hasRunning ? nil : snapshot.currentPlanned(now: entry.date)
    let nextTask = snapshot.nextUpcoming(now: entry.date)

    GeometryReader { proxy in
      let spec = computeWidgetLayout(
        family: family,
        availableHeight: proxy.size.height,
        taskCount: snapshot.tasks.count,
        hasRunning: hasRunning,
        hasNowPlanned: planned != nil,
        hasLastAction: entry.lastAction != nil,
        hasNextUpcoming: nextTask != nil
      )
      let visibleTasks = Array(snapshot.tasks.prefix(spec.visibleTasks))

      VStack(alignment: .leading, spacing: 0) {
        VStack(alignment: .leading, spacing: spec.gap) {
          HeaderRow(
            balance: snapshot.balance,
            needsYou: snapshot.needsYou,
            isSmall: isSmall,
            height: spec.headerHeight
          )

          if let running = running {
            RunningBanner(
              running: running,
              height: spec.runningHeight,
              isSmall: isSmall
            )
          } else if let planned = planned {
            NowPlannedPill(
              planned: planned,
              shortForm: isSmall,
              height: spec.nowHeight
            )
          }

          if let action = entry.lastAction {
            FeedbackChip(
              action: action,
              canUndo: entry.canUndo,
              height: spec.chipHeight
            )
          }

          if snapshot.tasks.isEmpty && !hasRunning {
            NoTasksTile(height: spec.rowHeight)
          } else {
            ForEach(visibleTasks) { task in
              TaskRow(
                task: task,
                isSmall: isSmall,
                rowHeight: spec.rowHeight
              )
            }
          }

          if spec.showNext, let nextTask = nextTask {
            NextUpcomingRow(next: nextTask, height: spec.nextHeight)
          }

          if spec.showSeeAll {
            SeeAllTasksRow(height: spec.seeAllHeight)
          }
        }
        #if DEBUG
        .background(
          GeometryReader { innerProxy in
            recordDebugHeight(innerProxy.size.height, key: "debug.widget.medium2RowHeight")
          }
        )
        #endif

        Spacer(minLength: spec.showFooter ? spec.gap : 0)

        if spec.showFooter {
          NowButtonsRow(height: spec.footerHeight)
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
      #if DEBUG
      .background(
         recordDebugHeight(proxy.size.height, key: "debug.widget.mediumHeight")
      )
      #endif
    }
  }
}

struct SmallWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    ConnectedFamilyWidgetView(family: .systemSmall, entry: entry, snapshot: snapshot)
  }
}

struct MediumWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    ConnectedFamilyWidgetView(family: .systemMedium, entry: entry, snapshot: snapshot)
  }
}

struct LargeWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    ConnectedFamilyWidgetView(family: .systemLarge, entry: entry, snapshot: snapshot)
  }
}

struct AccessoryRectangularTasksView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let running = snapshot.running {
        Text(running.title)
          .font(.headline)
          .lineLimit(1)
        Text(running.startedAt, style: .timer)
          .font(.body.monospacedDigit())
      } else if let planned = snapshot.currentPlanned(now: entry.date) {
        let endTime = planned.endsAt != nil ? formatShortTime(planned.endsAt!) : ""
        Text(L10n.t("widget.nowPlanned", planned.title, endTime))
          .font(.headline)
          .lineLimit(2)
      } else if let next = snapshot.nextUpcoming(now: entry.date) {
        Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
          .font(.headline)
          .lineLimit(2)
      } else {
        Text(L10n.t("widget.noTasks"))
          .font(.caption)
          .lineLimit(2)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct AccessoryInlineTasksView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot

  var body: some View {
    if let running = snapshot.running {
      Text("\(running.title) \(Text(running.startedAt, style: .timer))")
    } else if let planned = snapshot.currentPlanned(now: entry.date) {
      Text(L10n.t("widget.nowPlannedShort", planned.title))
    } else if let next = snapshot.nextUpcoming(now: entry.date) {
      Text(L10n.t("widget.next", next.title, formatShortTime(next.startsAt)))
    } else {
      Text(L10n.t("widget.noTasks"))
    }
  }
}

struct NotConnectedView: View {
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    let isSmall = (family == .systemSmall)
    VStack(spacing: isSmall ? 6 : 8) {
      CoinGlyph(size: isSmall ? 24 : 30)
      Text(L10n.t("widget.notConnected"))
        .font(.footnote.weight(.medium))
        .foregroundColor(Palette.widgetText(colorScheme))
        .multilineTextAlignment(.center)
        .lineLimit(isSmall ? 3 : 2)
        .minimumScaleFactor(0.75)
        .padding(.horizontal, 6)
      Link(destination: widgetDeepLinkURL) {
        Text(L10n.t("widget.openApp"))
          .font(.caption.weight(.bold))
          .foregroundColor(renderingMode == .fullColor ? .white : .primary)
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .padding(.horizontal, 14)
          .frame(height: 28)
          .background(
            Capsule()
              .fill(renderingMode == .fullColor ? Palette.primary : Color.secondary.opacity(0.24))
              .widgetAccentable()
          )
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, isSmall ? 10 : 14)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .fill(tileFill(colorScheme, renderingMode: renderingMode))
    )
    .widgetURL(widgetDeepLinkURL)
  }
}

struct EmptyTasksView: View {
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    let isSmall = (family == .systemSmall)
    VStack(alignment: .leading, spacing: 6) {
      HeaderRow(balance: 0, needsYou: 0, isSmall: isSmall, height: 20)
      NoTasksTile(height: 44)
      Spacer(minLength: 0)
      if !isSmall {
        NowButtonsRow(height: 32)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

// MARK: - QuickTasksEntryView & QuickTasksWidget

public struct QuickTasksEntryView: View {
  let entry: QuickEntry
  @Environment(\.widgetFamily) var family
  @Environment(\.colorScheme) var colorScheme

  public init(entry: QuickEntry) {
    self.entry = entry
  }

  private var isSystemHomeFamily: Bool {
    family == .systemSmall || family == .systemMedium || family == .systemLarge
  }

  public var body: some View {
    Group {
      switch entry.state {
      case .notConnected:
        NotConnectedView()
      case .empty:
        EmptyTasksView()
      case .ready(let snapshot):
        switch family {
        case .systemSmall:
          SmallWidgetView(entry: entry, snapshot: snapshot)
        case .systemMedium:
          MediumWidgetView(entry: entry, snapshot: snapshot)
        case .accessoryRectangular:
          AccessoryRectangularTasksView(entry: entry, snapshot: snapshot)
        case .accessoryInline:
          AccessoryInlineTasksView(entry: entry, snapshot: snapshot)
        default:
          LargeWidgetView(entry: entry, snapshot: snapshot)
        }
      }
    }
    .padding(isSystemHomeFamily ? 12 : 0)
    .dynamicTypeSize(...DynamicTypeSize.xLarge)
    .containerBackground(Palette.widgetBackground(colorScheme), for: .widget)
  }
}

public struct QuickTasksWidget: Widget {
  public let kind: String = "CareCoinsQuickTasks"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickProvider()) { entry in
      QuickTasksEntryView(entry: entry)
    }
    .contentMarginsDisabled()
    .configurationDisplayName(Text(L10n.t("widget.tasks.name")))
    .description(Text(L10n.t("widget.tasks.description")))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryInline])
  }
}

// MARK: - Previews

enum QuickWidgetPreviewSamples {
  static let now = Date()

  static let tasks: [QuickSnapshot.Task] = [
    QuickSnapshot.Task(id: "1", title: "Breakfast routine", type: "care", durationMinutes: 20, coinValue: 1),
    QuickSnapshot.Task(id: "2", title: "Kitchen tidy-up", type: "household", durationMinutes: 15, coinValue: 1),
    QuickSnapshot.Task(id: "3", title: "School drop-off", type: "care", durationMinutes: 30, coinValue: 2),
    QuickSnapshot.Task(id: "4", title: "Laundry fold", type: "household", durationMinutes: 25, coinValue: 1),
    QuickSnapshot.Task(id: "5", title: "Bedtime story", type: "care", durationMinutes: 20, coinValue: 1),
  ]

  static let nextUpcomingItem = QuickSnapshot.Upcoming(
    id: "u-next",
    title: "Dinner prep",
    type: "household",
    startsAt: now.addingTimeInterval(2 * 3600),
    endsAt: now.addingTimeInterval(2.5 * 3600),
    status: "planned"
  )

  static let currentPlannedItem = QuickSnapshot.Upcoming(
    id: "u-now",
    title: "Dinner prep",
    type: "household",
    startsAt: now.addingTimeInterval(-15 * 60),
    endsAt: now.addingTimeInterval(30 * 60),
    status: "planned"
  )

  static let idleSnapshot = QuickSnapshot(
    family: QuickSnapshot.Family(id: "1", name: "Family"),
    balance: 42,
    needsYou: 1,
    tasks: tasks,
    upcoming: [nextUpcomingItem],
    running: nil,
    serverTime: now
  )

  static let nowPlannedSnapshot = QuickSnapshot(
    family: QuickSnapshot.Family(id: "1", name: "Family"),
    balance: 42,
    needsYou: 1,
    tasks: tasks,
    upcoming: [currentPlannedItem, nextUpcomingItem],
    running: nil,
    serverTime: now
  )

  static let runningSnapshot = QuickSnapshot(
    family: QuickSnapshot.Family(id: "1", name: "Family"),
    balance: 42,
    needsYou: 1,
    tasks: tasks,
    upcoming: [nextUpcomingItem],
    running: QuickSnapshot.Running(
      id: "r-1",
      title: "Care",
      type: "care",
      startedAt: now.addingTimeInterval(-12 * 60 - 34),
      clientRef: "ref-run"
    ),
    serverTime: now
  )

  static let idleEntry = QuickEntry(date: now, state: .ready(idleSnapshot))
  static let nowLineEntry = QuickEntry(date: now, state: .ready(nowPlannedSnapshot))
  static let runningEntry = QuickEntry(date: now, state: .ready(runningSnapshot))
  static let chipEntry = QuickEntry(
    date: now,
    state: .ready(idleSnapshot),
    lastAction: LastAction(kind: .started, taskId: "1", clientRef: "ref-1", at: now),
    canUndo: true
  )
}

#Preview("Small", as: .systemSmall) {
  QuickTasksWidget()
} timeline: {
  QuickWidgetPreviewSamples.idleEntry
  QuickWidgetPreviewSamples.runningEntry
  QuickWidgetPreviewSamples.chipEntry
  QuickWidgetPreviewSamples.nowLineEntry
}

#Preview("Medium", as: .systemMedium) {
  QuickTasksWidget()
} timeline: {
  QuickWidgetPreviewSamples.idleEntry
  QuickWidgetPreviewSamples.runningEntry
  QuickWidgetPreviewSamples.chipEntry
  QuickWidgetPreviewSamples.nowLineEntry
}

#Preview("Large", as: .systemLarge) {
  QuickTasksWidget()
} timeline: {
  QuickWidgetPreviewSamples.idleEntry
  QuickWidgetPreviewSamples.runningEntry
  QuickWidgetPreviewSamples.chipEntry
  QuickWidgetPreviewSamples.nowLineEntry
}

struct QuickTasksWidget_Previews: PreviewProvider {
  static var previews: some View {
    let families: [(String, WidgetFamily)] = [
      ("Small", .systemSmall),
      ("Medium", .systemMedium),
      ("Large", .systemLarge),
    ]
    let states: [(String, QuickEntry)] = [
      ("Idle", QuickWidgetPreviewSamples.idleEntry),
      ("Running", QuickWidgetPreviewSamples.runningEntry),
      ("Chip", QuickWidgetPreviewSamples.chipEntry),
      ("NowLine", QuickWidgetPreviewSamples.nowLineEntry),
    ]
    let schemes: [(String, ColorScheme)] = [
      ("Light", .light),
      ("Dark", .dark),
    ]

    ForEach(families, id: \.0) { familyName, family in
      ForEach(states, id: \.0) { stateName, entry in
        ForEach(schemes, id: \.0) { schemeName, scheme in
          QuickTasksEntryView(entry: entry)
            .environment(\.colorScheme, scheme)
            .previewContext(WidgetPreviewContext(family: family))
            .previewDisplayName("\(familyName) · \(stateName) · \(schemeName)")
        }
      }
    }
  }
}
