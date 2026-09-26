import Foundation

/// 検証モードで伝えること(試作品の app.js の scenarioStep と同じ区切り)
public enum ScenarioCue: Equatable, Sendable {
  /// 次の場面の指示を読み上げる(「3つめ。…」)。前の場面の終わりの音も鳴らす
  case phaseIntro(index: Int)
  /// 場面の採点を始める(短い音)
  case phaseStart(index: Int)
  /// 全部の場面が終わった
  case done
}

/// 検証シナリオの進み具合と、場面ごとの記録。
/// 9 場面の一部だけを行える(前に飛ばした場面を、あとで行うとき)。一時停止したら今の場面を指示からやり直すか、飛ばす
public struct ScenarioRun: Sendable {
  public let setup: SetupStyle
  /// この回に行う場面(Scenario.phases の番号。順番どおり)
  public let order: [Int]
  public private(set) var samples: [String: [ScenarioSample]] = [:]
  public private(set) var position: Scenario.Position?
  public private(set) var finished = false
  /// 最後まで行った場面と、飛ばした場面(id)
  public private(set) var completed: [String] = []
  public private(set) var skipped: [String] = []
  private var step = 0
  /// 今の場面の指示を始めた時刻(計測を始めてからの秒数)。nil なら次の update から始める
  private var stepStartSec: Double?
  private var announcedStep: Int?
  private var announcedTransition: Bool?

  /// phases:行う場面の番号(省くと 9 場面すべて)
  public init(setup: SetupStyle, phases: [Int]? = nil) {
    self.setup = setup
    order = (phases ?? Array(Scenario.phases.indices)).filter { Scenario.phases.indices.contains($0) }.sorted()
  }

  /// この回に行う場面の数と、かかる秒数
  public var count: Int { order.count }
  public var totalSec: Double { order.reduce(0) { $0 + Scenario.transitionSec + Scenario.phases[$1].sec } }

  /// この回の中で何番目か(1 から)
  public func number(ofPhase index: Int) -> Int { (order.firstIndex(of: index) ?? 0) + 1 }

  /// 今の場面(Scenario.phases の番号。終わっていれば nil)
  public var currentIndex: Int? { !finished && step < order.count ? order[step] : nil }

  /// まだ最後まで行っていない場面(飛ばした場面、途中でやめた場面、まだ始めていない場面。id)
  public var remaining: [String] { order.map { Scenario.phases[$0].id }.filter { !completed.contains($0) } }

  /// elapsedSec:計測を始めてからの秒数。dt・kind・output:このフレームの時間と判定(判定しなかったときは output が nil)
  public mutating func update(elapsedSec: Double, dt: Double, kind: TimeKind, output: AnalysisOutput?) -> [ScenarioCue] {
    guard !finished else { return [] }
    if stepStartSec == nil { stepStartSec = elapsedSec }
    // 場面の終わりを過ぎたら次の場面へ。続けて行うときは時刻を足していく(試作品の phaseAt と同じ区切りになる)
    while step < order.count, let s0 = stepStartSec, elapsedSec >= s0 + stepSec(step) {
      completed.append(Scenario.phases[order[step]].id)
      stepStartSec = s0 + stepSec(step)
      step += 1
    }
    guard step < order.count, let s0 = stepStartSec else {
      finished = true
      position = nil
      return [.done]
    }
    let index = order[step]
    let phaseStart = s0 + Scenario.transitionSec
    let inTransition = elapsedSec < phaseStart
    let pa = Scenario.Position(index: index, inTransition: inTransition, phaseElapsed: inTransition ? 0 : elapsedSec - phaseStart)
    position = pa
    var cues: [ScenarioCue] = []
    if step != announcedStep || inTransition != announcedTransition {
      cues.append(inTransition ? .phaseIntro(index: index) : .phaseStart(index: index))
      announcedStep = step
      announcedTransition = inTransition
    }
    if !inTransition {
      samples[Scenario.phases[index].id, default: []].append(ScenarioSample(phaseElapsed: pa.phaseElapsed, dt: dt, kind: kind, output: output))
    }
    return cues
  }

  /// 今の場面を飛ばす(あとで行う)。次の update から、次の場面の指示を始める
  public mutating func skipCurrent() {
    guard !finished, step < order.count else { return }
    let id = Scenario.phases[order[step]].id
    samples[id] = nil
    if !skipped.contains(id) { skipped.append(id) }
    step += 1
    stepStartSec = nil
    announcedStep = nil
    position = nil
  }

  /// 今の場面を、指示からやり直す(一時停止から戻ったとき。途中までの記録は捨てる)
  public mutating func restartCurrent() {
    guard !finished, step < order.count else { return }
    samples[Scenario.phases[order[step]].id] = nil
    stepStartSec = nil
    announcedStep = nil
    position = nil
  }

