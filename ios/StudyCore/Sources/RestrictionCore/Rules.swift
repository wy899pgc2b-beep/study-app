import Foundation

// スマホ制限(裏機能。決定事項 D-24、設計書 3.30)の決まり。Opal によく似た仕様にする。
// Apple の Screen Time の仕組み(FamilyControls・ManagedSettings・DeviceActivity)には頼らないので、Linux でもテストできる。
// アプリと拡張(制限の画面・ボタン・時間の見張り)が同じ決まりを使う。

/// 厳しさ(Opal と同じ 3 段階)
public enum Difficulty: String, Codable, CaseIterable, Sendable {
  /// ふつう:休憩・終了はできるが、1 回押したあと 6 秒待って、もう一度押す
  case normal
  /// タイムアウト:休憩のたびに、次の休憩までの待ち時間が 15 分 → 30 分 → 60 分と長くなる
  case timeout
  /// ディープフォーカス:終わりの時刻まで、休憩も終了もできない。アプリの削除もできなくする
  case deep

  public var label: String {
    switch self {
    case .normal: "ふつう"
    case .timeout: "タイムアウト"
    case .deep: "ディープフォーカス"
    }
  }

  public var summary: String {
    switch self {
    case .normal: "休憩・終了の前に 6 秒待つ"
    case .timeout: "休憩のたびに、次の休憩まで 15 分 → 30 分 → 60 分と待つ"
    case .deep: "時間まで休憩も終了もできない。アプリの削除もできない"
    }
  }
}

public enum RestrictionRules {
  /// ふつう:1 回目に押してから、もう一度押せるまでの秒数
  public static let confirmWaitSec: Double = 6
  /// 1 回目に押したことを覚えておく秒数(これを過ぎたら、1 回目からやり直す)
  public static let confirmExpireSec: Double = 60
  /// 休憩の長さ(分)
  public static let breakMinutes = 5
  /// タイムアウト:休憩してから、次の休憩ができるまでの分(回ごと。最後の値をくり返す)
  public static let timeoutSteps: [Int] = [15, 30, 60]
  /// DeviceActivity の区間のいちばん短い長さ(分)。これより短い見張りは、始まりを過去にずらして作る
  public static let minMonitorMinutes = 15

  public static func timeoutWait(afterBreak n: Int) -> Int {
    timeoutSteps[Swift.min(Swift.max(0, n - 1), timeoutSteps.count - 1)]
  }
}

/// 何による制限か
public enum SessionKind: String, Codable, Sendable {
  /// 自分で始めた集中セッション
  case manual
  /// 机に向かっている間(学習と連動)
  case study
  /// 時間割
  case schedule
  /// 1 日の使う時間を使い切った(アプリの時間制限)
  case limit
}

public enum BreakDecision: Equatable, Sendable {
  /// 休憩できる(この時刻まで)
  case allowed(until: Date)
  /// ふつう:あと何秒待って、もう一度押す
  case confirmAgain(afterSec: Double)
  /// タイムアウト:この時刻から休憩できる
  case notUntil(Date)
  /// ディープフォーカス:休憩できない
  case notAllowed
  /// すでに休憩中
  case alreadyOnBreak(until: Date)
}

public enum EndDecision: Equatable, Sendable {
  case allowed
  case confirmAgain(afterSec: Double)
  case notUntil(Date)
  case notAllowed
}

/// いま制限している 1 つ(集中セッション・学習中・時間割)と、その休憩の状態
public struct ActiveSession: Codable, Equatable, Sendable {
  /// 制限の場所の名前("session" または "schedule.<id>")
  public var key: String
  public var kind: SessionKind
  public var difficulty: Difficulty
  public var startAt: Date
  /// 終わりの時刻(学習と連動のときは nil:学習が終わるまで)
  public var endAt: Date?
  public var breaksTaken = 0
  public var breakUntil: Date?
  public var nextBreakAllowedAt: Date?
  public var breakRequestedAt: Date?
  public var endRequestedAt: Date?

  public init(key: String, kind: SessionKind, difficulty: Difficulty, startAt: Date, endAt: Date?) {
    self.key = key
    self.kind = kind
    self.difficulty = difficulty
    self.startAt = startAt
    self.endAt = endAt
  }

  public func isOver(at now: Date) -> Bool { endAt.map { now >= $0 } ?? false }

  public func onBreak(at now: Date) -> Bool { breakUntil.map { now < $0 } ?? false }

