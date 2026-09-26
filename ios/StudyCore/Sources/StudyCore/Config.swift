// このファイルは prototype/tools/gen-swift-config.mjs で prototype/js/config.js から作る。手で書き換えない。
// もとにした試作品の版:poc-24

import Foundation

/// 判定のしきい値(設計書 4 章)。値の意味と調整の経緯は prototype/js/config.js のコメントを参照。
public struct AnalysisConfig: Codable, Equatable, Sendable {
  public static let prototypeVersion = "poc-24"

  public var analysisFps: Double = 5
  public var awaySec: Double = 20
  public var returnSec: Double = 3
  public var lookAwayYawDeg: Double = 25
  public var lookAwayPitchUpDeg: Double = 20
  public var lookAwaySec: Double = 3
  public var blinkMarginOverCal: Double = 0.07
  public var blinkMin: Double = 0.55
  public var blinkMax: Double = 0.8
  public var earRatioWithBlink: Double = 0.95
  public var earRatioAlone: Double = 0.5
  public var earRatioStrong: Double = 0.8
  public var blinkSlackWithEar: Double = 0.1
  public var blinkMinWithEar: Double = 0.5
  public var earRatioStrongWhenDown: Double = 0.45
  public var usePersonalClosed: Bool = true
  public var personalCloseScore: Double = 0.85
  public var personalCloseScoreWhenDown: Double = 0.95
  public var personalSmoothSec: Double = 2
  public var personalMinEarDrop: Double = 0.15
  public var personalMinBlinkRise: Double = 0.1
  public var eyeSignalClearEarRatio: Double = 0.4
  public var eyeSignalClearBlinkRise: Double = 0.35
  public var closedGapSec: Double = 1
  public var lookingDownExtraDeg: Double = 10
  public var lookDownMinWhenBowed: Double = 0.35
  public var drowsyClosedSec: Double = 3
  public var sleepClosedSec: Double = 10
  public var perclosWindowSec: Double = 60
  public var perclosDrowsy: Double = 0.3
  public var perclosMinObservedSec: Double = 20
  public var perclosMinFaceRate: Double = 0.7
  public var wakeOpenSec: Double = 2
  public var faceDownSec: Double = 20
  public var faceGapSec: Double = 2
  public var headLowRatio: Double = 0.5
  public var headLowRatioLandscape: Double = 0
  public var faceRateWindowSec: Double = 10
  public var headDownRatio: Double = 0.85
  public var crownBowDelta: Double = 0.1
  public var segMinHairFrac: Double = 0.005
  public var segHairRatio: Double = 0.5
  public var segPersonRatio: Double = 0.4
  public var coverPersonFrac: Double = 0.85
  public var coverEyeDeskCm: Double = 10
  public var segAbsentRatio: Double = 0.2
  public var segAbsentFrac: Double = 0.05
  public var hairShrinkRatio: Double = 0.7
  public var headOnDeskHairRatio: Double = 4
  public var headMotionWindowSec: Double = 2
  public var dozeHeadStill: Double = 0.05
  public var dozeHandStill: Double = 0.1
  public var dozeShadowSec: Double = 5
  public var handWindowSec: Double = 1.5
  public var handSmoothing: Double = 0.5
  public var writeSpeedMin: Double = 0.12
  public var handEdgeMargin: Double = 0.01
  public var penGripPinchMax: Double = 0.35
  public var yawnJawOpen: Double = 0.5
  public var yawnSec: Double = 1.5
  public var drowsyBeepMinSec: Double = 60
  public var habitTouchSec: Double = 1
  public var habitGapSec: Double = 0.5
  public var chinRestSec: Double = 5
  public var chinRestMaxSpeed: Double = 0.3
  public var habitMergeSec: Double = 5
  public var irisDiameterCm: Double = 1.17
  public var cameraFovLongSideDeg: Double = 69
  public var eyeDeskCloseRatio: Double = 0.25
  public var eyeDeskAlertSec: Double = 20
  public var postureGapSec: Double = 3
  public var eyeDeskGuidelineCm: Double = 30
  public var headCloseRatio: Double = 0.75
  public var slouchCloseRatio: Double = 0.55
  public var slouchRatio: Double = 0.8
  public var slouchAlertSec: Double = 60
  public var tiltDeg: Double = 15
  public var tiltAlertSec: Double = 60
  public var minEvaluableSec: Double = 30
  public var drowsyWeight: Double = 40
  public var habitPenalty: Double = 3
  public var habitPenaltyMax: Double = 15
  public var interruptionPenalty: Double = 2
  public var interruptionPenaltyMax: Double = 10

  public init() {}

