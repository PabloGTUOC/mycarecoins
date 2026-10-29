#if canImport(WidgetKit) && canImport(AppIntents)
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
public struct StartCareNowControl: ControlWidget {
  public static let kind: String = "CareCoinsStartCareNow"

  public init() {}

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind) {
      ControlWidgetButton(action: StartNowIntent(type: "care")) {
        Label(L10n.t("widget.careNow"), systemImage: "heart.circle")
      }
    }
    .displayName("widget.careNow")
    .description("widget.control.careNow.description")
  }
}

@available(iOS 18.0, *)
public struct TopTaskControlValue {
  public var taskId: String
  public var label: String
  public var systemImage: String

  public init(taskId: String = "", label: String = "", systemImage: String = "heart.circle") {
    self.taskId = taskId
    self.label = label
    self.systemImage = systemImage
  }
}

@available(iOS 18.0, *)
public struct TopTaskControlValueProvider: ControlValueProvider {
  public var previewValue: TopTaskControlValue {
    TopTaskControlValue(
      taskId: "1",
      label: L10n.t("widget.control.logTop", "Task"),
      systemImage: "checkmark.circle"
    )
  }

  public init() {}

  public func currentValue() async throws -> TopTaskControlValue {
    guard let snapshot = SnapshotStore.load() else {
      return TopTaskControlValue(
        taskId: "",
        label: L10n.t("widget.notConnected"),
        systemImage: "heart.circle"
      )
    }
    if let first = snapshot.tasks.first {
      return TopTaskControlValue(
        taskId: first.id,
        label: L10n.t("widget.control.logTop", first.title),
        systemImage: "checkmark.circle"
      )
    }
    return TopTaskControlValue(
      taskId: "",
      label: L10n.t("widget.noTasks"),
      systemImage: "heart.circle"
    )
  }
}

@available(iOS 18.0, *)
public struct LogTopTaskControl: ControlWidget {
  public static let kind: String = "CareCoinsLogTopTask"

  public init() {}

  public var body: some ControlWidgetConfiguration {
    StaticControlConfiguration(kind: Self.kind, provider: TopTaskControlValueProvider()) { value in
      ControlWidgetButton(action: DoneTaskIntent(taskId: value.taskId)) {
        Label(value.label, systemImage: value.systemImage)
      }
    }
    .displayName("widget.control.logTop.name")
  }
}
#endif
