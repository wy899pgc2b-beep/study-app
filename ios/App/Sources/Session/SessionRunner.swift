import Foundation
import Observation
import QuartzCore
import StudyCore

/// 1 回の学習を動かす:カメラ → 端末内 AI → 特徴量 → StudySession(位置合わせ・判定・集計)→ 画面と音。
/// 解析はカメラのフレームの列で行い、StudySession と画面の状態はメインスレッドで持つ。
@MainActor
@Observable
final class SessionRunner {
  enum Status: Equatable {
    case idle
    case preparing
    case running
    case failed(String)
  }

  private(set) var status: Status = .idle
  private(set) var phase: SessionPhase?
  private(set) var guideChecks: [GuideCheck] = []
  private(set) var summary: SessionSummary?
  private(set) var card: ResultCard?
  /// 確認用の表示(開発中だけ使う)
  private(set) var debug = DebugInfo()
  private(set) var breakEndsAt: Date?

  struct DebugInfo: Equatable {
    var fps = 0.0
    var processingMs = 0.0
    var tiltDeg: Double?
    var state: String = "—"
    var faceVisible = false
    var handsCount = 0
    var rotation = "—"
    var lastEvent: String = "—"
    var errors = 0
  }

  private var session: StudySession?
  private var camera: CameraSource?
  private var pipeline: FramePipeline?
  private let motion = MotionSensor()
  private let voice = VoiceOutput()
  private let sound = SoundPlayer()
  private var frameTimes: [Double] = []
  private var breakTimer: Timer?
  private var lastDrowsyChimeT: Double?

  static func now() -> Double { CACurrentMediaTime() * 1000 }

  func start(settings: StudySettings) async {
    guard status == .idle || isFailed else { return }
    status = .preparing
    summary = nil
    card = nil
    guard await CameraSource.requestAccess() else {
      status = .failed("カメラの使用が許可されていません。設定アプリで許可すると、判定を使えます")
      return
    }
    do {
      // モデルの読み込みは重いので、メインスレッドの外で行う
      let vision = try await Task.detached(priority: .userInitiated) { try VisionEngine() }.value
      let camera = CameraSource()
      try camera.configure()
      let cfg = AnalysisConfig()
      camera.fps = cfg.analysisFps
      let pipeline = FramePipeline(vision: vision, motion: motion, cfg: cfg)
      camera.onFrame = { [weak self, pipeline] pixelBuffer, ms in
        do {
          let result = try pipeline.process(pixelBuffer, timestampMs: ms)
          Task { @MainActor in self?.handle(result) }
        } catch {
          Task { @MainActor in self?.debug.errors += 1 }
        }
      }
      self.camera = camera
      self.pipeline = pipeline
      var s = StudySession(
        cfg: cfg, setup: settings.setup, autoAway: true, measuredEyeDeskCm: settings.eyeDeskCm, breakTimer: settings.breakTimer)
      let cues = s.beginGuide(at: Self.now())
      session = s
      phase = s.phase
      motion.start()
      camera.start()
      status = .running
      handle(cues)
    } catch {
      status = .failed(error.localizedDescription)
    }
  }

  /// 位置合わせを省いて、開始の儀式に進む
  func skipGuide() {
    guard phase == .guide, let cues = session?.beginRitual(at: Self.now()) else { return }
    phase = session?.phase
    handle(cues)
  }

  func pause(_ reason: PauseReason) {
    guard phase == .studying else { return }
    session?.pause(at: Self.now(), reason: reason)
    phase = session?.phase
    sound.stopAlarm()
  }

  func resume() {
    session?.resume(at: Self.now())
    phase = session?.phase
  }

  func endBreak() {
    breakTimer?.invalidate()
    breakTimer = nil
    breakEndsAt = nil
    let cues = session?.endBreak(at: Self.now()) ?? []
    phase = session?.phase
    camera?.start()
    handle(cues)
  }

  /// 学習を終え、結果を返す(計測を始める前なら nil)
  @discardableResult
  func finish() -> SessionSummary? {
    let result = session?.finish(at: Self.now())
    if let result, let s = session {
      card = Self.makeCard(result, session: s)
      sound.gentle()
    }
    stopDevices()
    summary = result
    phase = .finished
    status = .idle
    session = nil
    return result
  }

  /// 結果カードを作り、次に同じ文を続けないよう覚えておく
  private static func makeCard(_ summary: SessionSummary, session: StudySession) -> ResultCard {
    let defaults = UserDefaults.standard
    // 過去 7 日の集中時間は、端末の DB を作ってから渡す(今は比べる記録がない)
    let input = ResultCardInput(
      summary: summary, events: session.recorder?.events ?? [], pauseCount: session.pauseCount, recentFocusMin: [],
      previousPraise: defaults.string(forKey: "lastPraise"), previousNextStep: defaults.string(forKey: "lastNextStep"))
    let card = buildResultCard(input)
    defaults.set(card.praise, forKey: "lastPraise")
    defaults.set(card.nextStep, forKey: "lastNextStep")
    return card
  }

