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

struct CoinPill: View {
  let balance: Int
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    HStack(spacing: 3) {
      Text("\(balance)")
        .font(.caption2.bold())
        .foregroundColor(renderingMode == .accented ? .primary : Palette.coinInk)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Circle()
        .fill(renderingMode == .accented ? Color.primary : Palette.coin)
        .frame(width: 5, height: 5)
    }
    .padding(.horizontal, 6)
    .frame(height: 14)
    .background(
      Group {
        if renderingMode != .accented {
          Capsule().fill(Palette.coinSoft)
        } else {
          Capsule().stroke(Color.primary.opacity(0.3), lineWidth: 1)
        }
      }
    )
    .privacySensitive()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.t("widget.a11y.balance", Int64(balance)))
    .widgetAccentable(renderingMode == .accented)
  }
}

struct HeaderRow: View {
  let familyName: String?
  let balance: Int
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    HStack(alignment: .center) {
      if let familyName = familyName, !familyName.isEmpty {
        Text(familyName)
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
      }
      Spacer()
      CoinPill(balance: balance)
    }
    .frame(height: 14)
  }
}

struct TaskRow: View {
  let task: QuickSnapshot.Task
  let startedTask: QuickSnapshot.Upcoming?
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var isRunningThisTask: Bool {
    guard let started = startedTask else { return false }
    return started.title == task.title && started.type == task.type
  }

  var body: some View {
    HStack(alignment: .center, spacing: 8) {
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(task.title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(Palette.widgetText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .truncationMode(.tail)
        Text("\(task.durationMinutes) min")
          .font(.caption2)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .layoutPriority(1)
      }
      .frame(height: 30)
      Spacer(minLength: 4)

      if isRunningThisTask, let started = startedTask {
        Button(intent: FinishTaskIntent(activityId: started.id)) {
          Text(L10n.t("widget.done"))
            .font(.caption.weight(.semibold))
            .foregroundColor(renderingMode == .accented ? .primary : .white)
            .padding(.horizontal, 10)
            .padding(.vertical, 2)
            .frame(height: 26)
            .background(
              Capsule()
                .fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Palette.success)
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .frame(height: 26)
        .contentShape(Rectangle())
        .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
        .widgetAccentable(renderingMode == .accented)
      } else {
        HStack(spacing: 8) {
          Button(intent: StartTaskIntent(taskId: task.id)) {
            Text(L10n.t("widget.start"))
              .font(.caption.weight(.semibold))
              .foregroundColor(renderingMode == .accented ? .primary : .white)
              .padding(.horizontal, 10)
              .padding(.vertical, 2)
              .frame(height: 26)
              .background(
                Capsule()
                  .fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Palette.primary)
              )
          }
          .buttonStyle(.plain)
          .padding(.vertical, 2)
          .frame(height: 26)
          .contentShape(Rectangle())
          .accessibilityLabel(L10n.t("widget.a11y.start", task.title, Int64(task.durationMinutes)))
          .widgetAccentable(renderingMode == .accented)

          Button(intent: DoneTaskIntent(taskId: task.id)) {
            Text(L10n.t("widget.done"))
              .font(.caption.weight(.semibold))
              .foregroundColor(renderingMode == .accented ? .primary : Palette.primaryInk)
              .padding(.horizontal, 10)
              .padding(.vertical, 2)
              .frame(height: 26)
              .background(
                Capsule()
                  .fill(renderingMode == .accented ? Color.clear : Palette.primarySoft)
              )
          }
          .buttonStyle(.plain)
          .padding(.vertical, 2)
          .frame(height: 26)
          .contentShape(Rectangle())
          .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
          .widgetAccentable(renderingMode == .accented)
        }
        .frame(height: 26)
      }
    }
    .frame(height: 30)
  }
}

struct RunningBanner: View {
  let running: QuickSnapshot.Running
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(L10n.t("widget.running", running.title))
          .font(.caption2.weight(.medium))
          .foregroundColor(Palette.widgetText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .truncationMode(.tail)
        Text(running.startedAt, style: .timer)
          .font(.system(.subheadline, design: .rounded).weight(.bold))
          .monospacedDigit()
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .foregroundColor(renderingMode == .accented ? .primary : Palette.danger)
      }
      Spacer(minLength: 4)
      Button(intent: StopTaskIntent(activityId: running.id)) {
        Text(L10n.t("widget.stop"))
          .font(.caption.weight(.semibold))
          .foregroundColor(renderingMode == .accented ? .primary : .white)
          .padding(.horizontal, 10)
          .padding(.vertical, 2)
          .frame(height: 26)
          .background(
            Capsule()
              .fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Palette.danger)
          )
      }
      .buttonStyle(.plain)
      .padding(.vertical, 2)
      .frame(height: 26)
      .contentShape(Rectangle())
      .accessibilityLabel(L10n.t("widget.stop"))
      .widgetAccentable(renderingMode == .accented)
    }
    .padding(.horizontal, 8)
    .frame(height: 30)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(renderingMode == .accented ? Color.clear : Palette.dangerSoft.opacity(0.5))
    )
  }
}

