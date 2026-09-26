import Foundation

/// 学習の状態(設計書 4.4)。rawValue は試作品と同じ。
public enum StudyState: String, Codable, Sendable, CaseIterable {
  /// 作業(手を動かしている)
  case work
  /// 思考(見つめて考えている)
  case think
  /// よそ見
  case lookaway
  /// うとうと
  case drowsy
  /// 居眠り
  case sleep
  /// 不在
  case absent

  public var label: String {
    switch self {
    case .work: return "作業(手を動かしている)"
    case .think: return "思考(見つめて考えている)"
    case .lookaway: return "よそ見"
    case .drowsy: return "うとうと"
    case .sleep: return "居眠り"
    case .absent: return "不在"
    }
  }
}

/// 判定が出す出来事。rawValue は試作品と同じ。
public enum AnalysisEventType: String, Codable, Sendable {
  case yawn
  case awayStart = "away_start"
  case awayEnd = "away_end"
  case lookaway
  case drowsy
  case sleep
  case wake
  case chinRest = "chin_rest"
  case habitHead = "habit_head"
  case habitFace = "habit_face"
  case postureClose = "posture_close"
  case postureSlouch = "posture_slouch"
  case postureTilt = "posture_tilt"

  /// 癖(1 分の集中度から差し引く)
  public var isHabit: Bool { self == .chinRest || self == .habitHead || self == .habitFace }
}

public struct AnalysisEvent: Codable, Equatable, Sendable {
  public var type: AnalysisEventType
  /// ミリ秒
  public var t: Double

  public init(type: AnalysisEventType, t: Double) {
    self.type = type
    self.t = t
  }
}

public struct AnalysisFlags: Codable, Equatable, Sendable {
  public var writing: Bool
  public var eyesClosed: Bool
  public var tooClose: Bool
  public var slouch: Bool
  public var tilt: Bool
  public var habit: Bool
}

/// 記録と調整のための値(試作品の metrics と同じ名前・同じ値。0/1 は真偽)。
public struct AnalysisMetrics: Codable, Sendable {
  public var handSpeed: Double
  public var fingerSpeed: Double
  public var pinch: Double?
  public var penGrip: Int
  public var handsCount: Int
  public var handFaceDist: Double?
  public var touchHandScale: Double?
  public var handY: Double?
  public var faceTopY: Double?
  public var handOnHead: Int
  public var perclos: Double
  public var closedSec: Double
  public var eyeDeskCm: Double?
  public var eyeDeskThresholdCm: Double?
  public var cameraTiltDeg: Double?
  public var yawDev: Double
  public var pitchUp: Double
  public var blink: Double?
  public var earRatio: Double?
  public var eyesClosed: Int
  public var closedBy: ClosureReason?
  public var closedScore: Double?
  public var closedScoreSmooth: Double?
  public var eyeLookDown: Double?
  public var eyeLookDownSmooth: Double?
  public var eyeLookUp: Double?
  public var eyeLookSide: Double?
  public var jawOpen: Double?
  public var writing: Int
  public var tooClose: Int
  public var writeShare: Double
  public var handScale: Double?
  public var handOnFace: Int
  public var faceVisible: Int
  public var faceRate: Double
  public var dozeShadow: Int
  public var headMotion: Double?
  public var lookingDown: Int
  public var crownRatio: Double?
  public var crownDelta: Double?
  public var hairFrac: Double?
  public var personFrac: Double?
  public var segHead: Int
  public var covering: Int
  public var poseVisible: Int
  public var headRatio: Double?
  public var hairShrunk: Int
  public var slouchRel: Double?
}

public struct AnalysisOutput: Codable, Sendable {
  public var state: StudyState
  /// 離席中(自動の離席判定)
  public var away: Bool
  public var events: [AnalysisEvent]
  public var flags: AnalysisFlags
  public var metrics: AnalysisMetrics
}

@inline(__always) private func b(_ x: Bool) -> Int { x ? 1 : 0 }

/// 直近の窓に入れる値(時刻はミリ秒)
private struct Sample: Sendable {
  var t: Double
  var v: Double
}

