import Foundation

// 1 回の学習の流れ(設置位置ガイド → 開始の儀式 → 学習中 → 一時停止・休憩 → 終了)。画面・カメラ・音声から切り離した部分。
// 設計書 3.1・3.4・3.11・3.24・4.12、MVP の設計 3 章。時刻はすべてミリ秒。

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
  /// 設置位置ガイド
  case guide
  case ritual(RitualStep)
  case studying
  case paused(PauseReason)
  /// 休憩中(カメラを止める)
  case onBreak
  case finished
}

/// 画面や音声に伝えること
public enum SessionCue: Equatable, Sendable {
  /// 位置合わせを始めた(置き方の案内を読み上げる)
  case guideStarted(SetupStyle)
  /// 位置合わせで足りないもの(読み上げる)
  case guide(GuidePrompt)
  /// 位置が合った
  case guideReady
  /// 儀式の次の段階に進んだ(案内を読み上げる)
  case ritual(RitualStep)
  /// 儀式の間に顔が映らず、基準を取れなかった(位置合わせからやり直す)
  case ritualFailed
  /// 目を閉じたときの記録ができなかった(判定はこれまでの基準で続ける)
  case closedReferenceMissing
  /// 学習の計測を始めた
  case started
  /// 休憩の後、学習に戻った
  case resumed
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

  public private(set) var phase: SessionPhase = .guide
  public private(set) var calibration: Calibration?
  public private(set) var recorder: SessionRecorder?
  public private(set) var lastOutput: AnalysisOutput?
  /// 位置合わせの確認の項目(画面に並べる)
  public private(set) var guideChecks: [GuideCheck] = []
  /// 休憩した秒数の合計
  public private(set) var breakSec = 0.0
  /// 画面に触れた・アプリを離れた回数
  public private(set) var pauseCount = 0
  public private(set) var startT: Double?

  private var analyzer: Analyzer
  private var guide: PlacementGuide
  private var stepStartT: Double?
  private var closedFeatures: [Features] = []
  private var postureFeatures: [Features] = []
  private var lastT: Double?
  /// 休憩タイマーで数える、前の休憩から学習した秒数(一時停止・離席を除く)
  private var studySinceBreak = 0.0
  private var breakStartT: Double?
  private var breakOverSent = false
  /// 休憩の後の位置の確認中(儀式は姿勢の記録だけにする)
  private var returningFromBreak = false

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
    self.guide = PlacementGuide(setup: setup)
  }

  /// 位置合わせを始める(「始める」を押したとき)
  public mutating func beginGuide(at t: Double) -> [SessionCue] {
    phase = .guide
    guide = PlacementGuide(setup: setup)
    guideChecks = []
    return [.guideStarted(setup)]
  }

  /// 儀式を始める(位置が合ったとき。位置合わせを省いたときも)
  public mutating func beginRitual(at t: Double) -> [SessionCue] {
    let first: RitualStep = returningFromBreak ? .posture : .closeEyes
    phase = .ritual(first)
    stepStartT = t
    if !returningFromBreak { closedFeatures = [] }
    postureFeatures = []
    return [.ritual(first)]
  }

  /// 1 フレーム分の特徴量を渡す。位置合わせ、儀式の記録、判定、1 分ごとの集計を進める。
  /// deviceLandscape:端末が横向きか(重力から。位置合わせに使う)
  public mutating func process(_ f: Features, deviceLandscape: Bool? = nil) -> [SessionCue] {
    switch phase {
    case .guide:
      return guideStep(f, deviceLandscape: deviceLandscape)
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
    pauseCount += 1
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

  /// 休憩を終える。位置の確認と姿勢の記録をしてから学習に戻る(MVP の設計 3 章)
  public mutating func endBreak(at t: Double) -> [SessionCue] {
    guard phase == .onBreak, let bs = breakStartT else { return [] }
    breakSec += Swift.max(0, (t - bs) / 1000)
    breakStartT = nil
    studySinceBreak = 0
    returningFromBreak = true
    return beginGuide(at: t)
  }

  /// 学習を終える。計測を始めていなければ nil
  @discardableResult
  public mutating func finish(at t: Double) -> SessionSummary? {
    switch phase {
    case .studying: closeSpan(at: t, studying: true)
    case .paused: closeSpan(at: t, studying: false)
    case .onBreak:
      if let bs = breakStartT { breakSec += Swift.max(0, (t - bs) / 1000) }
      breakStartT = nil
    default: break
    }
    phase = .finished
    return recorder?.summary()
  }

  public var isPaused: Bool {
    if case .paused = phase { return true }
    return false
  }

  // MARK: - 位置合わせと儀式

  private mutating func guideStep(_ f: Features, deviceLandscape: Bool?) -> [SessionCue] {
    let step = guide.update(f, deviceLandscape: deviceLandscape)
    guideChecks = step.checks
    if step.ready { return [.guideReady] + beginRitual(at: f.t) }
    return step.prompts.map { .guide($0) }
  }

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
      // 顔が映っていなかった:位置合わせからやり直す
      return [.ritualFailed] + beginGuide(at: t)
    }
    if returningFromBreak {
      // 休憩の後は姿勢だけを記録し直し、目を閉じたときの基準は前の値を使う
      cal.closedRef = calibration?.closedRef
    } else {
      cal.closedRef = computeClosedReference(closedFeatures, cal, cfg)
    }
    calibration = cal
    analyzer.setCalibration(cal)
    lastT = t
    phase = .studying
    if returningFromBreak, recorder != nil {
      returningFromBreak = false
      return [.resumed]
    }
    returningFromBreak = false
    recorder = SessionRecorder(startT: t, cfg: cfg, autoAway: autoAway)
    startT = t
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