struct NowButtonsRow: View {
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    HStack(spacing: 8) {
      Button(intent: StartNowIntent(type: "care")) {
        Text(L10n.t("widget.careNow"))
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .foregroundColor(renderingMode == .accented ? .primary : Palette.primary)
          .padding(.vertical, 2)
          .frame(maxWidth: .infinity)
          .frame(height: 26)
          .overlay(
            Capsule().stroke(renderingMode == .accented ? Color.primary : Palette.primary, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .padding(.vertical, 2)
      .frame(maxWidth: .infinity)
      .frame(height: 26)
      .contentShape(Rectangle())
      .widgetAccentable(renderingMode == .accented)

      Button(intent: StartNowIntent(type: "household")) {
        Text(L10n.t("widget.householdNow"))
          .font(.caption.weight(.medium))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .foregroundColor(renderingMode == .accented ? .primary : Palette.primary)
          .padding(.vertical, 2)
          .frame(maxWidth: .infinity)
          .frame(height: 26)
          .overlay(
            Capsule().stroke(renderingMode == .accented ? Color.primary : Palette.primary, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
      .padding(.vertical, 2)
      .frame(maxWidth: .infinity)
      .frame(height: 26)
      .contentShape(Rectangle())
      .widgetAccentable(renderingMode == .accented)
    }
    .frame(height: 26)
  }
}

struct FeedbackChip: View {
  let action: LastAction
  let canUndo: Bool
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
    HStack(spacing: 6) {
      Text(chipText)
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundColor(renderingMode == .accented ? .primary : (isFailure ? Palette.dangerInk : Palette.successInk))
        .truncationMode(.tail)
      Spacer(minLength: 4)
      if canUndo, let ref = action.clientRef, !ref.isEmpty {
        Button(intent: UndoIntent(clientRef: ref)) {
          Text(L10n.t("widget.undo"))
            .font(.caption2.weight(.bold))
            .foregroundColor(renderingMode == .accented ? .primary : Palette.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .frame(height: 22)
            .background(
              Capsule().fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Color.white)
            )
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
        .frame(height: 22)
        .contentShape(Rectangle())
        .widgetAccentable(renderingMode == .accented)
      }
    }
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(
      RoundedRectangle(cornerRadius: 10)
        .fill(renderingMode == .accented ? Color.clear : (isFailure ? Palette.dangerSoft : Palette.successSoft))
    )
  }
}

// MARK: - Family Views

struct SmallWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.widgetRenderingMode) var renderingMode

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Spacer()
        CoinPill(balance: snapshot.balance)
      }

      if let running = snapshot.running {
        RunningBanner(running: running)
      } else if let task = snapshot.tasks.first {
        Text(task.title)
          .font(.subheadline.weight(.semibold))
          .foregroundColor(Palette.widgetText(colorScheme))
          .lineLimit(2)
          .minimumScaleFactor(0.8)
          .frame(maxWidth: .infinity, alignment: .leading)

        if let action = entry.lastAction {
          FeedbackChip(action: action, canUndo: entry.canUndo)
        } else {
          let started = snapshot.startedTask(now: entry.date)
          let isRunningThisTask = started?.title == task.title && started?.type == task.type

          if isRunningThisTask, let started = started {
            Button(intent: FinishTaskIntent(activityId: started.id)) {
              Text(L10n.t("widget.done"))
                .font(.caption.weight(.semibold))
                .foregroundColor(renderingMode == .accented ? .primary : .white)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                  Capsule()
                    .fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Palette.success)
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
            .controlSize(.small)
            .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
            .widgetAccentable(renderingMode == .accented)
          } else {
            HStack(spacing: 8) {
              Button(intent: StartTaskIntent(taskId: task.id)) {
                Text(L10n.t("widget.start"))
                  .font(.caption.weight(.semibold))
                  .foregroundColor(renderingMode == .accented ? .primary : .white)
                  .frame(maxWidth: .infinity)
                  .frame(height: 30)
                  .background(
                    Capsule()
                      .fill(renderingMode == .accented ? Color.primary.opacity(0.2) : Palette.primary)
                  )
              }
              .buttonStyle(.plain)
              .frame(maxWidth: .infinity)
              .frame(height: 30)
              .contentShape(Rectangle())
              .controlSize(.small)
              .accessibilityLabel(L10n.t("widget.a11y.start", task.title, Int64(task.durationMinutes)))
              .widgetAccentable(renderingMode == .accented)

              Button(intent: DoneTaskIntent(taskId: task.id)) {
                Text(L10n.t("widget.done"))
                  .font(.caption.weight(.semibold))
                  .foregroundColor(renderingMode == .accented ? .primary : Palette.primaryInk)
                  .frame(maxWidth: .infinity)
                  .frame(height: 30)
                  .background(
                    Capsule()
                      .fill(renderingMode == .accented ? Color.clear : Palette.primarySoft)
                  )
              }
              .buttonStyle(.plain)
              .frame(maxWidth: .infinity)
              .frame(height: 30)
              .contentShape(Rectangle())
              .controlSize(.small)
              .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
              .widgetAccentable(renderingMode == .accented)
            }
            .frame(height: 30)
          }
        }
      } else {
        Text(L10n.t("widget.noTasks"))
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .frame(maxWidth: .infinity, alignment: .center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

#if DEBUG
private func recordDebugHeight(_ height: CGFloat, key: String) -> Color {
  UserDefaults(suiteName: CareCoinsShared.appGroup)?.set(Double(height), forKey: key)
  return Color.clear
}
#endif

struct MediumWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot
  @Environment(\.colorScheme) var colorScheme

  var maxTasks: Int {
    snapshot.running != nil ? 1 : 2
  }

  var body: some View {
    ViewThatFits(in: .vertical) {
      layout(tasksToShow: maxTasks)
        #if DEBUG
        .background(
          GeometryReader { proxy in
            recordDebugHeight(proxy.size.height, key: "debug.widget.medium2RowHeight")
          }
        )
        #endif
      if maxTasks >= 2 { layout(tasksToShow: 1) }
      layout(tasksToShow: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    #if DEBUG
    .background(
      GeometryReader { proxy in
        recordDebugHeight(proxy.size.height, key: "debug.widget.mediumHeight")
      }
      .hidden()
    )
    #endif
  }

  @ViewBuilder
  private func layout(tasksToShow: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HeaderRow(familyName: snapshot.family.name, balance: snapshot.balance)

      if let running = snapshot.running {
        RunningBanner(running: running)
      }

      let visibleTasks = Array(snapshot.tasks.prefix(tasksToShow))
      if snapshot.tasks.isEmpty && snapshot.running == nil {
        Text(L10n.t("widget.noTasks"))
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 4)
      } else {
        ForEach(visibleTasks) { task in
          TaskRow(task: task, startedTask: snapshot.startedTask(now: entry.date))
        }
      }

      if let action = entry.lastAction {
        FeedbackChip(action: action, canUndo: entry.canUndo)
      } else {
        NowButtonsRow()
      }
    }
  }
}

struct LargeWidgetView: View {
  let entry: QuickEntry
  let snapshot: QuickSnapshot
  @Environment(\.colorScheme) var colorScheme

  var maxTasks: Int {
    snapshot.running != nil ? 4 : 5
  }

  var body: some View {
    ViewThatFits(in: .vertical) {
      layout(tasksToShow: maxTasks)
      if maxTasks >= 5 { layout(tasksToShow: 4) }
      if maxTasks >= 4 { layout(tasksToShow: 3) }
      if maxTasks >= 3 { layout(tasksToShow: 2) }
      if maxTasks >= 2 { layout(tasksToShow: 1) }
      layout(tasksToShow: 0)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }

  @ViewBuilder
  private func layout(tasksToShow: Int) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HeaderRow(familyName: snapshot.family.name, balance: snapshot.balance)

      if let running = snapshot.running {
        RunningBanner(running: running)
      }

      let visibleTasks = Array(snapshot.tasks.prefix(tasksToShow))
      if snapshot.tasks.isEmpty && snapshot.running == nil {
        Text(L10n.t("widget.noTasks"))
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 4)
      } else {
        ForEach(visibleTasks) { task in
          TaskRow(task: task, startedTask: snapshot.startedTask(now: entry.date))
        }
      }

      NowButtonsRow()

      if let action = entry.lastAction {
        FeedbackChip(action: action, canUndo: entry.canUndo)
      } else if let nextTask = snapshot.nextUpcoming(now: entry.date) {
        Text(L10n.t("widget.next", nextTask.title, formatShortTime(nextTask.startsAt)))
          .font(.caption)
          .foregroundColor(Palette.widgetSecondaryText(colorScheme))
          .lineLimit(1)
          .minimumScaleFactor(0.75)
          .frame(height: 14)
      }
    }
  }
}

struct NotConnectedView: View {
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    VStack(spacing: 8) {
      Image(systemName: "link.badge.plus")
        .font(.title2)
        .foregroundColor(Palette.primary)
      Text(L10n.t("widget.notConnected"))
        .font(.footnote)
        .foregroundColor(Palette.primary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

struct EmptyTasksView: View {
  @Environment(\.colorScheme) var colorScheme

  var body: some View {
    VStack(spacing: 8) {
      Text(L10n.t("widget.noTasks"))
        .font(.footnote)
        .foregroundColor(Palette.widgetSecondaryText(colorScheme))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
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

  public var body: some View {
    switch entry.state {
    case .notConnected:
      NotConnectedView()
        .containerBackground(Palette.widgetBackground(colorScheme), for: .widget)
    case .empty:
      EmptyTasksView()
        .containerBackground(Palette.widgetBackground(colorScheme), for: .widget)
    case .ready(let snapshot):
      Group {
        switch family {
        case .systemSmall:
          SmallWidgetView(entry: entry, snapshot: snapshot)
        case .systemMedium:
          MediumWidgetView(entry: entry, snapshot: snapshot)
        default:
          LargeWidgetView(entry: entry, snapshot: snapshot)
        }
      }
      .containerBackground(Palette.widgetBackground(colorScheme), for: .widget)
    }
  }
}

public struct QuickTasksWidget: Widget {
  public let kind: String = "CareCoinsQuickTasks"

  public init() {}

  public var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: QuickProvider()) { entry in
      QuickTasksEntryView(entry: entry)
    }
    .configurationDisplayName(Text(L10n.t("widget.tasks.name")))
    .description(Text(L10n.t("widget.tasks.description")))
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