private struct HandSample: Sendable {
  var t: Double
  var speed: Double
  var fingerSpeed: Double?
}

/// 時間の重み(秒)つきの真偽
private struct TimedFlag: Sendable {
  var t: Double
  var dt: Double
  var on: Bool
}

/// 条件が続いている区間(ミリ秒)
private struct GapTimer: Sendable {
  var start: Double
  var last: Double
}

/// フレームごとに状態を判定し、居眠り・癖・姿勢・離席の出来事を出す(設計書 4.4〜4.11)。
/// 試作品(prototype/js/analysis.js の Analyzer)と同じ判定。値の比べ方(取れない値は偽になる)もそろえている。
public struct Analyzer: Sendable {
  public let cfg: AnalysisConfig
  public let autoAway: Bool
  public let setup: SetupStyle
  public private(set) var cal: Calibration?
  private var prev: Features?
  private var handMotion: HandMotion
  private var handSamples: [HandSample] = []
  private var writeSamples: [TimedFlag] = []
  private var personalSamples: [Sample] = []
  private var lookDownSamples: [Sample] = []
  private var faceSamples: [Sample] = []
  private var headSamples: [Sample] = []
  private var prevNose: Point2?
  private var lastSeg: SegmentStats?
  private var perclosSamples: [TimedFlag] = []
  private var inLookAway = false
  private var absentSince: Double?
  private var presentSince: Double?
  public private(set) var away = false
  private var sleepLevel: StudyState?  // nil | .drowsy | .sleep
  private var timers: [String: Double] = [:]
  private var firedPosture: Set<AnalysisEventType> = []
  private var gapTimers: [String: GapTimer] = [:]
  private var lastHabitAt: [AnalysisEventType: Double] = [:]
  private var yawnFired = false

  public init(cfg: AnalysisConfig, autoAway: Bool = true, setup: SetupStyle = .stand) {
    self.cfg = cfg
    self.autoAway = autoAway
    self.setup = setup
    self.handMotion = HandMotion(cfg: cfg)
  }

  public mutating func setCalibration(_ cal: Calibration?) {
    self.cal = cal
  }

  // 条件が続いた時間を測る。gapSec 以内の途切れ(検出のちらつき)は続いているとみなす。
  // 途切れている間は時間を伸ばさない(0.6 秒触って 0.4 秒離れたのを「1 秒触った」としない)
  private mutating func sustainedGap(_ key: String, _ cond: Bool, _ t: Double, _ gapSec: Double) -> Double {
    if cond {
      if gapTimers[key] != nil { gapTimers[key]!.last = t } else { gapTimers[key] = GapTimer(start: t, last: t) }
    } else if let g = gapTimers[key], (t - g.last) / 1000 > gapSec {
      gapTimers[key] = nil
    }
    guard let g = gapTimers[key] else { return 0 }
    return (g.last - g.start) / 1000
  }

  // 条件が続いた時間を測る。続いている秒数を返す(条件が偽なら 0)。
  private mutating func sustained(_ key: String, _ cond: Bool, _ t: Double) -> Double {
    if !cond {
      timers[key] = nil
      return 0
    }
    if timers[key] == nil { timers[key] = t }
    return (t - timers[key]!) / 1000
  }

