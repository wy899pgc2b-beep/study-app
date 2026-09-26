import Foundation

// 1 回の学習の流れ(開始の儀式 → 学習中 → 一時停止・休憩 → 終了)。画面・カメラ・音声から切り離した部分。
// 設計書 3.1・3.11・3.24・4.12、MVP の設計 3 章。時刻はすべてミリ秒。

/// 開始の儀式の段階(設計書 4.12)
public enum RitualStep: String, Codable, Sendable {
  /// 「目を閉じて、ひと呼吸」。目を閉じた状態を記録する
  case closeEyes
  /// 「目を開けて、教材を見てください」。目を開けた直後はまばたきが多いので記録に使わない
  case openEyes
  /// 正しい姿勢で教材を見た状態を記録する
  case posture
}

public enum PauseReason: String, Codable, Sendable {
  /// 画面に触れた
  case touch
  /// アプリを離れた
  case leftApp
}

public enum SessionPhase: Equatable, Sendable {
  case ritual(RitualStep)
  case studying
  case paused(PauseReason)
  /// 休憩中(カメラを止める)
  case onBreak
  case finished
}

/// 画面や音声に伝えること
public enum SessionCue: Equatable, Sendable {
  /// 儀式の次の段階に進んだ(案内を読み上げる)
  case ritual(RitualStep)
  /// 儀式の間に顔が映らず、基準を取れなかった(位置合わせからやり直す)
  case ritualFailed
  /// 目を閉じたときの記録ができなかった(判定はこれまでの基準で続ける)
  case closedReferenceMissing
  /// 学習の計測を始めた
  case started
  /// 休憩の時間になった
  case breakDue
  /// 休憩の時間が終わった
  case breakOver
  /// 判定の出来事(居眠り・姿勢・離席など)
  case event(AnalysisEvent)
}

/// 開始の儀式の時間(秒)。設計書 4.12:目を閉じた状態は約 3 秒、目を開けた直後の約 1 秒は使わない、姿勢は約 3 秒
public struct RitualTiming: Equatable, Sendable {
  /// 案内を聞いて目を閉じるまでの待ち
  public var closeLeadSec: Double = 3
  public var closedSec: Double = 3
  public var openDiscardSec: Double = 1
  public var postureSec: Double = 3

  public init() {}
}

/// 休憩タイマー(設計書 3.24、決定事項 D-9)
public struct BreakTimer: Equatable, Codable, Sendable {
  public var enabled: Bool
  public var studyMin: Int
  public var breakMin: Int

  public init(enabled: Bool = false, studyMin: Int = 25, breakMin: Int = 5) {
    self.enabled = enabled
    self.studyMin = studyMin
    self.breakMin = breakMin
  }

  /// 設定できる範囲(学習 10〜90 分・休憩 3〜30 分。5 分きざみの学習は画面の側で行う)
  public static let studyRange = 10...90
  public static let breakRange = 3...30
  public static let presets = [BreakTimer(enabled: true, studyMin: 25, breakMin: 5), BreakTimer(enabled: true, studyMin: 50, breakMin: 10)]
}

public struct StudySession: Sendable {
  public let cfg: AnalysisConfig
  public let setup: SetupStyle
  public let autoAway: Bool
  public let measuredEyeDeskCm: Double?
  public let timing: RitualTiming
  public let breakTimer: BreakTimer

  public private(set) var phase: SessionPhase = .ritual(.closeEyes)
  public private(set) var calibration: Calibration?
  public private(set) var recorder: SessionRecorder?
  public private(set) var lastOutput: AnalysisOutput?
  /// 休憩した秒数の合計
  public private(set) var breakSec = 0.0
  public private(set) var startT: Double?

  private var analyzer: Analyzer
  private var stepStartT: Double?
  private var closedFeatures: [Features] = []
  private var postureFeatures: [Features] = []
  private var lastT: Double?
  /// 休憩タイマーで数える、前の休憩から学習した秒数(一時停止・離席を除く)
  private var studySinceBreak = 0.0
  private var breakStartT: Double?
  private var breakOverSent = false

  public init(
    cfg: AnalysisConfig = AnalysisConfig(), setup: SetupStyle = .landscape, autoAway: Bool = true, measuredEyeDeskCm: Double? = 35,
    timing: RitualTiming = RitualTiming(), breakTimer: BreakTimer = BreakTimer()
  ) {
    self.cfg = cfg
    self.setup = setup
    self.autoAway = autoAway
    self.measuredEyeDeskCm = measuredEyeDeskCm
    self.timing = timing
    self.breakTimer = breakTimer
    self.analyzer = Analyzer(cfg: cfg, autoAway: autoAway, setup: setup)
  }

  /// 儀式を始める(位置合わせの後)
  public mutating func beginRitual(at t: Double) -> [SessionCue] {
    phase = .ritual(.closeEyes)
    stepStartT = t
    closedFeatures = []
    postureFeatures = []
    return [.ritual(.closeEyes)]
  }

  /// 1 フレーム分の特徴量を渡す。儀式の記録、判定、1 分ごとの集計を進める
  public mutating func process(_ f: Features) -> [SessionCue] {
    switch phase {
    case .ritual(let step):
      return ritualStep(step, f)
    case .studying:
      return studyStep(f)
    case .paused:
      // 一時停止の間も時間は流れる(学習時間には入れない)
      recordTime(f.t, .paused)
      return []
    case .onBreak:
      return breakStep(at: f.t)
    case .finished:
      return []
    }
  }

