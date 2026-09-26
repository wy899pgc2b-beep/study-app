import Foundation
import Observation
import StudyCore

/// 学習の前に決めておく設定(設計書 3.24、決定事項 D-9)。端末に覚えておく。
struct StudySettings: Codable, Equatable {
  var breakTimer = BreakTimer()
  var setup: SetupStyle = .landscape
  /// 本人が測った目と机の距離(cm)。「近すぎ」の基準に使う(決定事項 D-7)
  var eyeDeskCm: Double = 35

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

  init() {
    let store = try? Store()
    self.store = store
    runner = SessionRunner(store: store)
    // 前回、計測中にアプリが強制終了されていたら、それまでの記録を締める
    store?.recoverUnfinished()
    refreshToday()
  }

  func refreshToday() {
    let date = StudyDay.studyDate(Date())
    today = dayTotals(store?.sessions(since: date) ?? [], dates: [date]).first
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
