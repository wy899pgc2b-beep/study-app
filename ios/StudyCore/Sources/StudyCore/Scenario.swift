import Foundation

// 検証シナリオ(試作品の scenario.js と同じ場面・同じ採点)。音声の指示どおりに動いてもらい、各場面で正しく判定できたかを調べる。
// MVP の完了の条件 2(9 場面のうち 8 場面以上に合格)を、アプリの検証モードで確かめるのに使う。

public enum Scenario {
  /// 場面と場面の間の、指示を読み上げる時間(秒)。この間は採点しない
  public static let transitionSec = 5.0

  public struct Expect: Sendable {
    public var states: [String]?
    public var minShare: Double?
    public var mustReach: String?
    public var mustAway = false
    public var flag: String?
    public var events: [String]?
    public var minEvents: Int?
    public var maxFalseSleep: Double?
  }

  public struct Phase: Sendable {
    public var id: String
    public var label: String
    public var speech: String
    public var sec: Double
    public var graceSec: Double
    public var expect: Expect
    public var purpose: String
    /// この置き方では対象外(理由)
    public var notIn: [SetupStyle: String] = [:]
  }

  public static let phases: [Phase] = [
    Phase(
      id: "read", label: "教材を読む", speech: "教材を見下ろして、読んでください", sec: 25, graceSec: 3,
      expect: Expect(states: ["think"], minShare: 0.6, maxFalseSleep: 0.05), purpose: "下を向いて読んでいるときに、居眠りや作業と誤判定しないか"),
    Phase(
      id: "write", label: "書く", speech: "ペンを持って、ノートに文字を書いてください", sec: 25, graceSec: 3,
      expect: Expect(states: ["work"], minShare: 0.5), purpose: "ペンを持って書いている時間を作業と判定できるか",
      notIn: [.flat: "平置きでは手元が映らないため対象外"]),
    Phase(
      id: "eyes", label: "目を閉じる", speech: "顔を上げたまま、目を閉じてください。音が鳴るまで開けないでください", sec: 25, graceSec: 4,
      expect: Expect(states: ["drowsy", "sleep"], minShare: 0.6, mustReach: "sleep"), purpose: "目を閉じた居眠りを検知できるか(10 秒で居眠りと判定)"),
    Phase(
      id: "doze", label: "前に傾いて目を閉じる", speech: "少し前に傾いて、目を閉じてください。いつもの居眠りの姿勢で、音が鳴るまで続けてください", sec: 25,
      graceSec: 4, expect: Expect(states: ["drowsy", "sleep"], minShare: 0.6, mustReach: "sleep"),
      purpose: "ふだんの居眠りの姿勢(少し前に傾いて目を閉じる)を検知できるか"),
    Phase(
      id: "facedown", label: "机に伏せる", speech: "机に顔を伏せて、居眠りのまねをしてください。音が鳴るまで続けてください", sec: 35, graceSec: 5,
      expect: Expect(mustReach: "sleep"), purpose: "机に伏せた居眠りを検知できるか(20 秒で居眠りと判定)"),
    Phase(
      id: "lookaway", label: "よそ見", speech: "顔を横に向けて、よそ見をしてください", sec: 15, graceSec: 4,
      expect: Expect(states: ["lookaway"], minShare: 0.6), purpose: "よそ見を検知できるか"),
    Phase(
      id: "touch", label: "顔や頭を触る", speech: "顔や頭を、ときどき触ってください", sec: 20, graceSec: 2,
      expect: Expect(events: ["habit_face", "habit_head", "chin_rest"], minEvents: 2), purpose: "癖(顔や頭を触る)を検出できるか"),
    Phase(
      id: "close", label: "顔を机に近づける", speech: "顔を机に近づけて、のぞき込むような姿勢をしてください", sec: 15, graceSec: 3,
      expect: Expect(minShare: 0.5, flag: "tooClose"), purpose: "目と机の距離が近すぎることを検知できるか"),
    Phase(
      id: "leave", label: "離席", speech: "席を立って、カメラに映らない所まで離れてください。音が鳴ったら戻ってください", sec: 40, graceSec: 4,
      expect: Expect(states: ["absent"], minShare: 0.6, mustAway: true), purpose: "離席を検知できるか(20 秒で離席と判定)"),
  ]

