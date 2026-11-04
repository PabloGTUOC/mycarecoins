import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
private func isConfirmState(context: ActivityViewContext<QuickActivityAttributes>) -> Bool {
  guard context.attributes.kind == "started" else { return false }
  if context.isStale { return true }
  if let plannedEnd = context.state.plannedEnd, Date() >= plannedEnd {
    return true
  }
  return false
}

@available(iOS 17.0, *)
private func timerRange(for context: ActivityViewContext<QuickActivityAttributes>) -> ClosedRange<Date> {
  let end = context.state.plannedEnd ?? context.state.startedAt.addingTimeInterval(15 * 60)
  if end <= context.state.startedAt {
    return context.state.startedAt...context.state.startedAt.addingTimeInterval(1)
  }
  return context.state.startedAt...end
}

@available(iOS 17.0, *)
public struct QuickLiveActivityWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    ActivityConfiguration(for: QuickActivityAttributes.self) { context in
      LockScreenLiveActivityView(context: context)
        .activityBackgroundTint(Palette.ink)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let confirm = isConfirmState(context: context)
      let timerEnd = context.state.plannedEnd ?? context.state.startedAt.addingTimeInterval(4 * 3600)
      let isStarted = context.attributes.kind == "started"
      let range = isStarted ? timerRange(for: context) : (context.state.startedAt...timerEnd)

      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          if confirm {
            Text(L10n.t("widget.didYouFinish", context.attributes.title))
              .font(.headline)
              .fontWeight(.semibold)
              .lineLimit(2)
              .foregroundColor(.white)
          } else {
            Text(context.attributes.title)
              .font(.headline)
              .fontWeight(.semibold)
              .lineLimit(1)
              .foregroundColor(.white)
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          if !confirm {
            Text(timerInterval: range, countsDown: isStarted)
              .font(.headline)
              .monospacedDigit()
              .fontWeight(.bold)
              .foregroundColor(.white)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          if confirm {
            HStack(spacing: 12) {
              Spacer()
              LiveActivityConfirmButtons(activityId: context.attributes.activityId)
              Spacer()
            }
            .padding(.top, 4)
          } else if isStarted {
            VStack(spacing: 6) {
              ProgressView(timerInterval: range, countsDown: true)
                .labelsHidden()
                .tint(Palette.success)
              HStack {
                Spacer()
                LiveActivityActionButton(
                  kind: context.attributes.kind,
                  activityId: context.attributes.activityId,
                  stopped: context.state.stopped
                )
                Spacer()
              }
            }
            .padding(.top, 4)
          } else {
            HStack {
              Spacer()
              LiveActivityActionButton(
                kind: context.attributes.kind,
                activityId: context.attributes.activityId,
                stopped: context.state.stopped
              )
              Spacer()
            }
            .padding(.top, 4)
          }
        }
      } compactLeading: {
        Image(systemName: confirm ? "questionmark.circle" : "timer")
          .foregroundColor(confirm ? Palette.warning : (isStarted ? Palette.success : Palette.primary))
      } compactTrailing: {
        if confirm {
          Image(systemName: "questionmark")
            .foregroundColor(Palette.warning)
        } else {
          Text(timerInterval: range, countsDown: isStarted)
            .monospacedDigit()
            .frame(maxWidth: 52)
        }
      } minimal: {
        Image(systemName: confirm ? "questionmark.circle" : "timer")
          .foregroundColor(confirm ? Palette.warning : (isStarted ? Palette.success : Palette.primary))
      }
    }
  }
}

@available(iOS 17.0, *)
private struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<QuickActivityAttributes>

  var body: some View {
    HStack(spacing: 12) {
      if isConfirmState(context: context) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L10n.t("widget.didYouFinish", context.attributes.title))
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(2)
            .foregroundColor(.white)
        }

        Spacer(minLength: 8)

        LiveActivityConfirmButtons(activityId: context.attributes.activityId)
      } else if context.attributes.kind == "started" {
        let range = timerRange(for: context)
        VStack(alignment: .leading, spacing: 4) {
          Text(context.attributes.title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundColor(.white)

          Text(timerInterval: range, countsDown: true)
            .font(.title2)
            .monospacedDigit()
            .fontWeight(.bold)
            .foregroundColor(.white)

          ProgressView(timerInterval: range, countsDown: true)
            .labelsHidden()
            .tint(Palette.success)
        }

        Spacer(minLength: 8)

        LiveActivityActionButton(
          kind: context.attributes.kind,
          activityId: context.attributes.activityId,
          stopped: context.state.stopped
        )
      } else {
        VStack(alignment: .leading, spacing: 2) {
          Text(context.attributes.title)
            .font(.subheadline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundColor(.white)

          let timerEnd = context.state.plannedEnd ?? context.state.startedAt.addingTimeInterval(4 * 3600)
          Text(timerInterval: context.state.startedAt...timerEnd, countsDown: false)
            .font(.title2)
            .monospacedDigit()
            .fontWeight(.bold)
            .foregroundColor(.white)
        }

        Spacer(minLength: 8)

        LiveActivityActionButton(
          kind: context.attributes.kind,
          activityId: context.attributes.activityId,
          stopped: context.state.stopped
        )
      }
    }
    .padding(16)
  }
}

@available(iOS 17.0, *)
private struct LiveActivityConfirmButtons: View {
  let activityId: String

  var body: some View {
    HStack(spacing: 8) {
      Button(intent: FinishTaskIntent(activityId: activityId)) {
        Text(L10n.t("widget.done"))
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(Palette.success)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)

      Button(intent: CancelTaskIntent(activityId: activityId)) {
        Text(L10n.t("widget.notDone"))
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(Palette.dangerOnDark)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .overlay(
            Capsule().stroke(Palette.dangerOnDark, lineWidth: 1)
          )
      }
      .buttonStyle(.plain)
    }
  }
}

@available(iOS 17.0, *)
private struct LiveActivityActionButton: View {
  let kind: String
  let activityId: String
  let stopped: Bool

  var body: some View {
    if stopped {
      Text(L10n.t(kind == "started" ? "widget.logged" : "widget.stopped"))
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundColor(Palette.inkMuted)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    } else if kind == "started" {
      Button(intent: FinishTaskIntent(activityId: activityId)) {
        Text(L10n.t("widget.done"))
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Palette.success)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    } else {
      Button(intent: StopTaskIntent(activityId: activityId)) {
        Text(L10n.t("widget.stop"))
          .font(.subheadline)
          .fontWeight(.semibold)
          .foregroundColor(.white)
          .padding(.horizontal, 16)
          .padding(.vertical, 8)
          .background(Palette.danger)
          .clipShape(Capsule())
      }
      .buttonStyle(.plain)
    }
  }
}
#endif
