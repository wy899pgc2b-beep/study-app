import FamilyControls
import Foundation
import Observation
import RestrictionCore

/// スマホ制限(裏機能。決定事項 D-24、設計書 3.30)。Opal によく似た仕様:
/// 集中セッション・学習と連動・時間割・1 日の時間制限・開く回数の制限と、3 段階の厳しさ(ふつう・タイムアウト・ディープフォーカス)。
/// 選んだアプリや使った時間は Apple の仕組みの中だけで扱われ、ツクエログにも、ほかの人にもわからない
@MainActor
@Observable
final class RestrictionModel {
  /// Apple の許可(Family Controls)を得たビルドか。得ていなければ「Apple の許可待ち」と出す
  let available = RestrictionEnv.enabled
  /// 本人がスクリーンタイムの利用を許可した
  private(set) var authorized = false
  private(set) var config = SharedStore.config()
  private(set) var state = SharedStore.state()
  var errorMessage: String?
  /// 学習の休憩の画面に出す、スマホ制限の様子
  private(set) var studyNote: String?

  init() {
    refresh()
  }

  var ready: Bool { available && authorized }

  /// アプリを開いたとき・画面を開いたとき:許可を確かめ、見張りと制限を設定に合わせる
  func refresh() {
    guard available else { return }
    authorized = AuthorizationCenter.shared.authorizationStatus == .approved
    if authorized { RestrictionEngine.sync(now: Date()) }
    reload()
  }

  private func reload() {
    config = SharedStore.config()
    state = SharedStore.state()
  }

  func requestAuthorization() async {
    guard available else { return }
    do {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      errorMessage = nil
    } catch {
      errorMessage = "許可されませんでした。設定アプリで「スクリーンタイム」がオンになっているか確かめてね"
    }
    refresh()
  }

  func updateConfig(_ change: (inout RestrictionConfig) -> Void) {
    let old = SharedStore.config()
    var c = old
    change(&c)
    guard c != old else { return }
    SharedStore.save(c)
    if ready { RestrictionEngine.sync(now: Date()) }
    reload()
  }

  // MARK: いまの制限

  var focus: ActiveSession? { state.sessions[RestrictionKeys.session] }
  var study: ActiveSession? { state.sessions[RestrictionKeys.study] }

  struct ActiveItem: Identifiable {
    var id: String
    var title: String
  }

  /// いま制限している時間割と時間制限(名前と、終わりの時刻)
  var otherActive: [ActiveItem] {
    state.sessions.values
      .filter { ($0.kind == .schedule || $0.kind == .limit) && !$0.isOver(at: Date()) }
      .sorted { $0.startAt < $1.startAt }
      .map { s in
        let name = config.name(for: s.key) ?? ""
        let until = s.kind == .limit ? "あしたまで" : s.endAt.map { "\(clock($0)) まで" } ?? ""
        return ActiveItem(id: s.key, title: "「\(name)」\(s.onBreak(at: Date()) ? "(休憩中)" : "") \(until)")
      }
  }

  /// ホームの入口に出す短い様子
  var homeStatus: String? {
    guard ready else { return nil }
    if focus != nil { return "集中セッション中" }
    if study != nil { return "学習中は制限中" }
    if !otherActive.isEmpty { return "制限中" }
    return nil
  }

  /// ディープフォーカスで制限している間は、その制限を変えられない
  func locked(_ key: String) -> Bool {
    guard let s = state.sessions[key] else { return false }
    return s.difficulty == .deep && !s.isOver(at: Date())
  }

  var focusAppsLocked: Bool { locked(RestrictionKeys.session) || locked(RestrictionKeys.study) }

  // MARK: 集中セッション

  func startFocus() {
    guard ready, !config.focusApps.isEmpty, focus == nil else { return }
    RestrictionEngine.startFocus(minutes: config.sessionMinutes, difficulty: config.difficulty, apps: config.focusApps, now: Date())
    reload()
  }

  @discardableResult
  func requestFocusBreak() -> BreakDecision {
    let d = RestrictionEngine.requestBreak(RestrictionKeys.session, now: Date())
    reload()
    return d
  }

  @discardableResult
  func requestFocusEnd() -> EndDecision {
    let d = RestrictionEngine.requestEnd(RestrictionKeys.session, now: Date())
    reload()
    return d
  }

