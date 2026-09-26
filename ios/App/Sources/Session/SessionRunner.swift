import Foundation
import Observation
import QuartzCore
import StudyCore
import UIKit

/// 学習のしかた:ふだんの学習か、検証モード(検証シナリオの 9 場面)か
enum SessionMode: String {
  case free
  case scenario
}

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
    /// カメラの使用が許可されていない(設定アプリを開くボタンを出す)
    case cameraDenied
  }

  private(set) var status: Status = .idle
  private(set) var phase: SessionPhase?
  private(set) var guideChecks: [GuideCheck] = []
  private(set) var summary: SessionSummary?
  private(set) var card: ResultCard?
  /// 確認用の表示(開発中だけ使う)
  private(set) var debug = DebugInfo()
  private(set) var breakEndsAt: Date?
  /// いまの休憩の長さ(秒。残り時間の輪に使う)
  private(set) var breakTotalSec: Double = 0
  /// 計測を始めた時刻(学習中の経過時間に使う)
  private(set) var studyStartedAt: Date?
  /// 一時停止した時刻と、そのときまでの集計(一時停止の画面に出す)
  private(set) var pausedAt: Date?
  private(set) var pauseSummary: SessionSummary?
  /// 一時停止のまま 10 分たった(終了するかを尋ねる。設計書 3.11 の要件 8)
  private(set) var pausedLong = false
  private var pauseTimer: Timer?
  /// 検証モードの進み具合と、終わったときの採点
  private(set) var mode: SessionMode = .free
  private var scenario: ScenarioRun?
  private(set) var scenarioPosition: Scenario.Position?
  private(set) var scenarioResults: [PhaseResult]?
  private var lastScenarioT: Double?
  /// 書き出した記録(結果の画面から送れる)
  private(set) var exportURL: URL?
  /// 検証モードが自分で終わったとき(結果の画面に移る)
  var onAutoFinish: (() -> Void)?
  // 解析の速さ(書き出しに入れる)
  private var perfMs: [Double] = []
  private var perfFirstT: Double?
  private var perfLastT: Double?
  private var videoSize: String?
  private var fovDeg: Double?

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
  private let store: Store?
  /// 保存している学習の記録(計測を始めてから)
  private(set) var record: SessionRecord?
  private var wallStart = Date()
  private var tStart = 0.0
  private var savedMinutes = 0
  private var savedIntervals = 0
  private var camera: CameraSource?
  private var pipeline: FramePipeline?
  private let motion = MotionSensor()
  private let voice = VoiceOutput()
  private let sound = SoundPlayer()
  private var frameTimes: [Double] = []
  private var breakTimer: Timer?
  private var lastDrowsyChimeT: Double?

  init(store: Store?) {
    self.store = store
  }

  static func now() -> Double { CACurrentMediaTime() * 1000 }

  /// 解析の時刻(ミリ秒)を、壁時計の時刻にする
  private func wall(_ t: Double) -> Date { wallStart.addingTimeInterval((t - tStart) / 1000) }

  func start(settings: StudySettings, mode: SessionMode = .free) async {
    guard status == .idle || isFailed else { return }
    status = .preparing
    summary = nil
    card = nil
    record = nil
    savedMinutes = 0
    savedIntervals = 0
    self.mode = mode
    scenario = mode == .scenario ? ScenarioRun(setup: settings.setup) : nil
    scenarioPosition = nil
    scenarioResults = nil
    lastScenarioT = nil
    exportURL = nil
    perfMs = []
    perfFirstT = nil
    perfLastT = nil
    guard await CameraSource.requestAccess() else {
      status = .cameraDenied
      usage("camera_denied_shown")
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
      videoSize = camera.dimensions.map { "\($0.width)×\($0.height)" }
      fovDeg = camera.fovLongSideDeg
      // 検証モードでは休憩タイマーを使わない
      var timer = settings.breakTimer
      if mode == .scenario { timer.enabled = false }
      var s = StudySession(
        cfg: cfg, setup: settings.setup, autoAway: true, measuredEyeDeskCm: settings.eyeDeskCm, breakTimer: timer)
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
    usage("ritual_skipped")
    phase = session?.phase
    handle(cues)
  }

  func pause(_ reason: PauseReason) {
    guard phase == .studying else { return }
    session?.pause(at: Self.now(), reason: reason)
    phase = session?.phase
    sound.stopAlarm()
    pausedAt = Date()
    pauseSummary = session?.recorder?.summary()
    pausedLong = false
    pauseTimer?.invalidate()
    pauseTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
      Task { @MainActor in
        guard let self, self.session?.isPaused == true else { return }
        self.pausedLong = true
        self.voice.say("一時停止から10分たちました。今日はここまでにしますか")
      }
    }
    usage("session_pause", ["reason": reason == .touch ? "touch" : "app"])
  }

  /// 一時停止の画面から休憩にするときの長さ(休憩タイマーの休憩の長さ。使っていなければ 5 分)
  var pauseBreakMinutes: Int {
    guard let t = session?.breakTimer, t.enabled else { return 5 }
    return t.breakMin
  }

  /// 一時停止から、そのまま休憩に切り替える(設計書 3.11 の要件 9)
  func breakFromPause() {
    guard session?.isPaused == true else { return }
    let minutes = pauseBreakMinutes
    session?.startBreak(at: Self.now(), minutes: minutes)
    clearPause()
    phase = session?.phase
    startBreakCountdown(minutes: minutes)
  }

  private func clearPause() {
    pauseTimer?.invalidate()
    pauseTimer = nil
    pausedAt = nil
    pausedLong = false
  }

  func resume() {
    guard session?.isPaused == true else { return }
    session?.resume(at: Self.now())
    phase = session?.phase
    clearPause()
    usage("session_resume")
    persistProgress()
  }

  func endBreak() {
    breakTimer?.invalidate()
    breakTimer = nil
    breakEndsAt = nil
    let cues = session?.endBreak(at: Self.now()) ?? []
    phase = session?.phase
    camera?.start()
    usage("break_end")
    persistProgress()
    handle(cues)
  }

  /// 学習を終え、結果を返す(計測を始める前なら nil)
  @discardableResult
  func finish(reason: String = "manual") -> SessionSummary? {
    let endT = Self.now()
    let result = session?.finish(at: endT)
    if let result, let s = session {
      scenarioResults = scenario?.results()
      writeExport(summary: result, session: s, reason: reason, endT: endT)
      if let r = scenarioResults {
        usage("scenario_complete", ["passed": String(r.filter { $0.pass == true }.count), "reason": reason])
        if reason != "scenario_done" { sound.gentle() }
      }
    }
    if let result, let s = session, var rec = record {
      let previous = store?.latestFinished()
      let recent = recentFocusMin(store?.sessions(since: StudyDay.recentDates(7, until: Date()).first ?? "") ?? [], excluding: rec.id, now: Date())
      let input = ResultCardInput(
        summary: result, events: s.recorder?.events ?? [], pauseCount: s.pauseCount, recentFocusMin: recent,
        previousPraise: previous?.praise, previousNextStep: previous?.nextStep)
      let c = buildResultCard(input)
      card = c
      rec.apply(result, breakSec: s.breakSec, deviceUseCount: s.pauseCount)
      rec.endedAt = Date()
      rec.endReason = .manual
      rec.praise = c.praise
      rec.nextStep = c.nextStep
      record = rec
      persistProgress(final: true)
      usage(
        "session_complete",
        [
          "studyMin": String(Int(result.studySec / 60)), "focusMin": String(Int(result.effectiveFocusMin)),
          "avgFocus": result.avgFocus.map(String.init) ?? "", "breakMin": String(Int(s.breakSec / 60)),
        ])
      sound.gentle()
    }
    stopDevices()
    summary = result
    phase = .finished
    status = .idle
    session = nil
    return result
  }

  /// 体感の 1 タップ(設計書 3.14。任意)
  func setSelfRating(_ rating: SelfRating) {
    guard var rec = record else { return }
    rec.selfRating = rating
    record = rec
    store?.setSelfRating(rating, sessionId: rec.id)
    usage("self_rating", ["value": rating.rawValue])
  }

  func resultCardViewed() {
    if record != nil { usage("result_card_view") }
  }

  /// 計測を始めたときに、学習の記録を作って保存する(検証モードは学習の記録に入れず、書き出しだけ行う)
  private func createRecord() {
    guard let s = session, let t0 = s.startT else { return }
    wallStart = Date()
    tStart = t0
    studyStartedAt = wallStart
    if mode == .scenario {
      usage("scenario_start", ["setup": s.setup.rawValue])
      return
    }
    let timer = s.breakTimer
    let preset =
      !timer.enabled ? "none" : timer.studyMin == 25 && timer.breakMin == 5 ? "25_5" : timer.studyMin == 50 && timer.breakMin == 10 ? "50_10" : "custom"
    let rec = SessionRecord(studyDate: StudyDay.studyDate(wallStart), startedAt: wallStart, setup: s.setup, timerPreset: preset)
    record = rec
    store?.save(rec)
    usage("session_start", ["timer": preset])
  }

  /// 終わった分の記録、一時停止・休憩の区間を保存する。final のときは、途中の分と学習の集計も保存する
  private func persistProgress(final: Bool = false) {
    guard let s = session, var rec = record, let recorder = s.recorder else { return }
    let done = final ? recorder.minutes.count : Swift.max(0, recorder.minutes.count - 1)
    if done > savedMinutes || final {
      // 最後は全部の分を保存し直す(離席の出来事は、始まった分にさかのぼって数えるため)
      let scores = recorder.scores()
      let from = final ? 0 : savedMinutes
      let rows = (from..<done).map { MinuteRow(sessionId: rec.id, minute: recorder.minutes[$0], focusPct: scores[$0]) }
      store?.save(minutes: rows)
      savedMinutes = done
      if !final {
        // 強制終了されても残るよう、休憩と一時停止の回数も書いておく
        rec.breakSec = s.breakSec
        rec.deviceUseCount = s.pauseCount
        record = rec
        store?.save(rec)
      }
    }
    if s.intervals.count > savedIntervals {
      let rows = s.intervals[savedIntervals...].map {
        IntervalRow(sessionId: rec.id, kind: $0.kind, startedAt: wall($0.startT), endedAt: wall($0.endT))
      }
      store?.add(intervals: Array(rows))
      savedIntervals = s.intervals.count
    }
    if final { store?.save(rec) }
  }

  private func usage(_ name: String, _ properties: [String: String] = [:]) {
    store?.log(UsageEvent(name: name, at: Date(), properties: properties))
  }

  private var isFailed: Bool {
    switch status {
    case .failed, .cameraDenied: true
    default: false
    }
  }

  private func stopDevices() {
    clearPause()
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
    if phase == .studying {
      perfMs.append(result.processingMs)
      if perfFirstT == nil { perfFirstT = f.t }
      perfLastT = f.t
    }
    handle(cues)
    persistProgress()
    if mode == .scenario { scenarioStep(f.t) }
  }

  /// 検証モード:計測を始めてからの時間で場面を進め、場面ごとに判定を記録する(試作品の app.js の scenarioStep と同じ)
  private func scenarioStep(_ t: Double) {
    guard var run = scenario, let s = session, let t0 = s.startT else { return }
    let kind: TimeKind
    let output: AnalysisOutput?
    switch s.phase {
    case .studying:
      output = s.lastOutput
      kind = output.map { $0.away ? .away : TimeKind($0.state) } ?? .think
    case .paused:
      output = nil
      kind = .paused
    default:
      return
    }
    let dt = lastScenarioT.map { Swift.min(1, (t - $0) / 1000) } ?? 0
    lastScenarioT = t
    let cues = run.update(elapsedSec: (t - t0) / 1000, dt: dt, kind: kind, output: output)
    scenario = run
    scenarioPosition = run.position
    for cue in cues {
      switch cue {
      case .phaseIntro(let index):
        // 前の場面の終わりの音と、次の場面の指示
        sound.stopAlarm()
        if index > 0 { sound.beep(freq: 1046, sec: 0.3, volume: 0.5) }
        voice.say(ScenarioRun.introSpeech(index), interrupt: true)
      case .phaseStart:
        sound.beep(freq: 784, sec: 0.12)
      case .done:
        // 終了でカメラと読み上げを止めてから、終わりを伝える
        finish(reason: "scenario_done")
        sound.beep(freq: 1046, sec: 0.3, volume: 0.5)
        voice.say("検証が終わりました。お疲れさまでした", interrupt: true)
        onAutoFinish?()
        return
      }
    }
  }

  /// 記録を JSON にして一時フォルダに書き出す(映像・画像・特徴点は含めない。結果の画面から本人が送る)
  private func writeExport(summary: SessionSummary, session s: StudySession, reason: String, endT: Double) {
    let t0 = s.startT ?? endT
    let spanSec = perfFirstT.flatMap { a in perfLastT.map { ($0 - a) / 1000 } } ?? 0
    let perf = perfSummary(
      perfMs, frames: perfMs.count, spanSec: spanSec, errors: debug.errors, videoSize: videoSize, device: Self.deviceModel(), fov: fovDeg)
    let export = SessionExport(
      appVersion: Self.appVersion, createdAt: wallStart, reason: reason, mode: mode.rawValue, session: s, summary: summary,
      durationSec: (endT - t0) / 1000, scenario: scenarioResults, perf: perf)
    do {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyyMMdd-HHmm"
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("tsukuelog-\(mode.rawValue)-\(f.string(from: wallStart)).json")
      try export.json().write(to: url, options: .atomic)
      exportURL = url
    } catch {
      debug.errors += 1
    }
  }

  static var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
  }

  /// 端末の機種名(例:iPhone15,2)
  static func deviceModel() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
  }

  private func handle(_ cues: [SessionCue]) {
    for cue in cues {
      switch cue {
      case .guideStarted(let setup):
        voice.say(PlacementGuide.introSpeech(setup), interrupt: true)
      case .guide(let prompt):
        voice.say(prompt.speech)
      case .guideReady:
        usage("ritual_start")
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
        createRecord()
        usage("ritual_complete")
        sound.gentle()
        // 検証モードでは、すぐに場面の指示を読み上げる
        if mode == .free { voice.say("学習を始めます") }
      case .resumed:
        sound.gentle()
        voice.say("学習に戻ります")
      case .breakDue:
        startBreakCountdown(minutes: session?.currentBreakMin ?? 5)
      case .breakOver:
        sound.gentle()
        voice.say("休憩の時間が終わりました。準備ができたら、休憩を終えるを押してください")
      case .event(let ev):
        debug.lastEvent = ev.type.rawValue
        if let rec = record { store?.add(events: [EventRow(sessionId: rec.id, type: ev.type, at: wall(ev.t))]) }
        notify(ev)
      }
    }
  }

  private func startBreakCountdown(minutes: Int) {
    // 休憩中はカメラを止める(MVP の設計 3 章)
    camera?.stop()
    sound.stopAlarm()
    sound.gentle()
    usage("break_start")
    voice.say("休憩の時間です。\(minutes)分休みましょう", interrupt: true)
    breakEndsAt = Date().addingTimeInterval(Double(minutes) * 60)
    breakTotalSec = Double(minutes) * 60
    breakTimer?.invalidate()
    breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      Task { @MainActor in
        guard let self, let cues = self.session?.tick(at: SessionRunner.now()) else { return }
        self.handle(cues)
      }
    }
  }

  /// 判定の出来事を音で知らせる(設計書 3.13、試作品の app.js の notify と同じ)。
  /// 検証モードでは、場面の指示と重ならないよう読み上げない(居眠りの音と注意の音は鳴らす)
  private func notify(_ ev: AnalysisEvent) {
    let quiet = mode == .scenario
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
      if !quiet { voice.say("離席として記録します") }
    case .awayEnd:
      if !quiet { voice.say("おかえりなさい。再開します") }
    case .postureClose:
      if !quiet { voice.say("目が机に近すぎます。少し離しましょう") }
    case .postureSlouch:
      if !quiet { voice.say("背中が丸まっています。姿勢を戻しましょう") }
    default:
      break
    }
  }
}