  public mutating func update(_ f: Features) -> AnalysisOutput {
    let cfg = self.cfg
    let cal = self.cal
    let t = f.t
    let dtSec = prev.map { Swift.min(1, (t - $0.t) / 1000) } ?? 0
    var events: [AnalysisEvent] = []

    // --- 手の動き(作業の判定)
    let scale = truthy(f.faceWidthNorm) ?? truthy(prev?.faceWidthNorm) ?? 0.15
    if let motion = handMotion.update(f.hands, t: t, scale: scale) {
      handSamples.append(HandSample(t: t, speed: motion.speed, fingerSpeed: motion.fingerSpeed))
    }
    handSamples.removeAll { t - $0.t > cfg.handWindowSec * 1000 }
    // 一瞬の跳ね(検出の誤り)に引きずられないよう、平均ではなく中央値を使う
    let handSpeed = median(handSamples.map(\.speed)) ?? 0
    let fingerSpeed = median(handSamples.map(\.fingerSpeed)) ?? 0
    let eyeY = f.eyeMid?.y ?? 0.35
    let handsOnDesk = f.hands.filter { $0.centroid.y > eyeY + (f.faceHeightNorm ?? 0.15) * 0.6 }
    // 書く動作:机の上の手が一定以上の速さで動いている。手の形(ペンを持つ形)は記録だけする
    let pinches = handsOnDesk.compactMap(\.pinch).filter(\.isFinite)
    let pinch = pinches.min()
    let penGrip = pinch.map { $0 < cfg.penGripPinchMax } ?? false
    // 頭が机の上にある(伏せている):顔が見えず、髪が大きく映っているか、頭がカメラを覆っている。このときは書いていない
    let seg = f.seg ?? lastSeg
    if f.seg != nil { lastSeg = f.seg }
    var headOnDesk = false
    if !f.faceVisible, let seg {
      var hairBig = false
      if let hair = seg.hairFrac, let calHair = cal?.hairFrac, calHair >= cfg.segMinHairFrac {
        hairBig = hair >= calHair * cfg.headOnDeskHairRatio
      }
      headOnDesk = hairBig || (seg.personFrac.map { $0 >= cfg.coverPersonFrac } ?? false)
    }
    let writing = !handsOnDesk.isEmpty && handSpeed >= cfg.writeSpeedMin && !headOnDesk
    // 【記録のみ】机の上の手の大きさ(顔の幅を 1 とする)
    let handSizes = handsOnDesk.compactMap(\.sizeNorm).filter { $0 > 0 }
    var handScale: Double?
    if let maxSize = handSizes.max(), let fw = truthy(f.faceWidthNorm) { handScale = maxSize / fw }
    // 【記録のみ】直近 10 秒のうち書いていた時間の割合
    writeSamples.append(TimedFlag(t: t, dt: dtSec, on: writing))
    writeSamples.removeAll { t - $0.t > cfg.sleepClosedSec * 1000 }
    let writeTotal = writeSamples.reduce(0) { $0 + $1.dt }
    let writeShare = writeTotal > 0 ? writeSamples.reduce(0) { $0 + ($1.on ? $1.dt : 0) } / writeTotal : 0

    // 顔の検出率(直近 10 秒)
    faceSamples.append(Sample(t: t, v: f.faceVisible ? 1 : 0))
    faceSamples.removeAll { t - $0.t > cfg.faceRateWindowSec * 1000 }
    let faceRate = faceSamples.reduce(0) { $0 + $1.v } / Double(faceSamples.count)

    // --- 閉眼・PERCLOS
    // 手が顔にかかっているときは、目が隠れて「閉じている」と誤判定しやすい(6 回目)。そのあいだは閉眼として数えない
    let handOnFace = handCoversFace(f)
    // 本人の基準での閉じ具合は、一瞬の跳ねに反応しないよう直近の中央値を使う
    let closedScore = personalClosedScore(f, cal)
    if let closedScore { personalSamples.append(Sample(t: t, v: closedScore)) }
    personalSamples.removeAll { t - $0.t > cfg.personalSmoothSec * 1000 }
    let closedScoreSmooth = f.faceVisible ? median(personalSamples.map(\.v)) : nil
    if let d = f.eyeLookDown { lookDownSamples.append(Sample(t: t, v: d)) }
    lookDownSamples.removeAll { t - $0.t > cfg.personalSmoothSec * 1000 }
    let lookDownSmooth = f.faceVisible ? median(lookDownSamples.map(\.v)) : nil
    let closedBy = handOnFace ? nil : eyeClosureReason(f, cal, cfg, personalScore: closedScoreSmooth, lookDown: lookDownSmooth)
    let closed = closedBy != nil
    if f.faceVisible { perclosSamples.append(TimedFlag(t: t, dt: dtSec, on: closed)) }
    // 目覚めたら(目を開けた状態が続いたら)過去の閉眼の記録を消し、アラームがすぐ止まるようにする
    if sustainedGap("eyesOpen", sleepLevel != nil && f.faceVisible && !closed, t, cfg.faceGapSec) >= cfg.wakeOpenSec {
      perclosSamples = []
    }
    perclosSamples.removeAll { t - $0.t > cfg.perclosWindowSec * 1000 }
    let totalP = perclosSamples.reduce(0) { $0 + $1.dt }
    // 顔がいま見えていないときは PERCLOS を使わない(5 回目)
    let perclos =
      totalP >= cfg.perclosMinObservedSec && faceRate >= cfg.perclosMinFaceRate
      ? perclosSamples.reduce(0) { $0 + ($1.on ? $1.dt : 0) } / totalP
      : 0
    // 閉眼の判定は境目の値でちらつく(4 回目)。短い途切れは閉じたままとみなす
    let closedSec = sustainedGap("closed", closed && !writing, t, cfg.closedGapSec)
    // 居眠りは手の動きに関係なく、目を閉じた時間で判定する(3 回目・8 回目の前)
    let closedRawSec = sustainedGap("closedRaw", closed, t, cfg.closedGapSec)

    // 【記録のみ】あくび
    let yawnSec = sustainedGap("yawn", f.jawOpen.map { $0 >= cfg.yawnJawOpen } ?? false, t, 0.5)
    if yawnSec >= cfg.yawnSec && !yawnFired {
      yawnFired = true
      events.append(AnalysisEvent(type: .yawn, t: t))
    }
    if yawnSec == 0 { yawnFired = false }

    // --- 頭のうつむき具合(設計書 4.9)
    // 髪の面積がキャリブレーション時より大きく減っていれば、頭は下がっていない(横や後ろを向いた。7 回目)
    var hairShrunk = false
    if let hair = seg?.hairFrac, let calHair = cal?.hairFrac, calHair >= cfg.segMinHairFrac {
      hairShrunk = hair < calHair * cfg.hairShrinkRatio
    }
    var rawHeadRatio: Double?
    if let calHead = truthy(cal?.headHeight), let head = f.headHeight { rawHeadRatio = head / calHead }
    let headRatio = hairShrunk ? nil : rawHeadRatio
    let poseHeadLow = !hairShrunk && f.headLow == true  // 頭の高さの比が取れないときの目安
    let headLowThr = setup == .landscape ? cfg.headLowRatioLandscape : cfg.headLowRatio
    let headLow = headRatio.map { $0 < headLowThr } ?? poseHeadLow
    // 頭頂部の見える割合(髪 ÷ (髪 + 顔の肌))のキャリブレーション時からの増え方。うつむくほど大きい
    var crownDelta: Double?
    if let crown = seg?.crownRatio, let calCrown = cal?.crownRatio { crownDelta = crown - calCrown }
    // 頭頂部の割合でうつむきを判断するのは、正面に立てたときだけ(5 回目・7 回目)
    let lookingDown =
      (headRatio.map { $0 < cfg.headDownRatio } ?? false)
      || (setup == .stand && !hairShrunk && (crownDelta.map { $0 > cfg.crownBowDelta } ?? false))
    // 顔も上半身も見つからなくても、頭(髪)が大きく映っていれば席にいる(3 回目)
    var segHead = false
    if let seg, let calHair = truthy(cal?.hairFrac), let calPerson = truthy(cal?.personFrac) {
      let hairOk = seg.hairFrac.map { $0 >= Swift.max(cfg.segMinHairFrac, calHair * cfg.segHairRatio) } ?? false
      let personOk = seg.personFrac.map { $0 >= calPerson * cfg.segPersonRatio } ?? false
      segHead = hairOk && personOk
    }
    // 頭がカメラを覆っている:人が画面のほとんどを占め、顔が見えないか目がカメラのすぐ近くにある(5 回目)
    let nearEyeDesk = estimateEyeDeskCm(f, cal)
    var covering = false
    if let person = seg?.personFrac, person >= cfg.coverPersonFrac {
      covering = !f.faceVisible || (nearEyeDesk.map { $0 < cfg.coverEyeDeskCm } ?? false)
    }
    // 顔が見えず、人の領域もほとんど映っていなければ、上半身の特徴点は誤検出とみなす(13 回目)
    var segEmpty = false
    if !f.faceVisible, let person = seg?.personFrac {
      segEmpty = person < Swift.max(cfg.segAbsentFrac, (cal?.personFrac ?? 0) * cfg.segAbsentRatio)
    }
    let present = f.faceVisible || (f.poseVisible && !segEmpty) || segHead || covering
    // うつ伏せ:顔は見えず、頭が低い(上半身が映っていれば肩からの高さ、映っていなければ髪だけが見えている)
    let faceDown = !writing && ((!f.faceVisible && ((f.poseVisible && headLow) || (!f.poseVisible && segHead))) || covering)
    let faceDownSec = sustainedGap("faceDown", faceDown, t, cfg.faceGapSec)

    // --- 離席(設計書 3.10, 4.11)
    if !present {
      if absentSince == nil { absentSince = t }
      presentSince = nil
    } else {
      absentSince = nil
      if presentSince == nil { presentSince = t }
    }
    if autoAway && !away, let since = absentSince, (t - since) / 1000 >= cfg.awaySec {
      away = true
      perclosSamples = []
      events.append(AnalysisEvent(type: .awayStart, t: since))
    }
    if away && f.faceVisible, let since = presentSince, (t - since) / 1000 >= cfg.returnSec {
      away = false
      events.append(AnalysisEvent(type: .awayEnd, t: t))
    }

    // --- よそ見
    // 角度が取れないときは NaN(比べると偽になる。試作品と同じ)
    let yawDev: Double = cal?.yawDeg != nil && f.faceVisible ? abs((f.yawDeg ?? .nan) - cal!.yawDeg!) : 0
    let pitchUp: Double = cal?.pitchDeg != nil && f.faceVisible ? cal!.pitchDeg! - (f.pitchDeg ?? .nan) : 0
    // 顔が見えなくても、うつむいているだけならよそ見ではない(3 回目)
    let lookAwayCand =
      present && ((!f.faceVisible && !faceDown && !lookingDown) || yawDev > cfg.lookAwayYawDeg || pitchUp > cfg.lookAwayPitchUpDeg)
    // 頭の向きは強い手がかりなので、手が動いていてもよそ見とする
    let lookAwaySec = sustained("lookaway", lookAwayCand, t)
    let lookingAway = lookAwaySec >= cfg.lookAwaySec
    if lookingAway && !inLookAway { events.append(AnalysisEvent(type: .lookaway, t: t)) }
    inLookAway = lookingAway

    // --- 状態の決定
    let state: StudyState
    if !present {
      state = .absent
    } else if closedRawSec >= cfg.sleepClosedSec || faceDownSec >= cfg.faceDownSec {
      state = .sleep
    } else if (closedSec >= cfg.drowsyClosedSec || perclos >= cfg.perclosDrowsy) && !writing {
      state = .drowsy
    } else if lookingAway {
      state = .lookaway
    } else if writing {
      state = .work
    } else {
      state = .think
    }

    let level: StudyState? = state == .sleep || state == .drowsy ? state : nil
    if level != sleepLevel {
      if let level {
        events.append(AnalysisEvent(type: level == .sleep ? .sleep : .drowsy, t: t))
      } else if sleepLevel != nil && present {
        events.append(AnalysisEvent(type: .wake, t: t))
        perclosSamples = []
      }
      sleepLevel = level
    }

    // --- 癖(設計書 4.7):指先の位置で判定する。手の検出のちらつきで途切れないよう、短い途切れは許す
    var habit: AnalysisEventType?
    var handFaceDist: Double?
    var onHead = false
    var onFace = false
    var chinRest = false
    var touchHandScale: Double?
    if f.faceVisible && !f.hands.isEmpty, let bx = f.faceBox, let chin = f.chin {
      let w = bx.maxX - bx.minX
      let h = bx.maxY - bx.minY
      let inX = { (p: Landmark) in p.x > bx.minX - w * 0.15 && p.x < bx.maxX + w * 0.15 }
      let tips = f.hands.flatMap { hd in LM.handTips.compactMap { hd.point($0) } }
      let knuckles = f.hands.flatMap { hd in LM.handKnuckles.compactMap { hd.point($0) } }
      let wOr1 = truthy(w) ?? 1
      handFaceDist = tips.map { p in
        hypot(Swift.max(bx.minX - p.x, 0, p.x - bx.maxX), Swift.max(bx.minY - p.y, 0, p.y - bx.maxY)) / wOr1
      }.min()
      onHead = tips.contains { inX($0) && $0.y < bx.minY + h * 0.15 && $0.y > bx.minY - h * 0.6 }
      onFace = tips.contains { inX($0) && $0.y >= bx.minY + h * 0.15 && $0.y < chin.y }
      let underChin = (tips + knuckles).contains { inX($0) && $0.y >= chin.y - h * 0.1 && $0.y < chin.y + h * 0.3 }
      chinRest = underChin && handSpeed < cfg.chinRestMaxSpeed
      // 【記録のみ】顔に重なって映った手の大きさ(顔の幅を 1 とする。12 回目)
      let sizes = f.hands
        .filter { hd in
          LM.handTips.contains { i in
            guard let p = hd.point(i) else { return false }
            return inX(p) && p.y > bx.minY - h * 0.6 && p.y < chin.y
          }
        }
        .compactMap(\.sizeNorm)
        .filter { $0 > 0 }
      if let maxSize = sizes.max(), let fw = truthy(f.faceWidthNorm) { touchHandScale = maxSize / fw }
    }
    let chinSec = sustainedGap("habitChin", chinRest, t, cfg.habitGapSec)
    let headSec = sustainedGap("habitHead", onHead, t, cfg.habitGapSec)
    let faceSec = sustainedGap("habitFace", onFace && !chinRest, t, cfg.habitGapSec)
    if chinSec >= cfg.chinRestSec {
      habit = .chinRest
    } else if headSec >= cfg.habitTouchSec {
      habit = .habitHead
    } else if faceSec >= cfg.habitTouchSec {
      habit = .habitFace
    }
    if let habit {
      if let last = lastHabitAt[habit], (t - last) / 1000 <= cfg.habitMergeSec {
        // 続けて出た癖は 1 回と数える
      } else {
        events.append(AnalysisEvent(type: habit, t: t))
      }
      lastHabitAt[habit] = t
    }

    // --- 姿勢(設計書 4.9)
    let eyeDeskCm = estimateEyeDeskCm(f, cal)
    // 顔を机に近づけすぎると顔の特徴点が取れなくなる(2 回目)。そのときは肩に対する頭の低さで判定する
    let headDropped = !f.faceVisible && f.poseVisible && (headRatio.map { $0 < cfg.headCloseRatio } ?? poseHeadLow)
    // 本人の基準(キャリブレーション時の距離)より一定の割合以上近づいたら「近すぎ」(設計書 3.9、決定事項 D-7)
    let eyeDeskThresholdCm = truthy(cal?.measuredEyeDeskCm).map { $0 * (1 - cfg.eyeDeskCloseRatio) }
    // 横向きでは、肩からの目の高さが大きく下がっていれば「近すぎ」(12 回目)。ほかの置き方では使わない(3・4・5・6 回目)
    var slouchRel: Double?
    if let calSlouch = truthy(cal?.slouchRatio), let s = f.slouchRatio { slouchRel = s / calSlouch }
    let eyesDropped = setup == .landscape && f.faceVisible && !hairShrunk && (slouchRel.map { $0 < cfg.slouchCloseRatio } ?? false)
    var tooClose = headDropped || eyesDropped
    if let e = eyeDeskCm, let thr = eyeDeskThresholdCm, e < thr { tooClose = true }

    // 頭の動き(肩幅 / 秒、直近の中央値)
    if let nose = f.noseN, let pn = prevNose, dtSec > 0 { headSamples.append(Sample(t: t, v: dist(nose, pn) / dtSec)) }
    prevNose = f.noseN
    headSamples.removeAll { t - $0.t > cfg.headMotionWindowSec * 1000 }
    let headMotion = median(headSamples.map(\.v))

    // 【試験中・判定には使わない】前に傾いて居眠りしている候補:うつむいていて、頭も手もほとんど動かない状態が続く
    let stillNow = lookingDown && (headMotion.map { $0 < cfg.dozeHeadStill } ?? false) && handSpeed < cfg.dozeHandStill
    let dozeShadow = sustainedGap("dozeShadow", stillNow, t, 1) >= cfg.dozeShadowSec
    var slouch = false
    if let calSlouch = cal?.slouchRatio, let s = f.slouchRatio { slouch = s < calSlouch * cfg.slouchRatio }
    var tilt = false
    if let calRoll = cal?.rollDeg, f.faceVisible, let roll = f.rollDeg { tilt = abs(roll - calRoll) > cfg.tiltDeg }
    let postureChecks: [(AnalysisEventType, Bool, Double)] = [
      (.postureClose, tooClose, cfg.eyeDeskAlertSec),
      (.postureSlouch, slouch, cfg.slouchAlertSec),
      (.postureTilt, tilt, cfg.tiltAlertSec),
    ]
    for (key, cond, sec) in postureChecks {
      // 検出のちらつきで計測がやり直しにならないよう、短い途切れは許す
      let s = sustainedGap(key.rawValue, cond, t, cfg.postureGapSec)
      if s >= sec && !firedPosture.contains(key) {
        firedPosture.insert(key)
        events.append(AnalysisEvent(type: key, t: t))
      }
      if !cond && s == 0 { firedPosture.remove(key) }
    }

    prev = f
    var earRatio: Double?
    if let calEar = truthy(cal?.ear), let ear = f.ear { earRatio = ear / calEar }
    return AnalysisOutput(
      state: state,
      away: away,
      events: events,
      flags: AnalysisFlags(writing: writing, eyesClosed: closed, tooClose: tooClose, slouch: slouch, tilt: tilt, habit: habit != nil),
      metrics: AnalysisMetrics(
        handSpeed: handSpeed,
        fingerSpeed: fingerSpeed,
        pinch: pinch,
        penGrip: b(penGrip),
        handsCount: f.hands.count,
        handFaceDist: handFaceDist,
        touchHandScale: touchHandScale,
        // 【記録のみ】いちばん下に映った手の中心の高さ(画面の上端 0・下端 1)
        handY: f.hands.map(\.centroid.y).max(),
        // 【記録のみ】顔の上端の高さ(画面の上端 0)
        faceTopY: f.faceVisible ? f.faceBox?.minY : nil,
        handOnHead: b(onHead),
        perclos: perclos,
        closedSec: closedSec,
        eyeDeskCm: eyeDeskCm,
        eyeDeskThresholdCm: eyeDeskThresholdCm,
        cameraTiltDeg: f.cameraTiltDeg,
        yawDev: yawDev,
        pitchUp: pitchUp,
        blink: f.blink,
        earRatio: earRatio,
        eyesClosed: b(closed),
        closedBy: closedBy,
        closedScore: closedScore,
        closedScoreSmooth: closedScoreSmooth,
        eyeLookDown: f.eyeLookDown,
        eyeLookDownSmooth: lookDownSmooth,
        eyeLookUp: f.eyeLookUp,
        eyeLookSide: f.eyeLookSide,
        jawOpen: f.jawOpen,
        writing: b(writing),
        tooClose: b(tooClose),
        writeShare: writeShare,
        handScale: handScale,
        handOnFace: b(handOnFace),
        faceVisible: b(f.faceVisible),
        faceRate: faceRate,
        dozeShadow: b(dozeShadow),
        headMotion: headMotion,
        lookingDown: b(lookingDown),
        crownRatio: seg?.crownRatio,
        crownDelta: crownDelta,
        hairFrac: seg?.hairFrac,
        personFrac: seg?.personFrac,
        segHead: b(segHead),
        covering: b(covering),
        poseVisible: b(f.poseVisible),
        headRatio: rawHeadRatio,
        hairShrunk: b(hairShrunk),
        slouchRel: slouchRel
      )
    )
  }
}
