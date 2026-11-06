import SwiftUI
import WatchKit

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

public struct WatchRootView: View {
  @Environment(WatchStore.self) private var store

  public init() {}

  public var body: some View {
    NavigationStack {
      if !store.connected {
        WatchNotConnectedView()
      } else {
        WatchContentView()
      }
    }
  }
}

private struct WatchNotConnectedView: View {
  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Image(systemName: "applewatch.radiowaves.left.and.right")
          .font(.title)
          .foregroundColor(Palette.primary)
          .padding(.top, 8)
        Text(L10n.t("watch.connect.title"))
          .font(.headline)
          .multilineTextAlignment(.center)
          .foregroundColor(.white)
        Text(L10n.t("watch.connect.body"))
          .font(.footnote)
          .multilineTextAlignment(.center)
          .foregroundColor(Palette.inkMuted)
      }
      .padding(.horizontal)
    }
  }
}

private enum NowType: String, Identifiable {
  case care
  case household
  var id: String { rawValue }
}

private struct WatchContentView: View {
  @Environment(WatchStore.self) private var store
  @State private var selectedTask: QuickSnapshot.Task?
  @State private var activeNowType: NowType?
  @State private var showStopConfirm = false

  var body: some View {
    List {
      // 6. Feedback chip at the top
      TimelineView(.periodic(from: .now, by: 1.0)) { timeline in
        if let action = store.lastAction,
           timeline.date.timeIntervalSince(action.at) <= SnapshotStore.undoWindow {
          WatchFeedbackRow(action: action, canUndo: store.canUndo) {
            Task { await store.undo() }
          }
        }
      }

      // 2. Running task
      if let running = store.snapshot?.running {
        Section {
          VStack(alignment: .leading, spacing: 6) {
            Text(running.title)
              .font(.headline)
              .foregroundColor(.white)
              .lineLimit(2)
            HStack {
              Text(running.startedAt, style: .timer)
                .font(.system(.body, design: .rounded).monospacedDigit())
                .foregroundColor(Palette.dangerOnDark)
              Spacer()
              Button(L10n.t("widget.stop")) {
                showStopConfirm = true
              }
              .buttonStyle(.borderedProminent)
              .tint(Palette.danger)
              .accessibilityLabel(L10n.t("widget.stop"))
            }
          }
        }
      }

      // 4. "Now" row
      Section(L10n.t("watch.now")) {
        HStack(spacing: 8) {
          Button {
            activeNowType = .care
          } label: {
            Text(L10n.t("widget.careNow"))
              .font(.footnote.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(Palette.primary)

          Button {
            activeNowType = .household
          } label: {
            Text(L10n.t("widget.householdNow"))
              .font(.footnote.weight(.medium))
              .lineLimit(1)
              .minimumScaleFactor(0.75)
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.bordered)
          .tint(Palette.primary)
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
      }

      // 5. Your tasks
      if let tasks = store.snapshot?.tasks, !tasks.isEmpty {
        Section(L10n.t("watch.tasks")) {
          ForEach(tasks) { task in
            let isPending = store.pending.contains { $0.taskId == task.id }
            Button {
              selectedTask = task
            } label: {
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundColor(.white)
                    .lineLimit(2)
                  if isPending {
                    HStack(spacing: 4) {
                      Image(systemName: "clock")
                      Text(L10n.t("watch.pending"))
                    }
                    .font(.caption2)
                    .foregroundColor(Palette.warning)
                  } else {
                    Text("\(task.durationMinutes) min")
                      .font(.caption2)
                      .foregroundColor(Palette.inkMuted)
                  }
                }
                Spacer()
              }
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }

      Section {
        Toggle(isOn: Binding(
          get: { store.remindersEnabled },
          set: { store.remindersEnabled = $0 }
        )) {
          Text(L10n.t("watch.reminders.toggle"))
            .font(.footnote)
        }
      }
    }
    .refreshable {
      await store.refresh()
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        if let balance = store.snapshot?.balance {
          WatchCoinPill(balance: balance)
        }
      }
    }
    .confirmationDialog(
      store.snapshot?.running?.title ?? "",
      isPresented: $showStopConfirm,
      titleVisibility: .visible
    ) {
      if let running = store.snapshot?.running {
        Button(L10n.t("widget.stop"), role: .destructive) {
          Task { await store.stop(runningId: running.id) }
        }
      }
    }
    .sheet(item: $activeNowType) { nowType in
      StartNowSheet(type: nowType.rawValue) { customTitle in
        Task { await store.startNow(type: nowType.rawValue, title: customTitle) }
      }
    }
    .sheet(item: $selectedTask) { task in
      TaskConfirmSheet(
        task: task,
        onStart: {
          Task { await store.start(task: task) }
        },
        onDone: {
          Task { await store.done(task: task) }
        }
      )
    }
  }
}

private struct WatchFeedbackRow: View {
  let action: LastAction
  let canUndo: Bool
  let onUndo: () -> Void

  private var isFailure: Bool {
    action.kind == .failed
  }

  private var message: String {
    switch action.kind {
    case .started: return L10n.t("widget.started")
    case .logged: return L10n.t("widget.logged")
    case .stopped: return L10n.t("widget.stopped")
    case .undone: return L10n.t("widget.undone")
    case .failed: return action.message ?? L10n.t("widget.error.generic")
    }
  }

  var body: some View {
    Section {
      HStack(spacing: 8) {
        Text(message)
          .font(.footnote.weight(.medium))
          .foregroundColor(isFailure ? Palette.dangerOnDark : Palette.successOnDark)
          .lineLimit(2)
          .minimumScaleFactor(0.8)
        Spacer()
        if canUndo {
          Button(L10n.t("widget.undo")) {
            onUndo()
          }
          .font(.caption2.bold())
          .buttonStyle(.borderedProminent)
          .tint(Palette.primary)
        }
      }
    }
  }
}

private struct WatchCoinPill: View {
  let balance: Int

  var body: some View {
    HStack(spacing: 3) {
      Text("\(balance)")
        .font(.system(.caption2, design: .rounded).bold())
        .foregroundColor(Palette.coinInk)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
      Circle()
        .fill(Palette.coin)
        .frame(width: 5, height: 5)
    }
    .padding(.horizontal, 6)
    .frame(height: 16)
    .background(Capsule().fill(Palette.coinSoft))
    .privacySensitive()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(L10n.t("widget.a11y.balance", Int64(balance)))
  }
}

private struct StartNowSheet: View {
  let type: String
  let onStart: (String) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var title: String = ""

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text(L10n.t("widget.title.\(type)"))
          .font(.headline)
          .foregroundColor(.white)

        TextField(L10n.t("watch.titleOptional"), text: $title)
          .textContentType(.none)

        Button(L10n.t("widget.start")) {
          onStart(title.trimmingCharacters(in: .whitespacesAndNewlines))
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .tint(Palette.primary)
        .accessibilityLabel(
          L10n.t(
            "widget.a11y.start",
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
              ? L10n.t("widget.title.\(type)")
              : title.trimmingCharacters(in: .whitespacesAndNewlines)
          )
        )
      }
      .padding()
    }
  }
}

private struct TaskConfirmSheet: View {
  let task: QuickSnapshot.Task
  let onStart: () -> Void
  let onDone: () -> Void
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    ScrollView {
      VStack(spacing: 12) {
        Text(task.title)
          .font(.headline)
          .multilineTextAlignment(.center)
          .foregroundColor(.white)

        let now = Date()
        let end = now.addingTimeInterval(Double(task.durationMinutes) * 60)
        Text(L10n.t("watch.addsToCalendar", formatShortTime(now), formatShortTime(end)))
          .font(.caption2)
          .foregroundColor(Palette.inkMuted)
          .multilineTextAlignment(.center)

        HStack(spacing: 8) {
          Text("\(task.durationMinutes) min")
            .font(.footnote)
            .foregroundColor(Palette.inkMuted)

          Text("•")
            .font(.footnote)
            .foregroundColor(Palette.inkMuted)

          Text(L10n.t("watch.coins", CInt(task.coinValue)))
            .font(.system(.footnote, design: .rounded).weight(.semibold))
            .foregroundColor(Palette.coin)
        }

        VStack(spacing: 8) {
          Button(L10n.t("widget.start")) {
            onStart()
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .tint(Palette.primary)
          .accessibilityLabel(L10n.t("widget.a11y.start", task.title))

          Button(L10n.t("widget.done")) {
            onDone()
            dismiss()
          }
          .buttonStyle(.borderedProminent)
          .tint(Palette.success)
          .accessibilityLabel(L10n.t("widget.a11y.done", task.title))
        }
        .padding(.top, 4)
      }
      .padding()
    }
  }
}