  // 足りない項目は既定値のままにする(試作品のテストは一部の値だけを変えた設定を使う)
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    if let x = try c.decodeIfPresent(Double.self, forKey: .analysisFps) { analysisFps = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .awaySec) { awaySec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .returnSec) { returnSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .lookAwayYawDeg) { lookAwayYawDeg = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .lookAwayPitchUpDeg) { lookAwayPitchUpDeg = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .lookAwaySec) { lookAwaySec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .blinkMarginOverCal) { blinkMarginOverCal = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .blinkMin) { blinkMin = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .blinkMax) { blinkMax = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .earRatioWithBlink) { earRatioWithBlink = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .earRatioAlone) { earRatioAlone = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .earRatioStrong) { earRatioStrong = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .blinkSlackWithEar) { blinkSlackWithEar = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .blinkMinWithEar) { blinkMinWithEar = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .earRatioStrongWhenDown) { earRatioStrongWhenDown = x }
    if let x = try c.decodeIfPresent(Bool.self, forKey: .usePersonalClosed) { usePersonalClosed = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .personalCloseScore) { personalCloseScore = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .personalCloseScoreWhenDown) { personalCloseScoreWhenDown = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .personalSmoothSec) { personalSmoothSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .personalMinEarDrop) { personalMinEarDrop = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .personalMinBlinkRise) { personalMinBlinkRise = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .eyeSignalClearEarRatio) { eyeSignalClearEarRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .eyeSignalClearBlinkRise) { eyeSignalClearBlinkRise = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .closedGapSec) { closedGapSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .lookingDownExtraDeg) { lookingDownExtraDeg = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .lookDownMinWhenBowed) { lookDownMinWhenBowed = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .drowsyClosedSec) { drowsyClosedSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .sleepClosedSec) { sleepClosedSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .perclosWindowSec) { perclosWindowSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .perclosDrowsy) { perclosDrowsy = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .perclosMinObservedSec) { perclosMinObservedSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .perclosMinFaceRate) { perclosMinFaceRate = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .wakeOpenSec) { wakeOpenSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .faceDownSec) { faceDownSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .faceGapSec) { faceGapSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headLowRatio) { headLowRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headLowRatioLandscape) { headLowRatioLandscape = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .faceRateWindowSec) { faceRateWindowSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headDownRatio) { headDownRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .crownBowDelta) { crownBowDelta = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .segMinHairFrac) { segMinHairFrac = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .segHairRatio) { segHairRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .segPersonRatio) { segPersonRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .coverPersonFrac) { coverPersonFrac = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .coverEyeDeskCm) { coverEyeDeskCm = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .segAbsentRatio) { segAbsentRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .segAbsentFrac) { segAbsentFrac = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .hairShrinkRatio) { hairShrinkRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headOnDeskHairRatio) { headOnDeskHairRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headMotionWindowSec) { headMotionWindowSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .dozeHeadStill) { dozeHeadStill = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .dozeHandStill) { dozeHandStill = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .dozeShadowSec) { dozeShadowSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .handWindowSec) { handWindowSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .handSmoothing) { handSmoothing = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .writeSpeedMin) { writeSpeedMin = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .handEdgeMargin) { handEdgeMargin = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .penGripPinchMax) { penGripPinchMax = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .yawnJawOpen) { yawnJawOpen = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .yawnSec) { yawnSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .drowsyBeepMinSec) { drowsyBeepMinSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .habitTouchSec) { habitTouchSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .habitGapSec) { habitGapSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .chinRestSec) { chinRestSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .chinRestMaxSpeed) { chinRestMaxSpeed = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .habitMergeSec) { habitMergeSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .irisDiameterCm) { irisDiameterCm = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .cameraFovLongSideDeg) { cameraFovLongSideDeg = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .eyeDeskCloseRatio) { eyeDeskCloseRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .eyeDeskAlertSec) { eyeDeskAlertSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .postureGapSec) { postureGapSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .eyeDeskGuidelineCm) { eyeDeskGuidelineCm = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .headCloseRatio) { headCloseRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .slouchCloseRatio) { slouchCloseRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .slouchRatio) { slouchRatio = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .slouchAlertSec) { slouchAlertSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .tiltDeg) { tiltDeg = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .tiltAlertSec) { tiltAlertSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .minEvaluableSec) { minEvaluableSec = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .drowsyWeight) { drowsyWeight = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .habitPenalty) { habitPenalty = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .habitPenaltyMax) { habitPenaltyMax = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .interruptionPenalty) { interruptionPenalty = x }
    if let x = try c.decodeIfPresent(Double.self, forKey: .interruptionPenaltyMax) { interruptionPenaltyMax = x }
  }
}

/// 置き方ごとのカメラの上向きの傾き(度)。センサーが読めないときに使う。
public enum SetupStyle: String, Codable, Sendable, CaseIterable {
  case stand
  case tilt
  case landscape
  case flat

  public var defaultTiltDeg: Double {
    switch self {
    case .stand: return 0
    case .tilt: return 45
    case .landscape: return 20
    case .flat: return 90
    }
  }

  /// 位置合わせで求める傾きの範囲(度)。範囲のない置き方は nil。
  public var tiltRangeDeg: ClosedRange<Double>? {
    switch self {
    case .stand: return nil
    case .tilt: return 35...55
    case .landscape: return 10...20
    case .flat: return nil
    }
  }
}
