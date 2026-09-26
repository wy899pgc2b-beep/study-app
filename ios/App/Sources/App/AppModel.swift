import Foundation
import Observation
import StudyCore

/// 学年(オンボーディングで選ぶ。MVP の設計 S-01)
enum Grade: String, Codable, CaseIterable, Identifiable {
  case junior1, junior2, junior3, high1, high2, high3, graduate, university, other

  var id: String { rawValue }

  var label: String {
    switch self {
    case .junior1: "中1"
    case .junior2: "中2"
    case .junior3: "中3"
    case .high1: "高1"
    case .high2: "高2"
    case .high3: "高3"
    case .graduate: "既卒"
    case .university: "大学生"
    case .other: "その他"
    }
  }

  /// 保護者の同意を確かめる学年(中学生以下)
  var needsParentalConsent: Bool {
    switch self {
    case .junior1, .junior2, .junior3: true
    default: false
    }
  }
}

/// 学習の前に決めておく設定(設計書 3.24、決定事項 D-9)。端末に覚えておく。
struct StudySettings: Codable, Equatable {
  var breakTimer = BreakTimer()
  var setup: SetupStyle = .landscape
  /// 本人が測った目と机の距離(cm)。「近すぎ」の基準に使う(決定事項 D-7)
  var eyeDeskCm: Double = 35
  /// 置く前の説明(置き方の絵)を省く(設計書 5.5)
  var skipPlacementIntro = false
  /// オンボーディング(同意・学年・カメラの許可)を終えた
  var onboarded = false
  var grade: Grade?
  /// 保護者の同意を得たと本人が確かめた(中学生以下)
  var parentalConsent = false
  /// 映像の扱いに同意した日時
  var consentedAt: Date?

  init() {}

  // 項目を増やしても、前に保存した設定を読めるようにする
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    breakTimer = try c.decodeIfPresent(BreakTimer.self, forKey: .breakTimer) ?? BreakTimer()
    setup = try c.decodeIfPresent(SetupStyle.self, forKey: .setup) ?? .landscape
    eyeDeskCm = try c.decodeIfPresent(Double.self, forKey: .eyeDeskCm) ?? 35
    skipPlacementIntro = try c.decodeIfPresent(Bool.self, forKey: .skipPlacementIntro) ?? false
    onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
    grade = try? c.decodeIfPresent(Grade.self, forKey: .grade)
    parentalConsent = try c.decodeIfPresent(Bool.self, forKey: .parentalConsent) ?? false
    consentedAt = try c.decodeIfPresent(Date.self, forKey: .consentedAt)
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
  /// 初回だけ(同意・学年・カメラの許可)
  case onboarding
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
    if !settings.onboarded { screen = .onboarding }
    // 前回、計測中にアプリが強制終了されていたら、それまでの記録を締める
    store?.recoverUnfinished()
    refreshToday()
    // 検証モードは、最後の場面が終わると自分で終わる
    runner.onAutoFinish = { [weak self] in self?.screen = .result }
  }

  /// 利用状況の記録(F-27。端末内だけ)
  func usage(_ name: String, _ properties: [String: String] = [:]) {
    store?.log(UsageEvent(name: name, at: Date(), properties: properties))
  }

  /// オンボーディングを終えてホームへ
  func completeOnboarding() {
    update { $0.onboarded = true }
    usage("onboarding_complete", ["grade": settings.grade?.rawValue ?? ""])
    screen = .home
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

  /// 検証モード:検証シナリオの 9 場面を行い、場面ごとの合否を出して記録を書き出す(MVP の設計 5 章 4)
  func startScenario() {
    screen = .session
    Task { await runner.start(settings: settings, mode: .scenario) }
  }

  /// 設定の「記録を書き出す」
  func exportRecords() -> URL? {
    let url = store?.exportAll(appVersion: SessionRunner.appVersion, grade: settings.grade?.rawValue)
    if url != nil { usage("records_export") }
    return url
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