  public static var totalSec: Double { phases.reduce(0) { $0 + transitionSec + $1.sec } }

  /// 場面ごとに記録する数値(結果の JSON に入る)
  public static let diagnosticMetrics = [
    "handSpeed", "fingerSpeed", "pinch", "penGrip", "handsCount", "handFaceDist", "touchHandScale", "handY", "faceTopY", "handOnHead",
    "blink", "earRatio", "eyesClosed", "closedScore", "closedScoreSmooth", "eyeLookDown", "eyeLookDownSmooth", "eyeLookUp",
    "eyeLookSide", "jawOpen", "writeShare", "handScale", "yawDev", "pitchUp", "eyeDeskCm", "headRatio", "slouchRel", "faceVisible",
    "faceRate", "dozeShadow", "headMotion", "lookingDown", "crownRatio", "crownDelta", "hairFrac", "personFrac", "segHead",
    "covering", "handOnFace", "poseVisible", "hairShrunk", "cameraTiltDeg",
  ]

  public struct Position: Equatable, Sendable {
    public var index: Int
    public var inTransition: Bool
    public var phaseElapsed: Double
  }

  /// 経過秒数から、今どの場面かを返す。終わっていれば nil
  public static func phaseAt(_ elapsedSec: Double) -> Position? {
    var t = 0.0
    for (i, p) in phases.enumerated() {
      if elapsedSec < t + transitionSec { return Position(index: i, inTransition: true, phaseElapsed: 0) }
      t += transitionSec
      if elapsedSec < t + p.sec { return Position(index: i, inTransition: false, phaseElapsed: elapsedSec - t) }
      t += p.sec
    }
    return nil
  }
}

/// 採点に使う 1 フレーム分の記録
public struct ScenarioSample: Codable, Sendable {
  public var phaseElapsed: Double
  public var dt: Double
  /// 状態の名前(work・think…。判定しなかったフレームは away・paused)
  public var state: String
  public var away: Bool
  public var flags: [String: Bool]
  /// 記録の値(判定しなかったフレームは nil)
  public var metrics: [String: Double]?
  public var closedBy: String?
  public var events: [String]

  public init(
    phaseElapsed: Double, dt: Double, state: String, away: Bool, flags: [String: Bool], metrics: [String: Double]?, closedBy: String?,
    events: [String]
  ) {
    self.phaseElapsed = phaseElapsed
    self.dt = dt
    self.state = state
    self.away = away
    self.flags = flags
    self.metrics = metrics
    self.closedBy = closedBy
    self.events = events
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    phaseElapsed = try c.decode(Double.self, forKey: .phaseElapsed)
    dt = try c.decode(Double.self, forKey: .dt)
    state = try c.decode(String.self, forKey: .state)
    away = try c.decode(Bool.self, forKey: .away)
    flags = try c.decodeIfPresent([String: Bool].self, forKey: .flags) ?? [:]
    // 値のない項目(null)は入れない
    metrics = try c.decodeIfPresent([String: Double?].self, forKey: .metrics).map { $0.compactMapValues { $0 } }
    closedBy = try c.decodeIfPresent(String.self, forKey: .closedBy)
    events = try c.decodeIfPresent([String].self, forKey: .events) ?? []
  }

  /// 判定の結果から作る
  public init(phaseElapsed: Double, dt: Double, kind: TimeKind, output: AnalysisOutput?) {
    self.phaseElapsed = phaseElapsed
    self.dt = dt
    state = output?.state.rawValue ?? kind.rawValue
    away = kind == .away
    if let o = output {
      flags = [
        "writing": o.flags.writing, "eyesClosed": o.flags.eyesClosed, "tooClose": o.flags.tooClose, "slouch": o.flags.slouch,
        "tilt": o.flags.tilt, "habit": o.flags.habit,
      ]
      metrics = o.metrics.numericValues
      closedBy = o.metrics.closedBy?.rawValue
      events = o.events.map(\.type.rawValue)
    } else {
      flags = [:]
      metrics = nil
      closedBy = nil
      events = []
    }
  }
}

