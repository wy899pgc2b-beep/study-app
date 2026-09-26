import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import RestrictionCore
import os

// スマホ制限(決定事項 D-24、設計書 3.30)の動き。アプリと 3 つの拡張が同じものを使う。
// 制限の場所(ManagedSettingsStore)は、制限の出どころごとに分ける("session"・"study"・"schedule.<id>"・"limit.<id>"・"open.<id>")。
// 重なったときは、Apple の仕組みがいちばん厳しいものをかける。1 つを外しても、ほかの制限は残る。

private let log = Logger(subsystem: "tsukuelog", category: "restriction")

/// アプリを制限する・外す
enum Shielder {
  static func store(_ key: String) -> ManagedSettingsStore {
    ManagedSettingsStore(named: ManagedSettingsStore.Name(rawValue: key))
  }

  static func apply(_ key: String, _ list: BlockList, denyRemoval: Bool) {
    let s = store(key)
    let sel = list.selection
    if list.allowMode {
      // 選んだもの以外をすべて
      s.shield.applications = nil
      s.shield.webDomains = nil
      s.shield.applicationCategories = .all(except: sel.applicationTokens)
      s.shield.webDomainCategories = .all(except: sel.webDomainTokens)
    } else {
      s.shield.applications = sel.applicationTokens.isEmpty ? nil : sel.applicationTokens
      s.shield.webDomains = sel.webDomainTokens.isEmpty ? nil : sel.webDomainTokens
      s.shield.applicationCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
      s.shield.webDomainCategories = sel.categoryTokens.isEmpty ? nil : .specific(sel.categoryTokens)
    }
    // ディープフォーカスの間は、アプリを削除できなくする
    s.application.denyAppRemoval = denyRemoval ? true : nil
  }

  static func clear(_ key: String) {
    store(key).clearAllSettings()
  }
}

/// 時間の見張り(DeviceActivity)。区間の始まり・終わりと、使った時間のしきい値で、拡張(MonitorExtension)が呼ばれる
enum Watcher {
  static let center = DeviceActivityCenter()
  private static let fullDate: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

  /// 1 回だけ、end に終わる区間(短い区間は、始まりを過去にずらす)
  static func once(_ activity: String, until end: Date, now: Date) {
    let w = monitorWindow(until: end, now: now)
    let cal = Calendar.current
    let schedule = DeviceActivitySchedule(
      intervalStart: cal.dateComponents(fullDate, from: w.start), intervalEnd: cal.dateComponents(fullDate, from: w.end), repeats: false)
    start(activity, schedule)
  }

  /// 毎日の区間(0 時からの分)
  static func daily(_ activity: String, from start: Int, to end: Int, events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) {
    let schedule = DeviceActivitySchedule(
      intervalStart: DateComponents(hour: start / 60, minute: start % 60, second: 0),
      intervalEnd: DateComponents(hour: end / 60, minute: end % 60, second: end == 1439 ? 59 : 0), repeats: true)
    self.start(activity, schedule, events: events)
  }