  /// 残りの秒数(終わりを決めていなければ nil)
  public func remainingSec(at now: Date) -> Double? { endAt.map { Swift.max(0, $0.timeIntervalSince(now)) } }

  /// 休憩を求める。できるなら、休憩の終わりを覚える。
  /// confirm が false のとき(学習の休憩。休憩にしたこと自体が確かめ)は、ふつうでも 6 秒の確かめをしない
  public mutating func requestBreak(now: Date, minutes: Int = RestrictionRules.breakMinutes, confirm: Bool = true) -> BreakDecision {
    if let until = breakUntil, now < until { return .alreadyOnBreak(until: until) }
    switch difficulty {
    case .deep:
      return .notAllowed
    case .timeout:
      if let next = nextBreakAllowedAt, now < next { return .notUntil(next) }
      return startBreak(now: now, minutes: minutes)
    case .normal:
      if confirm, let wait = confirmStep(&breakRequestedAt, now: now) { return .confirmAgain(afterSec: wait) }
      return startBreak(now: now, minutes: minutes)
    }
  }

  /// ふつう:休憩の 1 回目を押してから 60 秒たっていない(2 回目を待っている)
  public func breakPending(at now: Date) -> Bool { Self.pending(breakRequestedAt, now: now) }

  /// ふつう:終了の 1 回目を押してから 60 秒たっていない
  public func endPending(at now: Date) -> Bool { Self.pending(endRequestedAt, now: now) }

  /// 2 回目を押せるまでの残りの秒数(もう押せるなら 0)
  public func confirmWait(for requestedAt: Date?, now: Date) -> Double {
    guard let first = requestedAt else { return RestrictionRules.confirmWaitSec }
    return Swift.max(0, RestrictionRules.confirmWaitSec - now.timeIntervalSince(first))
  }

  private static func pending(_ requestedAt: Date?, now: Date) -> Bool {
    requestedAt.map { now.timeIntervalSince($0) < RestrictionRules.confirmExpireSec } ?? false
  }

  /// 休憩できるか(押さずに調べるだけ)
  public func canBreak(at now: Date) -> Bool {
    switch difficulty {
    case .deep: false
    case .timeout: nextBreakAllowedAt.map { now >= $0 } ?? true
    case .normal: true
    }
  }

  /// 終わりを求める
  public mutating func requestEnd(now: Date) -> EndDecision {
    switch difficulty {
    case .deep:
      return isOver(at: now) ? .allowed : .notAllowed
    case .timeout:
      if let next = nextBreakAllowedAt, now < next, !isOver(at: now) { return .notUntil(next) }
      return .allowed
    case .normal:
      if isOver(at: now) { return .allowed }
      if let wait = confirmStep(&endRequestedAt, now: now) { return .confirmAgain(afterSec: wait) }
      return .allowed
    }
  }

  /// 休憩が終わった
  public mutating func breakEnded() {
    breakUntil = nil
  }

  private mutating func startBreak(now: Date, minutes: Int) -> BreakDecision {
    let until = now.addingTimeInterval(Double(minutes) * 60)
    breaksTaken += 1
    breakUntil = until
    breakRequestedAt = nil
    if difficulty == .timeout {
      nextBreakAllowedAt = now.addingTimeInterval(Double(RestrictionRules.timeoutWait(afterBreak: breaksTaken)) * 60)
    }
    return .allowed(until: until)
  }

  /// ふつうの確かめ:1 回目は時刻を覚えて待つ秒数を返す。6 秒たってからの 2 回目は nil(進めてよい)
  private func confirmStep(_ requestedAt: inout Date?, now: Date) -> Double? {
    if let first = requestedAt, now.timeIntervalSince(first) < RestrictionRules.confirmExpireSec {
      let waited = now.timeIntervalSince(first)
      if waited >= RestrictionRules.confirmWaitSec {
        requestedAt = nil
        return nil
      }
      return RestrictionRules.confirmWaitSec - waited
    }
    requestedAt = now
    return RestrictionRules.confirmWaitSec
  }
}

/// DeviceActivity で見張る区間。短すぎる区間は作れないので、始まりを過去にずらして、終わりの時刻を守る
/// (秒の切り捨てで 15 分を割らないよう、1 分の余裕を持たせる)
public func monitorWindow(until end: Date, now: Date, minMinutes: Int = RestrictionRules.minMonitorMinutes) -> (start: Date, end: Date) {
  let minSec = Double(minMinutes + 1) * 60
  let start = end.timeIntervalSince(now) >= minSec ? now : end.addingTimeInterval(-minSec)
  return (start, end)
}