  /// 最後まで行った場面の採点(順番どおり)
  public func results() -> [PhaseResult] {
    order.map { Scenario.phases[$0] }.filter { completed.contains($0.id) }.map {
      evaluatePhase($0, samples: samples[$0.id] ?? [], setup: setup)
    }
  }

  /// 読み上げる指示(「3つめ。顔を上げたまま、…」)。最初の場面では、場面の数も伝える
  public func introSpeech(_ index: Int) -> String {
    let n = number(ofPhase: index)
    let head = n == 1 ? "全部で\(order.count)場面です。" : ""
    return "\(head)\(n)つめ。\(Scenario.phases[index].speech)"
  }

  private func stepSec(_ step: Int) -> Double { Scenario.transitionSec + Scenario.phases[order[step]].sec }
}

/// 1 回の学習の記録の書き出し(試作品の結果の JSON と同じ形。映像・画像・特徴点は含めない)。
/// 検証モードの結果や自由な学習の記録を、技術検証の記録と比べるために使う
public struct SessionExport: Encodable, Sendable {
  public struct Minute: Encodable, Sendable {
    public var index: Int
    public var secs: MinuteSecs
    public var habits: Int
    public var interruptions: Int
    public var score: Int?
  }

  public struct Event: Encodable, Sendable {
    public var type: String
    public var sec: Double
  }

  public struct Perf: Encodable, Sendable {
    public var avgMs: Double
    public var p95Ms: Double
    public var effectiveFps: Double
    public var errors: Int
    public var videoSize: String?
    public var device: String
    public var fovLongSideDeg: Double?
    /// 電池の残り(0〜1)と 1 時間あたりの減り(%)。充電していたか。いちばん熱かった段階(MVP の完了の条件 6 を確かめる)
    public var batteryStart: Double? = nil
    public var batteryEnd: Double? = nil
    public var batteryPerHour: Double? = nil
    public var charging: Bool? = nil
    public var thermalMax: String? = nil
    public var lowPowerMode: Bool? = nil
  }

  public var version = 1
  public var app = "ツクエログ"
  public var appVersion: String
  public var prototypeVersion = AnalysisConfig.prototypeVersion
  public var createdAt: Date
  public var reason: String
  public var mode: String
  /// 学習項目(検証モードでは nil)
  public var subject: String?
  public var setup: SetupStyle
  public var cfg: AnalysisConfig
  public var calibration: Calibration?
  public var durationSec: Double
  public var summary: SessionSummary
  public var minutes: [Minute]
  public var events: [Event]
  public var scenario: [PhaseResult]?
  /// 検証モードで、この回に最後まで行わなかった場面(あとで行う)
  public var scenarioRemaining: [String]?
  public var perf: Perf

  public init(
    appVersion: String, createdAt: Date, reason: String, mode: String, session: StudySession, summary: SessionSummary, durationSec: Double,
    scenario: [PhaseResult]?, scenarioRemaining: [String]? = nil, perf: Perf, subject: String? = nil
  ) {
    self.subject = subject
    self.appVersion = appVersion
    self.createdAt = createdAt
    self.reason = reason
    self.mode = mode
    setup = session.setup
    cfg = session.cfg
    calibration = session.calibration
    self.durationSec = durationSec
    self.summary = summary
    let recorder = session.recorder
    let start = recorder?.startT ?? 0
    minutes = (recorder?.minutes ?? []).enumerated().map { i, m in
      Minute(index: m.index, secs: m.secs, habits: m.habits, interruptions: m.interruptions, score: i < summary.scores.count ? summary.scores[i] : nil)
    }
    events = (recorder?.events ?? []).map { Event(type: $0.type.rawValue, sec: jsRound(($0.t - start) / 100) / 10) }
    self.scenario = scenario
    self.scenarioRemaining = scenarioRemaining
    self.perf = perf
  }

  /// 読みやすい JSON
  public func json() throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    return try enc.encode(self)
  }
}

/// 解析の速さのまとめ
public func perfSummary(_ processingMs: [Double], frames: Int, spanSec: Double, errors: Int, videoSize: String?, device: String, fov: Double?)
  -> SessionExport.Perf
{
  let sorted = processingMs.sorted()
  let avg = sorted.isEmpty ? 0 : sorted.reduce(0, +) / Double(sorted.count)
  let p95 = sorted.isEmpty ? 0 : sorted[Swift.min(sorted.count - 1, Int((Double(sorted.count) * 0.95).rounded(.down)))]
  return SessionExport.Perf(
    avgMs: avg, p95Ms: p95, effectiveFps: spanSec > 0 ? Double(frames - 1) / spanSec : 0, errors: errors, videoSize: videoSize, device: device,
    fovLongSideDeg: fov)
}
