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
  let runner = SessionRunner()

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
    screen = .home
  }
}
