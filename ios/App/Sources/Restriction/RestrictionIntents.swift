import AppIntents
import Foundation
import RestrictionCore

// 気になったときに、アプリを開かずにプリセットで集中セッションを始める(D-25)。
// ショートカット・Siri・Spotlight・アクションボタン・コントロールセンター(ショートカット経由)から使える。
// アプリの中で動くので、拡張や、Apple の追加の許可は要らない

/// 集中セッションのプリセット(ショートカットで選ぶ)
struct FocusPresetEntity: AppEntity {
  static var typeDisplayRepresentation: TypeDisplayRepresentation = "集中のプリセット"
  static var defaultQuery = FocusPresetQuery()

  var id: String
  var label: String

  var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(label)") }

  init(_ preset: FocusPreset) {
    id = preset.id
    label = "\(preset.label)(\(preset.difficulty.label))"
  }
}

struct FocusPresetQuery: EntityQuery {
  func entities(for identifiers: [String]) async throws -> [FocusPresetEntity] {
    SharedStore.config().presets.filter { identifiers.contains($0.id) }.map(FocusPresetEntity.init)
  }

  func suggestedEntities() async throws -> [FocusPresetEntity] {
    SharedStore.config().presets.map(FocusPresetEntity.init)
  }
}

/// 集中セッションを始める(プリセットを選ばなければ、ホームのプリセット)
struct StartFocusIntent: AppIntent {
  static var title: LocalizedStringResource = "集中セッションを始める"
  static var description = IntentDescription("ツクエログのプリセットで、選んだアプリを決めた時間だけ制限します")
  static var openAppWhenRun = false

  @Parameter(title: "プリセット")
  var preset: FocusPresetEntity?

  func perform() async throws -> some IntentResult & ProvidesDialog {
    let now = Date()
    let text: String
    switch RestrictionEngine.startPreset(preset?.id, now: now) {
    case .started(let until):
      let label = preset?.label ?? SharedStore.config().homePreset?.label ?? ""
      text = "\(label)の集中を始めました。\(clock(until)) まで制限します"
    case .alreadyRunning(let until):
      text = "もう集中セッション中です" + (until.map { "(\(clock($0)) まで)" } ?? "")
    case .unavailable:
      text = "スマホ制限は、Apple の許可が下りてから使えます"
    case .notAuthorized:
      text = "ツクエログの「スマホ制限」で、スクリーンタイムの利用を許可してね"
    case .noApps:
      text = "ツクエログの「スマホ制限」で、制限するアプリを選んでね"
    }
    return .result(dialog: "\(text)")
  }
}

struct TsukueLogShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartFocusIntent(),
      phrases: [
        "\(.applicationName)で集中を始める",
        "\(.applicationName)でスマホを制限する",
        "Start focus in \(.applicationName)",
      ],
      shortTitle: "集中を始める",
      systemImageName: "hourglass")
  }
}
