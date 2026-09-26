import Foundation

/// 時間の内訳の種類:判定の状態、または離席中・一時停止
public enum TimeKind: String, Codable, Sendable, CaseIterable {
  case work, think, lookaway, drowsy, sleep, absent, away, paused

  public init(_ state: StudyState) {
    switch state {
    case .work: self = .work
    case .think: self = .think
    case .lookaway: self = .lookaway
    case .drowsy: self = .drowsy
    case .sleep: self = .sleep
    case .absent: self = .absent
    }
  }
}

/// 1 分の中の、種類ごとの秒数
public struct MinuteSecs: Codable, Equatable, Sendable {
  public var work = 0.0
  public var think = 0.0
  public var lookaway = 0.0
  public var drowsy = 0.0
  public var sleep = 0.0
  public var absent = 0.0
  public var away = 0.0
  public var paused = 0.0

  public init() {}

  public subscript(kind: TimeKind) -> Double {
    get {
      switch kind {
      case .work: return work
      case .think: return think
      case .lookaway: return lookaway
      case .drowsy: return drowsy
      case .sleep: return sleep
      case .absent: return absent
      case .away: return away
      case .paused: return paused
      }
    }
    set {
      switch kind {
      case .work: work = newValue
      case .think: think = newValue
      case .lookaway: lookaway = newValue
      case .drowsy: drowsy = newValue
      case .sleep: sleep = newValue
      case .absent: absent = newValue
      case .away: away = newValue
      case .paused: paused = newValue
      }
    }
  }

  /// 集中度を評価できる秒数(自動の離席判定を使わないときは、不在も評価に入れる)
  func evaluable(autoAway: Bool) -> Double {
    work + think + lookaway + drowsy + sleep + (autoAway ? 0 : absent)
  }
}

/// 1 分ごとの記録(設計書 6.2 MINUTE_SCORE)
public struct MinuteRecord: Codable, Equatable, Sendable {
  public var index: Int
  public var secs = MinuteSecs()
  public var habits = 0
  public var interruptions = 0

  public init(index: Int, secs: MinuteSecs = MinuteSecs(), habits: Int = 0, interruptions: Int = 0) {
    self.index = index
    self.secs = secs
    self.habits = habits
    self.interruptions = interruptions
  }
}

/// 1 分の集中度(設計書 4.5)。評価できた時間が足りない分は nil。
public func scoreMinute(_ m: MinuteRecord, _ cfg: AnalysisConfig, autoAway: Bool = true) -> Int? {
  let s = m.secs
  let evaluable = s.evaluable(autoAway: autoAway)
  if evaluable < cfg.minEvaluableSec { return nil }
  let base = (100 * (s.work + s.think)) / evaluable + (cfg.drowsyWeight * s.drowsy) / evaluable
  let penalty =
    Swift.min(cfg.habitPenaltyMax, cfg.habitPenalty * Double(m.habits))
    + Swift.min(cfg.interruptionPenaltyMax, cfg.interruptionPenalty * Double(Swift.max(0, m.interruptions - 1)))
  return Int(clamp(jsRound(base - penalty), 0, 100))
}

/// 手の動かし方の型(設計書 4.6)
public enum HandsStyle: String, Codable, Sendable {
  case output = "アウトプット型"
  case reflective = "熟考型"
  case balanced = "バランス型"
}

/// 集中の続き方の型(設計書 4.6)
public enum FocusPattern: String, Codable, Sendable {
  case slowStarter = "スロースターター型"
  case shortBurst = "短期集中型"
  case endurance = "持久型"
  case wavy = "波あり型"
}

public struct LearningStyle: Codable, Equatable, Sendable {
  public var hands: HandsStyle?
  /// 作業の時間 ÷(作業 + 思考)
  public var handRatio: Double?
  public var pattern: FocusPattern?
}