  /// カメラを止めている休憩中は、フレームの代わりに時刻だけを渡す
  public mutating func tick(at t: Double) -> [SessionCue] {
    if case .onBreak = phase { return breakStep(at: t) }
    return []
  }

  public mutating func pause(at t: Double, reason: PauseReason) {
    guard phase == .studying else { return }
    closeSpan(at: t, studying: true)
    phase = .paused(reason)
  }

  public mutating func resume(at t: Double) {
    guard case .paused = phase else { return }
    closeSpan(at: t, studying: false)
    phase = .studying
  }

  public mutating func startBreak(at t: Double) {
    guard phase == .studying || isPaused else { return }
    closeSpan(at: t, studying: !isPaused)
    phase = .onBreak
    breakStartT = t
    breakOverSent = false
  }

  /// 休憩を終えて学習に戻る(MVP の設計 3 章:位置の確認と姿勢の記録をしてから戻る)
  public mutating func endBreak(at t: Double) {
    guard phase == .onBreak, let bs = breakStartT else { return }
    breakSec += Swift.max(0, (t - bs) / 1000)
    breakStartT = nil
    studySinceBreak = 0
    lastT = t
    phase = .studying
  }

  /// 学習を終える。計測を始めていなければ nil
  @discardableResult
  public mutating func finish(at t: Double) -> SessionSummary? {
    switch phase {
    case .studying: closeSpan(at: t, studying: true)
    case .paused: closeSpan(at: t, studying: false)
    case .onBreak: endBreak(at: t)
    default: break
    }
    phase = .finished
    return recorder?.summary()
  }

  public var isPaused: Bool {
    if case .paused = phase { return true }
    return false
  }

  // MARK: - 儀式

  private mutating func ritualStep(_ step: RitualStep, _ f: Features) -> [SessionCue] {
    let s0 = stepStartT ?? f.t
    if stepStartT == nil { stepStartT = f.t }
    let el = (f.t - s0) / 1000
    switch step {
    case .closeEyes:
      if el >= timing.closeLeadSec { closedFeatures.append(f) }
      if el < timing.closeLeadSec + timing.closedSec { return [] }
      phase = .ritual(.openEyes)
      stepStartT = f.t
      return [.ritual(.openEyes)]
    case .openEyes:
      if el < timing.openDiscardSec { return [] }
      phase = .ritual(.posture)
      stepStartT = f.t
      postureFeatures = [f]
      return [.ritual(.posture)]
    case .posture:
      postureFeatures.append(f)
      if el < timing.postureSec { return [] }
      return finishRitual(at: f.t)
    }
  }

  private mutating func finishRitual(at t: Double) -> [SessionCue] {
    guard var cal = computeCalibration(postureFeatures, measuredEyeDeskCm: measuredEyeDeskCm, tiltDeg: setup.defaultTiltDeg) else {
      stepStartT = nil
      phase = .ritual(.closeEyes)
      return [.ritualFailed]
    }
    cal.closedRef = computeClosedReference(closedFeatures, cal, cfg)
    calibration = cal
    analyzer.setCalibration(cal)
    recorder = SessionRecorder(startT: t, cfg: cfg, autoAway: autoAway)
    startT = t
    lastT = t
    phase = .studying
    var cues: [SessionCue] = [.started]
    if cal.closedRef == nil { cues.insert(.closedReferenceMissing, at: 0) }
    return cues
  }

  // MARK: - 学習中

  private mutating func studyStep(_ f: Features) -> [SessionCue] {
    let out = analyzer.update(f)
    lastOutput = out
    let kind: TimeKind = out.away ? .away : TimeKind(out.state)
    let dt = recordTime(f.t, kind)
    if kind != .away && kind != .absent { studySinceBreak += dt }
    var cues: [SessionCue] = []
    for ev in out.events {
      recorder?.addEvent(ev)
      cues.append(.event(ev))
    }
    if breakTimer.enabled && studySinceBreak >= Double(breakTimer.studyMin) * 60 {
      startBreak(at: f.t)
      cues.append(.breakDue)
    }
    return cues
  }

  private mutating func breakStep(at t: Double) -> [SessionCue] {
    guard let bs = breakStartT, !breakOverSent, (t - bs) / 1000 >= Double(breakTimer.breakMin) * 60 else { return [] }
    breakOverSent = true
    return [.breakOver]
  }

  /// 前の時刻からの経過(最長 1 秒)を、kind として 1 分ごとの集計に入れる。試作品の app.js と同じ数え方
  @discardableResult
  private mutating func recordTime(_ t: Double, _ kind: TimeKind) -> Double {
    let dt = lastT.map { Swift.min(1, (t - $0) / 1000) } ?? 0
    lastT = t
    recorder?.add(t: t, dtSec: dt, kind: kind)
    return Swift.max(0, dt)
  }

  /// 一時停止・休憩・終了の直前までの時間を数える。学習中だった分は、直前の判定の状態として数える
  private mutating func closeSpan(at t: Double, studying: Bool) {
    if studying {
      let kind: TimeKind = lastOutput.map { $0.away ? .away : TimeKind($0.state) } ?? .think
      recordTime(t, kind)
    } else {
      recordTime(t, .paused)
    }
  }
}