public struct MetricStat: Codable, Equatable, Sendable {
  public var p10: Double
  public var median: Double
  public var p90: Double
  public var mean: Double
  public var n: Int
}

public struct ScenarioTimeline: Codable, Equatable, Sendable {
  public var state: String
  public var face: String
  public var closed: String
  public var grip: String
  public var doze: String
  public var bow: String
  public var head: String
  public var write: String
  public var by: String
}

/// 1 つの場面の採点(試作品の evaluatePhase と同じ)
public struct PhaseResult: Codable, Sendable {
  public var id: String
  public var label: String
  public var purpose: String
  public var seconds: Double
  public var share: [String: Double]
  public var notes: [String]
  public var metrics: [String: MetricStat]
  public var timeline: ScenarioTimeline
  /// 合格・不合格。対象外や判定できなかったときは nil
  public var pass: Bool?
  public var score: Double?
  public var flag: String?
  public var flagLabel: String?
  public var eventCount: Int?
}

private func jsQuantile(_ sorted: [Double], _ q: Double) -> Double? {
  guard !sorted.isEmpty else { return nil }
  let pos = Double(sorted.count - 1) * q
  let lo = Int(pos.rounded(.down))
  let hi = Int(pos.rounded(.up))
  return sorted[lo] + (sorted[hi] - sorted[lo]) * (pos - Double(lo))
}

/// 数値の分布(10%・中央値・90%)。小数第 3 位まで
public func metricStats(_ samples: [ScenarioSample], keys: [String] = Scenario.diagnosticMetrics) -> [String: MetricStat] {
  var out: [String: MetricStat] = [:]
  let r = { (x: Double) in jsRound(x * 1000) / 1000 }
  for key in keys {
    let v = samples.compactMap { $0.metrics?[key] }.filter(\.isFinite).sorted()
    if v.isEmpty { continue }
    let mean = v.reduce(0, +) / Double(v.count)
    out[key] = MetricStat(
      p10: r(jsQuantile(v, 0.1)!), median: r(jsQuantile(v, 0.5)!), p90: r(jsQuantile(v, 0.9)!), mean: r(mean), n: v.count)
  }
  return out
}

/// いちばん多いもの(同じ数なら、先に出てきたもの)
private func majority(_ items: [String]) -> String? {
  var order: [String] = []
  var counts: [String: Int] = [:]
  for x in items {
    if counts[x] == nil { order.append(x) }
    counts[x, default: 0] += 1
  }
  var best: String?
  for k in order where best == nil || counts[k]! > counts[best!]! { best = k }
  return best
}

/// 1 秒ごとの様子を文字列にする(しきい値の調整用)。記号の意味は試作品の scenario.js の phaseTimeline を参照
public func phaseTimeline(_ samples: [ScenarioSample], sec: Double) -> ScenarioTimeline {
  let n = Int(sec.rounded(.up))
  var buckets = [[ScenarioSample]](repeating: [], count: n)
  for s in samples {
    let i = Swift.min(n - 1, Int(s.phaseElapsed.rounded(.down)))
    if i >= 0 { buckets[i].append(s) }
  }
  let stateLetters = ["work": "w", "think": "t", "lookaway": "l", "drowsy": "d", "sleep": "s", "absent": "a", "away": "A", "paused": "p"]
  let closedLetters = ["ear": "e", "earBlink": "b", "blink": "k", "down": "d", "personal": "p", ".": "."]
  func flag(_ b: [ScenarioSample], _ key: String) -> String {
    let v = b.compactMap { $0.metrics?[key] }.filter { $0 == 0 || $0 == 1 }
    if v.isEmpty { return "-" }
    return v.reduce(0, +) / Double(v.count) >= 0.5 ? "1" : "0"
  }
  func line(_ f: ([ScenarioSample]) -> String) -> String { buckets.map(f).joined() }
  return ScenarioTimeline(
    state: line { b in
      if b.isEmpty { return "-" }
      let key = b.contains(where: \.away) ? "away" : majority(b.map(\.state)) ?? ""
      return stateLetters[key] ?? "?"
    },
    face: line { flag($0, "faceVisible") },
    closed: line { flag($0, "eyesClosed") },
    grip: line { flag($0, "penGrip") },
    doze: line { flag($0, "dozeShadow") },
    bow: line { flag($0, "lookingDown") },
    head: line { flag($0, "segHead") },
    write: line { flag($0, "writing") },
    by: line { b in
      let v = b.filter { $0.metrics != nil }.map { $0.closedBy ?? "." }
      if v.isEmpty { return "-" }
      return closedLetters[majority(v) ?? ""] ?? "?"
    }
  )
}