/// 学習スタイル(設計書 4.6)。
public func learningStyle(workSec: Double, thinkSec: Double, minuteScores: [Int?]) -> LearningStyle {
  let total = workSec + thinkSec
  var style = LearningStyle()
  if total > 0 {
    let handRatio = workSec / total
    style.handRatio = handRatio
    style.hands = handRatio >= 0.6 ? .output : handRatio <= 0.4 ? .reflective : .balanced
  }
  let scores = minuteScores.compactMap { $0 }.map(Double.init)
  if scores.count >= 30 {
    let n = scores.count / 3
    func avg(_ a: ArraySlice<Double>) -> Double { a.reduce(0, +) / Double(a.count) }
    let first = avg(scores.prefix(n))
    let last = avg(scores.suffix(n))
    let all = avg(scores[...])
    let sd = avg(scores.map { ($0 - all) * ($0 - all) }[...]).squareRoot()
    if last - first >= 10 {
      style.pattern = .slowStarter
    } else if first - last >= 15 {
      style.pattern = .shortBurst
    } else if all >= 70 && first - last < 10 {
      style.pattern = .endurance
    } else if sd >= 20 {
      style.pattern = .wavy
    }
  }
  return style
}

/// セッションのまとめ(設計書 3.14)
public struct SessionSummary: Codable, Sendable {
  public var totals: MinuteSecs
  /// 集中度を評価できた秒数
  public var studySec: Double
  public var awaySec: Double
  public var pausedSec: Double
  /// 1 分の集中度の平均
  public var avgFocus: Int?
  /// 集中度で重みをつけた学習時間(分)
  public var effectiveFocusMin: Double
  public var scores: [Int?]
  /// 出来事の回数(種類の rawValue ごと)
  public var counts: [String: Int]
  public var style: LearningStyle
}

/// セッションの記録と 1 分ごとの集計(設計書 3.14, 6.2 MINUTE_SCORE)。時刻はミリ秒。
public struct SessionRecorder: Sendable {
  public let startT: Double
  public let cfg: AnalysisConfig
  public let autoAway: Bool
  public private(set) var minutes: [MinuteRecord] = []
  public private(set) var events: [AnalysisEvent] = []

  public init(startT: Double, cfg: AnalysisConfig, autoAway: Bool = true) {
    self.startT = startT
    self.cfg = cfg
    self.autoAway = autoAway
  }

  private mutating func minuteIndex(_ t: Double) -> Int {
    let index = Swift.max(0, Int(((t - startT) / 60000).rounded(.down)))
    while minutes.count <= index { minutes.append(MinuteRecord(index: minutes.count)) }
    return index
  }

  public mutating func add(t: Double, dtSec: Double, kind: TimeKind) {
    if dtSec <= 0 { return }
    let i = minuteIndex(t)
    minutes[i].secs[kind] += dtSec
  }

  public mutating func addEvent(_ ev: AnalysisEvent) {
    events.append(ev)
    let i = minuteIndex(ev.t)
    if ev.type.isHabit { minutes[i].habits += 1 }
    if ev.type == .lookaway { minutes[i].interruptions += 1 }
  }

  public func scores() -> [Int?] {
    minutes.map { scoreMinute($0, cfg, autoAway: autoAway) }
  }

  public func summary() -> SessionSummary {
    var totals = MinuteSecs()
    for m in minutes {
      for k in TimeKind.allCases { totals[k] += m.secs[k] }
    }
    let scores = scores()
    let valid = scores.compactMap { $0 }
    var effectiveFocusMin = 0.0
    for (i, m) in minutes.enumerated() {
      if let s = scores[i] { effectiveFocusMin += (Double(s) / 100) * (m.secs.evaluable(autoAway: autoAway) / 60) }
    }
    var counts: [String: Int] = [:]
    for e in events { counts[e.type.rawValue, default: 0] += 1 }
    return SessionSummary(
      totals: totals,
      studySec: minutes.reduce(0) { $0 + $1.secs.evaluable(autoAway: autoAway) },
      awaySec: totals.away + (autoAway ? totals.absent : 0),
      pausedSec: totals.paused,
      avgFocus: valid.isEmpty ? nil : Int(jsRound(Double(valid.reduce(0, +)) / Double(valid.count))),
      effectiveFocusMin: effectiveFocusMin,
      scores: scores,
      counts: counts,
      style: learningStyle(workSec: totals.work, thinkSec: totals.think, minuteScores: scores)
    )
  }
}