  private var isFailed: Bool {
    if case .failed = status { return true }
    return false
  }

  private func stopDevices() {
    breakTimer?.invalidate()
    breakTimer = nil
    breakEndsAt = nil
    sound.stopAlarm()
    camera?.stop()
    camera?.onFrame = nil
    camera = nil
    pipeline = nil
    motion.stop()
    voice.stop()
  }

  private func handle(_ result: FramePipeline.Result) {
    guard session != nil else { return }
    let f = result.features
    let cues = session?.process(f, deviceLandscape: result.deviceLandscape) ?? []
    phase = session?.phase
    if phase == .guide { guideChecks = session?.guideChecks ?? [] }
    frameTimes.append(f.t)
    frameTimes.removeAll { f.t - $0 > 3000 }
    if let first = frameTimes.first, frameTimes.count > 1, f.t > first {
      debug.fps = Double(frameTimes.count - 1) / ((f.t - first) / 1000)
    }
    debug.processingMs = result.processingMs
    debug.tiltDeg = f.cameraTiltDeg
    debug.faceVisible = f.faceVisible
    debug.handsCount = f.hands.count
    debug.rotation = result.rotation.rawValue
    if let out = session?.lastOutput { debug.state = out.away ? "離席中" : out.state.label }
    handle(cues)
  }

  private func handle(_ cues: [SessionCue]) {
    for cue in cues {
      switch cue {
      case .guideStarted(let setup):
        voice.say(PlacementGuide.introSpeech(setup), interrupt: true)
      case .guide(let prompt):
        voice.say(prompt.speech)
      case .guideReady:
        sound.ok()
        voice.say("位置はOKです", interrupt: true)
      case .ritual(.closeEyes):
        voice.say("目を閉じて、ひと呼吸してください")
      case .ritual(.openEyes):
        sound.ok()
        voice.say("目を開けて、教材を見てください", interrupt: true)
      case .ritual(.posture):
        // 休憩の後は、目を閉じる段階を行わずに姿勢を記録する
        if session?.startT != nil { voice.say("教材を見てください") }
      case .ritualFailed:
        voice.say("顔が映っていなかったため、もう一度位置を合わせます", interrupt: true)
      case .closedReferenceMissing:
        voice.say("目を閉じたときの記録ができませんでした。このまま始めます")
      case .started:
        sound.gentle()
        voice.say("学習を始めます")
      case .resumed:
        sound.gentle()
        voice.say("学習に戻ります")
      case .breakDue:
        startBreakCountdown()
      case .breakOver:
        sound.gentle()
        voice.say("休憩の時間が終わりました。準備ができたら、休憩を終えるを押してください")
      case .event(let ev):
        debug.lastEvent = ev.type.rawValue
        notify(ev)
      }
    }
  }

  private func startBreakCountdown() {
    guard let minutes = session?.breakTimer.breakMin else { return }
    // 休憩中はカメラを止める(MVP の設計 3 章)
    camera?.stop()
    sound.stopAlarm()
    sound.gentle()
    voice.say("休憩の時間です。\(minutes)分休みましょう", interrupt: true)
    breakEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
    breakTimer?.invalidate()
    breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let cues = self.session?.tick(at: SessionRunner.now()) else { return }
        self.handle(cues)
      }
    }
  }

  /// 判定の出来事を音で知らせる(設計書 3.13、試作品の app.js の notify と同じ)
  private func notify(_ ev: AnalysisEvent) {
    switch ev.type {
    case .sleep:
      sound.startAlarm()
    case .wake:
      sound.stopAlarm()
    case .drowsy:
      // 判定がちらついて何度も鳴らないよう、一定の間隔をあける
      let minGap = (session?.cfg.drowsyBeepMinSec ?? 60) * 1000
      if lastDrowsyChimeT.map({ ev.t - $0 >= minGap }) ?? true {
        lastDrowsyChimeT = ev.t
        sound.chime()
      }
    case .awayStart:
      sound.stopAlarm()
      voice.say("離席として記録します")
    case .awayEnd:
      voice.say("おかえりなさい。再開します")
    case .postureClose:
      voice.say("目が机に近すぎます。少し離しましょう")
    case .postureSlouch:
      voice.say("背中が丸まっています。姿勢を戻しましょう")
    default:
      break
    }
  }
}
