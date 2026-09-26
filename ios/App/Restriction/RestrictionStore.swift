import FamilyControls
import Foundation
import ManagedSettings
import RestrictionCore

// スマホ制限(決定事項 D-24、設計書 3.30)で、アプリと 3 つの拡張(制限の画面・ボタン・時間の見張り)が共有するもの。
// 選んだアプリは Apple の仕組みの中の「しるし」(トークン)でしか扱えず、アプリの名前や使った時間はツクエログにもわからない。
// ここに置くものは、この iPhone の中(App Group)だけに保存する。

enum RestrictionEnv {
  /// 拡張と共有する App Group(Info.plist の TKAppGroup。xcconfig の TK_APP_GROUP)
  static let appGroup = Bundle.main.object(forInfoDictionaryKey: "TKAppGroup") as? String ?? ""
  /// Apple の許可(Family Controls)を得て、拡張を入れたビルドか(Info.plist の TKRestrictionEnabled)
  static let enabled = (Bundle.main.object(forInfoDictionaryKey: "TKRestrictionEnabled") as? String) == "YES"

  static var defaults: UserDefaults {
    appGroup.isEmpty ? .standard : UserDefaults(suiteName: appGroup) ?? .standard
  }
}

/// シールドを出す相手(アプリ・Web サイト・カテゴリ)
struct ShieldTarget {
  var app: ApplicationToken?
  var web: WebDomainToken?
  var category: ActivityCategoryToken?
}

/// 制限するアプリの選び方
struct BlockList: Codable, Equatable {
  var selection = FamilyActivitySelection()
  /// 選んだもの以外をすべて制限する(Opal の「許可リスト」)
  var allowMode = false

  var count: Int {
    selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
  }

  var isEmpty: Bool { !allowMode && count == 0 }

  func covers(_ t: ShieldTarget) -> Bool {
    if allowMode {
      if let a = t.app { return !selection.applicationTokens.contains(a) }
      if let w = t.web { return !selection.webDomainTokens.contains(w) }
      return t.category != nil
    }
    if let a = t.app, selection.applicationTokens.contains(a) { return true }
    if let w = t.web, selection.webDomainTokens.contains(w) { return true }
    if let c = t.category, selection.categoryTokens.contains(c) { return true }
    return false
  }

  static func == (a: BlockList, b: BlockList) -> Bool {
    a.allowMode == b.allowMode && a.selection.applicationTokens == b.selection.applicationTokens
      && a.selection.categoryTokens == b.selection.categoryTokens && a.selection.webDomainTokens == b.selection.webDomainTokens
  }
}

struct ScheduleRule: Codable, Equatable, Identifiable {
  var schedule: WeeklySchedule
  var apps = BlockList()
  var id: String { schedule.id }
  var key: String { "schedule." + id }
}

struct LimitRule: Codable, Equatable, Identifiable {
  var limit: DailyLimit
  var apps = BlockList()
  /// 変えるたびに 1 つ増やす(変えたときだけ、使った時間の見張りをやり直す)
  var revision = 0
  var id: String { limit.id }
  var key: String { "limit." + id }
}

struct OpenRule: Codable, Equatable, Identifiable {
  var limit: OpenLimit
  var apps = BlockList()
  var id: String { limit.id }
  var key: String { "open." + id }
}

/// 利用者が決めた制限
struct RestrictionConfig: Codable, Equatable {
  /// 集中セッションと、学習中に制限するアプリ
  var focusApps = BlockList()
  var sessionMinutes = 60
  var difficulty: Difficulty = .normal
  /// 机に向かっている間(学習を始めてから終えるまで)も制限する
  var studyLink = false
  var studyDifficulty: Difficulty = .normal
  var schedules: [ScheduleRule] = []
  var limits: [LimitRule] = []
  var opens: [OpenRule] = []

  /// DeviceActivity で同時に見張れる数(20)に収まるようにする
  static let maxSchedules = 4
  static let maxLimits = 3
  static let maxOpens = 3
  static let sessionChoices = [15, 25, 30, 45, 60, 90, 120, 180]

  init() {}