  private static func start(_ activity: String, _ schedule: DeviceActivitySchedule, events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]) {
    let name = DeviceActivityName(rawValue: activity)
    center.stopMonitoring([name])
    do {
      try center.startMonitoring(name, during: schedule, events: events)
    } catch {
      log.error("startMonitoring \(activity, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  static func stop(_ activities: [String]) {
    center.stopMonitoring(activities.map { DeviceActivityName(rawValue: $0) })
  }

  static var monitoring: Set<String> { Set(center.activities.map(\.rawValue)) }
}

enum RestrictionEngine {
  /// 学習と連動した制限の、いちばん長い時間(アプリが終わらされても、制限が残り続けないように)
  static let studyMaxHours = 8.0
  /// 見張りの呼ばれる時刻のずれを見込む秒数
  static let slack: TimeInterval = 90

  // MARK: 始める・終える

  static func start(kind: SessionKind, key: String, end: Date?, difficulty: Difficulty, apps: BlockList, now: Date, watchEnd: Bool) {
    let s = ActiveSession(key: key, kind: kind, difficulty: difficulty, startAt: now, endAt: end)
    SharedStore.updateState { $0.sessions[key] = s }
    Shielder.apply(key, apps, denyRemoval: difficulty == .deep)
    Watcher.stop([RestrictionKeys.breakActivity(key)])
    if watchEnd, let end { Watcher.once(key, until: end, now: now) }
  }

  /// 集中セッションを始める
  static func startFocus(minutes: Int, difficulty: Difficulty, apps: BlockList, now: Date) {
    start(
      kind: .manual, key: RestrictionKeys.session, end: now.addingTimeInterval(Double(minutes) * 60), difficulty: difficulty, apps: apps,
      now: now, watchEnd: true)
  }

  /// 学習を始めた(学習と連動)。学習を終えるまで制限する
  static func startStudy(difficulty: Difficulty, apps: BlockList, now: Date) {
    start(kind: .study, key: RestrictionKeys.study, end: nil, difficulty: difficulty, apps: apps, now: now, watchEnd: false)
    Watcher.once(RestrictionKeys.study, until: now.addingTimeInterval(studyMaxHours * 3600), now: now)
  }

  static func end(_ key: String) {
    SharedStore.updateState { $0.sessions[key] = nil }
    Shielder.clear(key)
    var activities = [RestrictionKeys.breakActivity(key)]
    if key == RestrictionKeys.session || key == RestrictionKeys.study { activities.append(key) }
    Watcher.stop(activities)
  }

  /// 休憩(時間制限では「あと 5 分」)を求める。できるなら、休憩の間だけ制限を外す
  @discardableResult
  static func requestBreak(_ key: String, now: Date, minutes: Int = RestrictionRules.breakMinutes, confirm: Bool = true) -> BreakDecision {
    var decision = BreakDecision.notAllowed
    SharedStore.updateState { st in
      guard var s = st.sessions[key] else { return }
      decision = s.requestBreak(now: now, minutes: minutes, confirm: confirm)
      st.sessions[key] = s
    }
    if case .allowed(let until) = decision {
      Shielder.clear(key)
      Watcher.once(RestrictionKeys.breakActivity(key), until: until, now: now)
    }
    return decision
  }

  /// 終わりを求める
  static func requestEnd(_ key: String, now: Date) -> EndDecision {
    var decision = EndDecision.allowed
    SharedStore.updateState { st in
      guard var s = st.sessions[key] else { return }
      decision = s.requestEnd(now: now)
      st.sessions[key] = s
    }
    if decision == .allowed { end(key) }
    return decision
  }

  /// 休憩の終わり。まだ制限の時間なら、もう一度制限する(force:学習に戻ったときは、休憩の時間が残っていても)
  static func breakOver(_ key: String, now: Date, force: Bool = false) {
    var again: ActiveSession?
    SharedStore.updateState { st in
      guard var s = st.sessions[key], let until = s.breakUntil else { return }
      guard force || until <= now.addingTimeInterval(slack) else { return }
      s.breakEnded()
      st.sessions[key] = s
      if !s.isOver(at: now) { again = s }
    }
    if let s = again, let apps = SharedStore.config().apps(for: key) {
      Shielder.apply(key, apps, denyRemoval: s.difficulty == .deep)
    }
    if force { Watcher.stop([RestrictionKeys.breakActivity(key)]) }
  }

  // MARK: 開く回数

  /// 1 回開く。開けたら、決めた分だけ制限を外す
  static func openOnce(_ id: String, now: Date) -> Bool {
    guard let rule = SharedStore.config().open(id), rule.limit.enabled else { return false }
    let until = now.addingTimeInterval(Double(rule.limit.minutesPerOpen) * 60)
    var opened = false
    SharedStore.updateState { st in
      opened = st.opens.open(rule.limit, day: DayKey.of(now))
      if opened { st.unlockedUntil[id] = until }
    }
    guard opened else { return false }
    Shielder.clear(rule.key)
    Watcher.once(RestrictionKeys.unlockActivity(id), until: until, now: now)
    return true
  }

  /// 開いていた時間が終わったので、もう一度制限する
  static func relock(_ id: String, now: Date) {
    var due = false
    SharedStore.updateState { st in
      guard let until = st.unlockedUntil[id], until <= now.addingTimeInterval(slack) else { return }
      st.unlockedUntil[id] = nil
      due = true
    }
    if due, let rule = SharedStore.config().open(id), rule.limit.enabled, !rule.apps.isEmpty {
      Shielder.apply(rule.key, rule.apps, denyRemoval: false)
    }
  }

  // MARK: 時間割

  /// 時間割の区間に合わせて、始める・終える
  static func checkSchedule(_ id: String, now: Date, slack: TimeInterval = 0) {
    let key = "schedule." + id
    let current = SharedStore.state().sessions[key]
    guard let rule = SharedStore.config().schedule(id), rule.schedule.enabled, rule.schedule.isValid, !rule.apps.isEmpty,
      let w = rule.schedule.window(containing: now.addingTimeInterval(slack))
    else {
      if current != nil { end(key) }
      return
    }
    if let s = current, s.endAt == w.end {
      if !s.onBreak(at: now) { Shielder.apply(key, rule.apps, denyRemoval: s.difficulty == .deep) }
      return
    }
    start(kind: .schedule, key: key, end: w.end, difficulty: rule.schedule.difficulty, apps: rule.apps, now: now, watchEnd: false)
  }

  private static func scheduleID(_ activity: String) -> String? {
    guard let rest = RestrictionKeys.id(activity, prefix: "schedule."), let dot = rest.lastIndex(of: ".") else { return nil }
    return String(rest[..<dot])
  }

  // MARK: 見張りから呼ばれる(MonitorExtension)

  static func intervalDidStart(_ activity: String, now: Date) {
    if activity == RestrictionKeys.day {
      newDay(now: now)
    } else if let id = scheduleID(activity) {
      checkSchedule(id, now: now, slack: slack)
    }
    // 休憩・開いている時間・集中セッションの区間は、始まりでは何もしない(すぐ呼ばれることがある)
  }

  static func intervalDidEnd(_ activity: String, now: Date) {
    let state = SharedStore.state()
    switch activity {
    case RestrictionKeys.session:
      if let s = state.sessions[activity], s.isOver(at: now.addingTimeInterval(slack)) { end(activity) }
    case RestrictionKeys.study:
      if let s = state.sessions[activity], now.timeIntervalSince(s.startAt) >= studyMaxHours * 3600 - slack { end(activity) }
    case RestrictionKeys.day:
      endLimits(now: now)
    default:
      if let key = RestrictionKeys.id(activity, prefix: "break.") {
        breakOver(key, now: now)
      } else if let id = RestrictionKeys.id(activity, prefix: "unlock.") {
        relock(id, now: now)
      } else if let id = scheduleID(activity) {
        checkSchedule(id, now: now, slack: slack)
      }
    }
  }

  /// 1 日の時間を使い切った
  static func thresholdReached(_ event: String, activity: String, now: Date) {
    guard activity == RestrictionKeys.day, let id = RestrictionKeys.id(event, prefix: "limit."),
      let rule = SharedStore.config().limit(id), rule.limit.enabled
    else { return }
    // 0 時からの時間より多く使うことはない(区間の始まりに、しきい値がすぐ届いてしまうことがあるため)
    let sinceMidnight = now.timeIntervalSince(Calendar.current.startOfDay(for: now))
    guard sinceMidnight >= Double(rule.limit.minutes) * 60 - 30 else { return }
    guard SharedStore.state().sessions[rule.key] == nil else { return }
    start(
      kind: .limit, key: rule.key, end: DayKey.endOfDay(now), difficulty: rule.limit.difficulty, apps: rule.apps, now: now,
      watchEnd: false)
  }

  /// 0 時:時間制限を終え、開く回数の制限をかけ直す
  private static func newDay(now: Date) {
    endLimits(now: now)
    let config = SharedStore.config()
    SharedStore.updateState { $0.unlockedUntil = [:] }
    for rule in config.opens {
      Watcher.stop([RestrictionKeys.unlockActivity(rule.id)])
      if rule.limit.enabled && !rule.apps.isEmpty { Shielder.apply(rule.key, rule.apps, denyRemoval: false) }
    }
  }

  private static func endLimits(now: Date) {
    for (key, s) in SharedStore.state().sessions where s.kind == .limit && s.isOver(at: now.addingTimeInterval(slack)) {
      end(key)
    }
  }

  // MARK: 合わせ直す

  /// 時間が過ぎたのに見張りが呼ばれなかったものを片づける
  static func sweep(now: Date) {
    let state = SharedStore.state()
    for (key, s) in state.sessions {
      let studyTooLong = s.kind == .study && now.timeIntervalSince(s.startAt) >= studyMaxHours * 3600
      if s.isOver(at: now) || studyTooLong {
        end(key)
      } else if let until = s.breakUntil, until <= now {
        breakOver(key, now: now)
      }
    }
    for (id, until) in state.unlockedUntil where until <= now { relock(id, now: now) }
  }

  /// 設定を変えたときと、アプリを開いたときに、見張りと制限を設定に合わせる
  static func sync(now: Date) {
    sweep(now: now)
    let config = SharedStore.config()
    let state = SharedStore.state()

    // 見張り:時間割(毎日の区間)と、1 日の区間(時間制限と、開く回数の数え直し)
    var wanted: [String: String] = [:]
    for rule in config.schedules where rule.schedule.enabled && rule.schedule.isValid && !rule.apps.isEmpty {
      for (i, part) in rule.schedule.dailyIntervals.enumerated() {
        wanted[RestrictionKeys.scheduleActivity(rule.id, part: i)] = "\(part.start)-\(part.end)"
      }
    }
    let limits = config.limits.filter { $0.limit.enabled && !$0.apps.isEmpty }
    if !limits.isEmpty || config.opens.contains(where: { $0.limit.enabled }) {
      wanted[RestrictionKeys.day] = "day;" + limits.map { "\($0.id)#\($0.revision)" }.joined(separator: ",")
    }
    let running = Watcher.monitoring
    let managed = running.filter { $0.hasPrefix("schedule.") || $0 == RestrictionKeys.day }
    Watcher.stop(Array(managed.subtracting(wanted.keys)))
    for (activity, signature) in wanted where state.monitored[activity] != signature || !running.contains(activity) {
      if activity == RestrictionKeys.day {
        Watcher.daily(activity, from: 0, to: 1439, events: limitEvents(limits))
      } else if let id = scheduleID(activity), let rule = config.schedule(id), let part = Int(activity.split(separator: ".").last ?? ""),
        rule.schedule.dailyIntervals.indices.contains(part)
      {
        let p = rule.schedule.dailyIntervals[part]
        Watcher.daily(activity, from: p.start, to: p.end)
      }
    }
    SharedStore.updateState { $0.monitored = wanted }

    // 時間割:いまの区間に合わせる(消した時間割は終える)
    for rule in config.schedules { checkSchedule(rule.id, now: now) }
    for key in state.sessions.keys {
      if let id = RestrictionKeys.id(key, prefix: "schedule."), config.schedule(id) == nil { end(key) }
    }
    // 時間制限:消した・止めたものは終える。使い切っているものは、選び直したアプリで制限し直す
    for (key, s) in SharedStore.state().sessions where s.kind == .limit {
      guard let id = RestrictionKeys.id(key, prefix: "limit."), let rule = config.limit(id), rule.limit.enabled else {
        end(key)
        continue
      }
      if !s.onBreak(at: now) { Shielder.apply(key, rule.apps, denyRemoval: s.difficulty == .deep) }
    }
    // 開く回数の制限
    let unlocked = SharedStore.state().unlockedUntil
    for rule in config.opens {
      if rule.limit.enabled && !rule.apps.isEmpty {
        if let until = unlocked[rule.id], until > now { continue }
        Shielder.apply(rule.key, rule.apps, denyRemoval: false)
      } else {
        Shielder.clear(rule.key)
        Watcher.stop([RestrictionKeys.unlockActivity(rule.id)])
      }
    }
    // 集中セッション・学習中:選び直したアプリで制限し直す
    for key in [RestrictionKeys.session, RestrictionKeys.study] {
      if let s = SharedStore.state().sessions[key], !s.onBreak(at: now), !s.isOver(at: now) {
        Shielder.apply(key, config.focusApps, denyRemoval: s.difficulty == .deep)
      }
    }
  }

  private static func limitEvents(_ limits: [LimitRule]) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    for rule in limits {
      let sel = rule.apps.selection
      let threshold = DateComponents(hour: rule.limit.minutes / 60, minute: rule.limit.minutes % 60)
      let event: DeviceActivityEvent
      if #available(iOS 17.4, *) {
        // 見張り直しても、その日のそれまでの時間を数える
        event = DeviceActivityEvent(
          applications: sel.applicationTokens, categories: sel.categoryTokens, webDomains: sel.webDomainTokens, threshold: threshold,
          includesPastActivity: true)
      } else {
        event = DeviceActivityEvent(
          applications: sel.applicationTokens, categories: sel.categoryTokens, webDomains: sel.webDomainTokens, threshold: threshold)
      }
      events[DeviceActivityEvent.Name(rawValue: rule.key)] = event
    }
    return events
  }

  // MARK: シールド(制限の画面とボタン)

  enum Source {
    case session(ActiveSession, name: String?)
    case open(OpenRule, remaining: Int)
  }

  /// このアプリを制限している出どころ(集中セッション → 学習中 → 時間割 → 時間制限 → 開く回数の順に探す)
  static func source(for target: ShieldTarget, now: Date) -> Source? {
    let config = SharedStore.config()
    let state = SharedStore.state()
    let order: [SessionKind] = [.manual, .study, .schedule, .limit]
    let active = state.sessions.values
      .filter { !$0.onBreak(at: now) && !$0.isOver(at: now) }
      .sorted { (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9) }
    for s in active where config.apps(for: s.key)?.covers(target) == true {
      return .session(s, name: config.name(for: s.key))
    }
    let day = DayKey.of(now)
    for rule in config.opens where rule.limit.enabled && rule.apps.covers(target) {
      if let until = state.unlockedUntil[rule.id], until > now { continue }
      return .open(rule, remaining: state.opens.remaining(rule.limit, day: day))
    }
    return nil
  }

  static func copy(for target: ShieldTarget, now: Date) -> ShieldCopy {
    switch source(for: target, now: now) {
    case .session(let s, let name):
      return ShieldCopyMaker.session(s, name: name, now: now)
    case .open(let rule, let remaining):
      return ShieldCopyMaker.open(rule.limit, remaining: remaining)
    case nil:
      return ShieldCopy(title: "ツクエログが制限しています", subtitle: "制限の時間が終わっていれば、「確かめる」で開けます", secondary: "確かめる")
    }
  }

  enum Press {
    /// アプリを閉じる
    case close
    /// 制限の画面を描き直す(制限を外したときは、そのままアプリが開く)
    case redraw
  }

  /// 制限の画面の 2 つめのボタン(休憩する・あと 5 分使う・開く・確かめる)
  static func secondaryPressed(for target: ShieldTarget, now: Date) -> Press {
    switch source(for: target, now: now) {
    case .session(let s, _):
      switch requestBreak(s.key, now: now) {
      case .allowed, .confirmAgain, .alreadyOnBreak: return .redraw
      case .notUntil, .notAllowed: return .close
      }
    case .open(let rule, _):
      return openOnce(rule.id, now: now) ? .redraw : .close
    case nil:
      sweep(now: now)
      return .redraw
    }
  }
}
