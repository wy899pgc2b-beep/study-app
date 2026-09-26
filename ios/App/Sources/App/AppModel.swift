import AVFoundation
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

/// 案内のしかた(決定事項 D-21)。消音では声も音も出さず、区切りを振動の回数で伝える
enum SoundMode: String, Codable, CaseIterable {
  case voice
  case vibrate

  var label: String {
    switch self {
    case .voice: "声と音"
    case .vibrate: "消音(振動だけ)"
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
  var soundMode: SoundMode = .voice
  /// 検証モードで最後まで行った場面(id)。残りの場面は「あとで」行う
  var scenarioDone: [String] = []
  /// オンボーディングの後に、検証モードを勧めた
  var scenarioInvited = false
  /// 学習項目(前回選んだもの。次の学習に引き継ぐ)と、自分で足した項目
  var subject: String?
  var customSubjects: [String] = []
  /// 居眠りのとき:アラームで起こす(true)/記録だけ(false)。設計書 3.8 の要件 3
  var sleepAlarm = true
  /// 音量(0〜1)
  var volume: Double = 0.6
  /// 離席と判定するまでの時間(秒。10〜60)と、「近すぎ」と判定する近づき方(0.15〜0.4)。設計書の付録 A
  var awaySec: Double = 20
  var closeRatio: Double = 0.25
  /// 居眠りが何度も来るときに、仮眠を勧める(決定事項 D-23)
  var napSuggest = true

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
    soundMode = (try? c.decodeIfPresent(SoundMode.self, forKey: .soundMode)) ?? .voice
    scenarioDone = try c.decodeIfPresent([String].self, forKey: .scenarioDone) ?? []
    scenarioInvited = try c.decodeIfPresent(Bool.self, forKey: .scenarioInvited) ?? false
    subject = try c.decodeIfPresent(String.self, forKey: .subject)
    customSubjects = try c.decodeIfPresent([String].self, forKey: .customSubjects) ?? []
    sleepAlarm = try c.decodeIfPresent(Bool.self, forKey: .sleepAlarm) ?? true
    volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 0.6
    awaySec = try c.decodeIfPresent(Double.self, forKey: .awaySec) ?? 20
    closeRatio = try c.decodeIfPresent(Double.self, forKey: .closeRatio) ?? 0.25
    napSuggest = try c.decodeIfPresent(Bool.self, forKey: .napSuggest) ?? true
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
  /// オンボーディングの後に、検証モードを勧める(「あとで」にできる)
  case scenarioInvite
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
  /// スマホ制限(裏機能。決定事項 D-24)
  let restriction = RestrictionModel()
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
    // 前回、学習の途中でアプリが終わらされていたら、学習と連動した制限を外す
    restriction.clearStaleStudy()
    runner.onMoment = { [weak self] m in
      guard let r = self?.restriction else { return }
      switch m {
      case .started: r.studyStarted()
      case .breakStarted(let minutes, let nap): r.studyBreakStarted(minutes: minutes, nap: nap)
      case .breakEnded: r.studyBreakEnded()
      case .finished: r.studyFinished()
      }
    }
    // 検証モードは、最後の場面が終わると自分で終わる
    runner.onAutoFinish = { [weak self] in
      self?.recordScenarioProgress()
      self?.screen = .result
    }
    headphones = AudioRoute.headphonesConnected
    NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
      Task { @MainActor in self?.headphones = AudioRoute.headphonesConnected }
    }
  }

  /// イヤホンがつながっているか(つながっていなければ、周りに人がいるときはイヤホンか消音を勧める)
  private(set) var headphones = false

  /// 学習項目の候補(前回 → よく使う順 → 自分で足したもの → よく使う教科)
  var subjectChoices: [String] {
    Subjects.ranked(history: store?.recentSubjects() ?? [], custom: settings.customSubjects)
  }

  /// 学習項目を選ぶ(候補にない名前は、自分で足した項目として覚える)
  func chooseSubject(_ name: String) {
    guard let s = Subjects.normalize(name) else { return }
    update { settings in
      settings.subject = s
      if Subjects.isCustom(s) && !settings.customSubjects.contains(s) {
        settings.customSubjects = Array(([s] + settings.customSubjects).prefix(20))
      }
    }
    usage("subject_selected", ["kind": Subjects.isCustom(s) ? "custom" : "preset"])
  }

  /// 自分で足した学習項目を消す
  func removeCustomSubject(_ name: String) {
    update { $0.customSubjects.removeAll { $0 == name } }
  }

  /// 検証モードでまだ最後まで行っていない場面(Scenario.phases の番号)
  var scenarioPending: [Int] {
    Scenario.phases.indices.filter { !settings.scenarioDone.contains(Scenario.phases[$0].id) }
  }

  /// 利用状況の記録(F-27。端末内だけ)
  func usage(_ name: String, _ properties: [String: String] = [:]) {
    store?.log(UsageEvent(name: name, at: Date(), properties: properties))
  }

  /// オンボーディングを終えて、検証モードを勧める
  func completeOnboarding() {
    update { $0.onboarded = true }
    usage("onboarding_complete", ["grade": settings.grade?.rawValue ?? ""])
    screen = .scenarioInvite
  }

  /// 検証モードを「あとで」にする(ホームに付箋を残す)
  func postponeScenario() {
    update { $0.scenarioInvited = true }
    usage("scenario_postponed", ["remaining": String(scenarioPending.count)])
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

  /// 検証モード:検証シナリオの場面を行い、場面ごとの合否を出して記録を書き出す(MVP の設計 5 章 4)。
  /// onlyPending のときは、まだ最後まで行っていない場面だけ行う
  func startScenario(onlyPending: Bool = true) {
    update { $0.scenarioInvited = true }
    let pending = scenarioPending
    let phases = onlyPending && !pending.isEmpty ? pending : Array(Scenario.phases.indices)
    screen = .session
    Task { await runner.start(settings: settings, mode: .scenario, scenarioPhases: phases) }
  }

  /// 検証モードで最後まで行った場面を覚える
  private func recordScenarioProgress() {
    guard runner.mode == .scenario else { return }
    let done = runner.scenarioCompleted
    update { s in
      let added = done.filter { !s.scenarioDone.contains($0) }
      s.scenarioDone += added
    }
  }

  /// 設定の「記録を書き出す」
  func exportRecords() -> URL? {
    let url = store?.exportAll(appVersion: SessionRunner.appVersion, grade: settings.grade?.rawValue)
    if url != nil { usage("records_export") }
    return url
  }

  func finish() {
    runner.finish()
    recordScenarioProgress()
    screen = .result
  }

  func backHome() {
    refreshToday()
    screen = .home
  }
}