  /// 休憩を早めに終える
  func endFocusBreak() {
    RestrictionEngine.breakOver(RestrictionKeys.session, now: Date(), force: true)
    reload()
  }

  /// 画面を開いたままの間に、時間が過ぎたもの(集中セッションの終わり・休憩の終わり)を片づける
  func tick() {
    guard ready else { return }
    RestrictionEngine.sweep(now: Date())
    let s = SharedStore.state()
    if s != state { state = s }
  }

  // MARK: 学習と連動

  /// 学習を始めた(開始の儀式を終えたとき)
  func studyStarted() {
    studyNote = nil
    guard ready, config.studyLink, !config.focusApps.isEmpty else { return }
    RestrictionEngine.startStudy(difficulty: config.studyDifficulty, apps: config.focusApps, now: Date())
    reload()
  }

  /// 学習の休憩・仮眠を始めた。ふつうは休憩の間だけ外す(休憩にしたこと自体を確かめとみなす)。仮眠の間は外さない
  func studyBreakStarted(minutes: Int, nap: Bool) {
    guard ready, study != nil else { return }
    if nap {
      studyNote = "仮眠の間も、スマホ制限は続けるよ"
      return
    }
    switch RestrictionEngine.requestBreak(RestrictionKeys.study, now: Date(), minutes: minutes, confirm: false) {
    case .allowed, .alreadyOnBreak, .confirmAgain:
      studyNote = "休憩の間は、スマホ制限を外しているよ"
    case .notUntil(let t):
      studyNote = "スマホ制限の休憩は \(clock(t)) からできるよ。それまでは制限したまま"
    case .notAllowed:
      studyNote = "ディープフォーカスなので、休憩の間もスマホ制限は続くよ"
    }
    reload()
  }

  /// 学習に戻った
  func studyBreakEnded() {
    studyNote = nil
    guard ready, study != nil else { return }
    RestrictionEngine.breakOver(RestrictionKeys.study, now: Date(), force: true)
    reload()
  }

  /// 学習を終えた
  func studyFinished() {
    studyNote = nil
    guard available, study != nil else { return }
    RestrictionEngine.end(RestrictionKeys.study)
    reload()
  }

  /// 学習していないのに学習中の制限が残っていたら外す(前回、学習の途中でアプリが終わらされたとき)
  func clearStaleStudy() {
    guard available, SharedStore.state().sessions[RestrictionKeys.study] != nil else { return }
    RestrictionEngine.end(RestrictionKeys.study)
    reload()
  }

  // MARK: 時間割・時間制限・開く回数

  var canAddSchedule: Bool { config.schedules.count < RestrictionConfig.maxSchedules }
  var canAddLimit: Bool { config.limits.count < RestrictionConfig.maxLimits }
  var canAddOpen: Bool { config.opens.count < RestrictionConfig.maxOpens }

  func save(_ rule: ScheduleRule) {
    updateConfig { c in
      if let i = c.schedules.firstIndex(where: { $0.id == rule.id }) { c.schedules[i] = rule } else { c.schedules.append(rule) }
    }
  }

  func save(_ rule: LimitRule) {
    var r = rule
    r.revision += 1
    updateConfig { c in
      if let i = c.limits.firstIndex(where: { $0.id == r.id }) { c.limits[i] = r } else { c.limits.append(r) }
    }
  }

  func save(_ rule: OpenRule) {
    updateConfig { c in
      if let i = c.opens.firstIndex(where: { $0.id == rule.id }) { c.opens[i] = rule } else { c.opens.append(rule) }
    }
  }

  func deleteSchedule(_ id: String) {
    guard !locked("schedule." + id) else { return }
    updateConfig { $0.schedules.removeAll { $0.id == id } }
  }

  func deleteLimit(_ id: String) {
    guard !locked("limit." + id) else { return }
    updateConfig { $0.limits.removeAll { $0.id == id } }
  }

  func deleteOpen(_ id: String) {
    updateConfig { $0.opens.removeAll { $0.id == id } }
    if available {
      Shielder.clear("open." + id)
      Watcher.stop([RestrictionKeys.unlockActivity(id)])
    }
  }

  /// 開く回数の制限で、今日あと何回開けるか
  func remainingOpens(_ rule: OpenRule) -> Int {
    state.opens.remaining(rule.limit, day: DayKey.of(Date()))
  }
}