/// 1 つの場面を採点する(試作品の evaluatePhase と同じ条件)
public func evaluatePhase(_ phase: Scenario.Phase, samples: [ScenarioSample], setup: SetupStyle) -> PhaseResult {
  let used = samples.filter { $0.phaseElapsed >= phase.graceSec }
  let total = used.reduce(0) { $0 + $1.dt }
  var share: [String: Double] = [:]
  for s in used { share[s.state, default: 0] += s.dt }
  for k in share.keys { share[k] = total > 0 ? share[k]! / total : 0 }

  var result = PhaseResult(
    id: phase.id, label: phase.label, purpose: phase.purpose, seconds: total, share: share, notes: [], metrics: metricStats(used),
    timeline: phaseTimeline(samples, sec: phase.sec))
  if let reason = phase.notIn[setup] {
    result.notes.append(reason)
    return result
  }
  if total < 3 {
    result.notes.append("判定できたフレームが少なすぎます")
    return result
  }

  let e = phase.expect
  var checks: [Bool] = []
  if let states = e.states {
    let hit = states.reduce(0) { $0 + (share[$1] ?? 0) }
    result.score = hit
    checks.append(hit >= (e.minShare ?? 0))
  }
  if let reach = e.mustReach {
    let reached = used.contains { $0.state == reach }
    result.notes.append(reached ? "居眠りの判定まで到達" : "居眠りの判定まで到達せず")
    checks.append(reached)
  }
  if e.mustAway {
    let away = used.contains(where: \.away)
    result.notes.append(away ? "離席と判定" : "離席と判定されず")
    checks.append(away)
  }
  if let flag = e.flag {
    let flagged = used.reduce(0) { $0 + ($1.flags[flag] == true ? $1.dt : 0) } / total
    result.flag = flag
    result.flagLabel = ["habit": "癖を検出", "tooClose": "近すぎと判定"][flag] ?? flag
    result.score = flagged
    checks.append(flagged >= (e.minShare ?? 0))
  }
  if let minEvents = e.minEvents {
    let wanted = Set(e.events ?? [])
    let count = samples.reduce(0) { $0 + $1.events.filter { wanted.contains($0) }.count }
    result.eventCount = count
    result.notes.append("癖を \(count) 回検出")
    checks.append(count >= minEvents)
  }
  if let maxFalse = e.maxFalseSleep {
    let falseSleep = (share["drowsy"] ?? 0) + (share["sleep"] ?? 0)
    result.notes.append("居眠りの誤判定 \(Int(jsRound(falseSleep * 100)))%")
    checks.append(falseSleep <= maxFalse)
  }
  result.pass = checks.allSatisfy { $0 }
  return result
}

extension AnalysisMetrics {
  /// 数値の記録(0/1 の真偽を含む)を、名前と値の組にする。値のない項目は入れない
  public var numericValues: [String: Double] {
    var out: [String: Double] = [:]
    for child in Mirror(reflecting: self).children {
      guard let label = child.label else { continue }
      switch child.value {
      case let v as Double: out[label] = v
      case let v as Int: out[label] = Double(v)
      case let v as Double?: if let v { out[label] = v }
      case let v as Int?: if let v { out[label] = Double(v) }
      default: break
      }
    }
    return out
  }
}
