import SwiftUI
import WidgetKit

#if canImport(ActivityKit)
import ActivityKit

@available(iOS 17.0, *)
public struct QuickLiveActivityWidget: Widget {
  public init() {}

  public var body: some WidgetConfiguration {
    ActivityConfiguration(for: QuickActivityAttributes.self) { context in
      LockScreenLiveActivityView(context: context)
        .activityBackgroundTint(Palette.ink)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      let timerEnd = context.state.plannedEnd ?? context.state.startedAt.addingTimeInterval(4 * 3600)
      return DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Text(context.attributes.title)
            .font(.headline)
            .fontWeight(.semibold)
            .lineLimit(1)
            .foregroundColor(.white)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(timerInterval: context.state.startedAt...timerEnd, countsDown: false)
            .font(.headline)
            .monospacedDigit()
            .fontWeight(.bold)
            .foregroundColor(.white)
        }
        DynamicIslandExpandedRegion(.bottom) {
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
      } compactLeading: {
        Image(systemName: "timer")
          .foregroundColor(Palette.primary)
      } compactTrailing: {
        Text(timerInterval: context.state.startedAt...timerEnd, countsDown: false)
          .monospacedDigit()
          .frame(maxWidth: 52)
      } minimal: {
        Image(systemName: "timer")
          .foregroundColor(Palette.primary)
      }
    }
  }
}

@available(iOS 17.0, *)
private struct LockScreenLiveActivityView: View {
  let context: ActivityViewContext<QuickActivityAttributes>

  var body: some View {
    HStack(spacing: 12) {
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
    .padding(16)
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
