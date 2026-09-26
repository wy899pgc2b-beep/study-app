import Foundation
import Observation
import StudyCore

/// 学習の前に決めておく設定(設計書 3.24、決定事項 D-9)。端末に覚えておく。
struct StudySettings: Codable, Equatable {
  var breakTimer = BreakTimer()
  var setup: SetupStyle = .landscape
  /// 本人が測った目と机の距離(cm)。「近すぎ」の基準に使う(決定事項 D-7)
  var eyeDeskCm: Double = 35
  /// 置く前の説明(置き方の絵)を省く(設計書 5.5)
  var skipPlacementIntro = false

  init() {}

  // 項目を増やしても、前に保存した設定を読めるようにする
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    breakTimer = try c.decodeIfPresent(BreakTimer.self, forKey: .breakTimer) ?? BreakTimer()
    setup = try c.decodeIfPresent(SetupStyle.self, forKey: .setup) ?? .landscape
    eyeDeskCm = try c.decodeIfPresent(Double.self, forKey: .eyeDeskCm) ?? 35
    skipPlacementIntro = try c.decodeIfPresent(Bool.self, forKey: .skipPlacementIntro) ?? false
  }

  private static let key = "studySettings"

  static func load() -> StudySettings {
    guard let data = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(StudySettings.self, from: data) else {
      return StudySettings()
    }
    return s
  }

  func save() {
    if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
  }
}

enum Screen: Equatable {
  case home
  /// 置く前の説明(置き方の絵)
  case placement
  case session
  case result
}

@MainActor
@Observable
final class AppModel {
  var screen: Screen = .home
  private(set) var settings = StudySettings.load()
  /// 端末の DB。開けなかったときは記録を保存せずに動く
  let store: Store?
  let runner: SessionRunner
  /// 今日の学習日の合計(ホームに出す)
  private(set) var today: DayTotal?
  /// この 1 週間の学習日ごとの合計(古い順。最後が今日)
  private(set) var week: [DayTotal] = []
  /// 結果カードから「ホームに貼っておく」にした明日の一手(ホームの「今日の一手」)
  private(set) var pinnedNextStep: String? = UserDefaults.standard.string(forKey: "pinnedNextStep")

  init() {
    let store = try? Store()
    self.store = store
    runner = SessionRunner(store: store)
    // 前回、計測中にアプリが強制終了されていたら、それまでの記録を締める
    store?.recoverUnfinished()
    refreshToday()
  }

  func refreshToday() {
    let dates = StudyDay.recentDates(7, until: Date())
    week = dayTotals(store?.sessions(since: dates[0]) ?? [], dates: dates)
    today = week.last
  }

  func pin(_ nextStep: String) {
    pinnedNextStep = nextStep
    UserDefaults.standard.set(nextStep, forKey: "pinnedNextStep")
  }

  /// 「机に向かう」:置く前の説明を見せてから始める(省く設定なら、すぐ始める)
  func beginFromHome() {
    if settings.skipPlacementIntro {
      start()
    } else {
      screen = .placement
    }
  }

  func update(_ change: (inout StudySettings) -> Void) {
    var s = settings
    change(&s)
    guard s != settings else { return }
    settings = s
    s.save()
  }

  func start() {
    screen = .session
    Task { await runner.start(settings: settings) }
  }

  func finish() {
    runner.finish()
    screen = .result
  }

  func backHome() {
    refreshToday()
    screen = .home
  }
}
