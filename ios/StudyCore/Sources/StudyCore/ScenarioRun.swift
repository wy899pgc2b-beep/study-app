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

/// 検証シナリオの進み具合と、場面ごとの記録
public struct ScenarioRun: Sendable {
  public let setup: SetupStyle
  public private(set) var samples: [String: [ScenarioSample]] = [:]
  public private(set) var position: Scenario.Position?
  public private(set) var finished = false
  private var index = -1
  private var inTransition: Bool?

  public init(setup: SetupStyle) {
    self.setup = setup
  }

  /// elapsedSec:計測を始めてからの秒数。dt・kind・output:このフレームの時間と判定(判定しなかったときは output が nil)
  public mutating func update(elapsedSec: Double, dt: Double, kind: TimeKind, output: AnalysisOutput?) -> [ScenarioCue] {
    guard !finished else { return [] }
    guard let pa = Scenario.phaseAt(elapsedSec) else {
      finished = true
      position = nil
      return [.done]
    }
    position = pa
    var cues: [ScenarioCue] = []
    if pa.index != index || pa.inTransition != inTransition {
      cues.append(pa.inTransition ? .phaseIntro(index: pa.index) : .phaseStart(index: pa.index))
      index = pa.index
      inTransition = pa.inTransition
    }
    if !pa.inTransition {
      let id = Scenario.phases[pa.index].id
      samples[id, default: []].append(ScenarioSample(phaseElapsed: pa.phaseElapsed, dt: dt, kind: kind, output: output))
    }
    return cues
  }

  public func results() -> [PhaseResult] {
    Scenario.phases.map { evaluatePhase($0, samples: samples[$0.id] ?? [], setup: setup) }
  }

  /// 読み上げる指示(「3つめ。顔を上げたまま、…」)
  public static func introSpeech(_ index: Int) -> String {
    "\(index + 1)つめ。\(Scenario.phases[index].speech)"
  }
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
  }

  public var version = 1
  public var app = "ツクエログ"
  public var appVersion: String
  public var prototypeVersion = AnalysisConfig.prototypeVersion
  public var createdAt: Date
  public var reason: String
  public var mode: String
  public var setup: SetupStyle
  public var cfg: AnalysisConfig
  public var calibration: Calibration?
  public var durationSec: Double
  public var summary: SessionSummary
  public var minutes: [Minute]
  public var events: [Event]
  public var scenario: [PhaseResult]?
  public var perf: Perf

  public init(
    appVersion: String, createdAt: Date, reason: String, mode: String, session: StudySession, summary: SessionSummary, durationSec: Double,
    scenario: [PhaseResult]?, perf: Perf
  ) {
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