  // 項目を増やしても、前に保存した設定を読めるようにする
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    focusApps = (try? c.decodeIfPresent(BlockList.self, forKey: .focusApps)) ?? BlockList()
    sessionMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionMinutes) ?? 60
    difficulty = (try? c.decodeIfPresent(Difficulty.self, forKey: .difficulty)) ?? .normal
    studyLink = try c.decodeIfPresent(Bool.self, forKey: .studyLink) ?? false
    studyDifficulty = (try? c.decodeIfPresent(Difficulty.self, forKey: .studyDifficulty)) ?? .normal
    schedules = (try? c.decodeIfPresent([ScheduleRule].self, forKey: .schedules)) ?? []
    limits = (try? c.decodeIfPresent([LimitRule].self, forKey: .limits)) ?? []
    opens = (try? c.decodeIfPresent([OpenRule].self, forKey: .opens)) ?? []
  }

  func schedule(_ id: String) -> ScheduleRule? { schedules.first { $0.id == id } }
  func limit(_ id: String) -> LimitRule? { limits.first { $0.id == id } }
  func open(_ id: String) -> OpenRule? { opens.first { $0.id == id } }

  /// 制限の場所の名前("session"・"study"・"schedule.<id>"・"limit.<id>")で制限するアプリ
  func apps(for key: String) -> BlockList? {
    if key == RestrictionKeys.session || key == RestrictionKeys.study { return focusApps }
    if let id = RestrictionKeys.id(key, prefix: "schedule.") { return schedule(id)?.apps }
    if let id = RestrictionKeys.id(key, prefix: "limit.") { return limit(id)?.apps }
    if let id = RestrictionKeys.id(key, prefix: "open.") { return open(id)?.apps }
    return nil
  }

  /// シールドに出す名前(時間割・時間制限の名前)
  func name(for key: String) -> String? {
    if let id = RestrictionKeys.id(key, prefix: "schedule.") { return schedule(id)?.schedule.name }
    if let id = RestrictionKeys.id(key, prefix: "limit.") { return limit(id)?.limit.name }
    return nil
  }
}

/// いまの制限の様子(拡張も書きかえる)
struct RestrictionState: Codable, Equatable {
  var sessions: [String: ActiveSession] = [:]
  var opens = OpenCounter()
  /// 開く回数の制限で、いま開いているもの(id → 終わりの時刻)
  var unlockedUntil: [String: Date] = [:]
  /// 見張りを始めたときの設定(変わったときだけ見張り直す。見張り直すと、使った時間の数え方が変わることがあるため)
  var monitored: [String: String] = [:]

  init() {}

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    sessions = (try? c.decodeIfPresent([String: ActiveSession].self, forKey: .sessions)) ?? [:]
    opens = (try? c.decodeIfPresent(OpenCounter.self, forKey: .opens)) ?? OpenCounter()
    unlockedUntil = (try? c.decodeIfPresent([String: Date].self, forKey: .unlockedUntil)) ?? [:]
    monitored = (try? c.decodeIfPresent([String: String].self, forKey: .monitored)) ?? [:]
  }
}

/// 制限の場所と見張りの名前
enum RestrictionKeys {
  static let session = "session"
  static let study = "study"
  /// 1 日の区間(0:00〜23:59)。時間制限のしきい値と、開く回数の数え直しに使う
  static let day = "day"

  static func breakActivity(_ key: String) -> String { "break." + key }
  static func scheduleActivity(_ id: String, part: Int) -> String { "schedule.\(id).\(part)" }
  static func unlockActivity(_ id: String) -> String { "unlock." + id }

  static func id(_ key: String, prefix: String) -> String? {
    key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : nil
  }
}

/// App Group に保存する
enum SharedStore {
  private static let configKey = "restriction.config"
  private static let stateKey = "restriction.state"

  static func config() -> RestrictionConfig {
    load(RestrictionConfig.self, configKey) ?? RestrictionConfig()
  }

  static func save(_ config: RestrictionConfig) {
    store(config, configKey)
  }

  static func state() -> RestrictionState {
    load(RestrictionState.self, stateKey) ?? RestrictionState()
  }

  /// その時点の保存内容を読み直して書きかえる(アプリと拡張が別々に書くため)
  @discardableResult
  static func updateState(_ change: (inout RestrictionState) -> Void) -> RestrictionState {
    var s = state()
    change(&s)
    store(s, stateKey)
    return s
  }

  private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
    guard let data = RestrictionEnv.defaults.data(forKey: key) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
  }

  private static func store<T: Encodable>(_ value: T, _ key: String) {
    if let data = try? JSONEncoder().encode(value) { RestrictionEnv.defaults.set(data, forKey: key) }
  }
}
