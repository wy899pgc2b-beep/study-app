import Foundation

/// 本人の「目を閉じたとき」の値(設計書 4.12)。確かめられなかった方は nil。
public struct ClosedRef: Codable, Equatable, Sendable {
  public var ear: Double?
  public var blink: Double?

  public init(ear: Double?, blink: Double?) {
    self.ear = ear
    self.blink = blink
  }
}

/// キャリブレーションの基準値(設計書 4.12)。名前は試作品と同じ。取れなかった値は nil。
public struct Calibration: Codable, Equatable, Sendable {
  public var yawDeg: Double?
  public var pitchDeg: Double?
  public var rollDeg: Double?
  public var blink: Double?
  public var ear: Double?
  public var slouchRatio: Double?
  public var tiltDeg: Double?
  public var tiltFromSensor: Bool?
  public var headHeight: Double?
  public var crownRatio: Double?
  public var hairFrac: Double?
  public var personFrac: Double?
  /// 【記録のみ】位置合わせで置いた手の高さ(画面の上端 0・下端 1)
  public var handY: Double?
  /// 【記録のみ】顔の上端の高さ(画面の上端 0)
  public var faceTopY: Double?
  public var measuredEyeDeskCm: Double?
  public var cameraHeightCm: Double?
  public var closedRef: ClosedRef?

  public init() {}
}

/// 目を閉じていると判定した理由(設計書 4.8)
public enum ClosureReason: String, Codable, Sendable {
  /// 深くうつむいていて EAR がとても小さい
  case down
  /// EAR がはっきり小さい
  case ear
  /// EAR がやや小さく閉じ具合もやや高い
  case earBlink
  /// 閉じ具合が高い
  case blink
  /// 本人の目を閉じたときの基準に近い
  case personal
}

/// 目の状態がはっきり読み取れるか(【記録のみ】)
public enum EyeSignal: String, Codable, Sendable {
  case clear
  case weak
}

/// キャリブレーション(設計書 4.12)。正しい姿勢で教材を見ている数秒間の特徴量から基準値を作る。
/// measuredEyeDeskCm:ユーザーが実際に測った目と机の距離。tiltDeg:端末の傾きが取れないときに使う、置き方の既定の傾き。
public func computeCalibration(_ features: [Features], measuredEyeDeskCm: Double?, tiltDeg: Double?) -> Calibration? {
  let faces = features.filter { $0.faceVisible }
  if faces.count < 3 { return nil }
  // 端末の傾きが取れていればそれを使い、取れなければ設置スタイルの既定値を使う
  let tiltOf = { (f: Features) in f.cameraTiltDeg ?? tiltDeg }
  let heights = faces
    .filter { $0.camDistCm?.isFinite == true }
    .map { heightAboveCameraCm(depthCm: $0.camDistCm, verticalOffsetCm: $0.verticalOffsetCm, tiltDeg: tiltOf($0)) }
  let h = median(heights)
  var c = Calibration()
  c.yawDeg = median(faces.map(\.yawDeg))
  c.pitchDeg = median(faces.map(\.pitchDeg))
  c.rollDeg = median(faces.map(\.rollDeg))
  c.blink = median(faces.map(\.blink))
  c.ear = median(faces.map(\.ear))
  c.slouchRatio = median(features.map(\.slouchRatio))
  c.tiltDeg = median(faces.map(tiltOf))
  c.tiltFromSensor = faces.contains { $0.cameraTiltDeg != nil }
  c.headHeight = median(features.map(\.headHeight))
  c.crownRatio = median(features.map { $0.seg?.crownRatio })
  c.hairFrac = median(features.map { $0.seg?.hairFrac })
  c.personFrac = median(features.map { $0.seg?.personFrac })
  c.handY = median(features.filter { !$0.hands.isEmpty }.map { f in f.hands.map(\.centroid.y).max()! })
  c.faceTopY = median(faces.map { $0.faceBox?.minY })
  c.measuredEyeDeskCm = measuredEyeDeskCm
  if let h, let m = measuredEyeDeskCm { c.cameraHeightCm = m - h }
  return c
}

/// 本人の「目を閉じたとき」の基準を作る(設計書 4.12)。キャリブレーションの後に 3 秒目を閉じてもらった間の特徴量から。
/// 目を閉じたことを確かめられなければ(目の形も閉じ具合も変わらなければ)nil。
public func computeClosedReference(_ features: [Features], _ cal: Calibration?, _ cfg: AnalysisConfig) -> ClosedRef? {
  let faces = features.filter { $0.faceVisible }
  guard let cal, faces.count >= 3 else { return nil }
  let ear = median(faces.map(\.ear))
  let blink = median(faces.map(\.blink))
  var earOk = false
  if let ear, let calEar = truthy(cal.ear) { earOk = calEar - ear >= calEar * cfg.personalMinEarDrop }
  var blinkOk = false
  if let blink, let calBlink = cal.blink { blinkOk = blink - calBlink >= cfg.personalMinBlinkRise }
  if !earOk && !blinkOk { return nil }
  return ClosedRef(ear: earOk ? ear : nil, blink: blinkOk ? blink : nil)
}

/// 【記録のみ】目の状態がはっきり読み取れるか。キャリブレーションで目を閉じたときの値で判断する。
public func eyeSignalQuality(_ cal: Calibration?, _ cfg: AnalysisConfig) -> EyeSignal {
  guard let cal, let ref = cal.closedRef else { return .weak }
  var earClear = false
  if let refEar = ref.ear, let calEar = truthy(cal.ear) { earClear = refEar / calEar < cfg.eyeSignalClearEarRatio }
  var blinkClear = false
  if let refBlink = ref.blink, let calBlink = cal.blink { blinkClear = refBlink - calBlink >= cfg.eyeSignalClearBlinkRise }
  return earClear || blinkClear ? .clear : .weak
}

/// 本人の基準で見た、目の閉じ具合(開いたとき 0、閉じたとき 1)。目の形と閉じ具合(表情係数)の平均。
/// 目を閉じたときの基準がなければ nil。基準の値が欠けていれば NaN になる(試作品と同じ)。
public func personalClosedScore(_ f: Features, _ cal: Calibration?) -> Double? {
  guard let cal, let ref = cal.closedRef, f.faceVisible else { return nil }
  var parts: [Double] = []
  if let refEar = ref.ear, let ear = f.ear {
    let calEar = cal.ear ?? .nan
    parts.append((calEar - ear) / (calEar - refEar))
  }
  if let refBlink = ref.blink, let blink = f.blink {
    let calBlink = cal.blink ?? .nan
    parts.append((blink - calBlink) / (refBlink - calBlink))
  }
  return parts.isEmpty ? nil : parts.reduce(0, +) / Double(parts.count)
}

/// 閉眼の判定(設計書 4.8)。下を向くとまぶたが閉じて見えるので、キャリブレーション値で補正する。
/// personalScore:本人の基準での閉じ具合、lookDown:視線の下向き(どちらも直近数秒の中央値)。
/// 閉じていると判定した理由を返す(閉じていなければ nil)。
public func eyeClosureReason(
  _ f: Features, _ cal: Calibration?, _ cfg: AnalysisConfig, personalScore: Double?, lookDown: Double?
) -> ClosureReason? {
  if !f.faceVisible { return nil }
  let personal = cfg.usePersonalClosed ? personalScore : nil
  let down = lookDown
  let calBlink = cal?.blink ?? 0.2
  let blinkThr = clamp(calBlink + cfg.blinkMarginOverCal, cfg.blinkMin, cfg.blinkMax)
  var earRatio: Double?
  if let calEar = truthy(cal?.ear), let ear = f.ear { earRatio = ear / calEar }
  var lookingFurtherDown = false
  if let calPitch = cal?.pitchDeg, let pitch = f.pitchDeg { lookingFurtherDown = pitch - calPitch > cfg.lookingDownExtraDeg }

  // 深くうつむいているときは、まぶたが下がって見えるので、目の形がはっきり閉じているときだけ閉眼とする
  if lookingFurtherDown {
    // 目を閉じたときはまぶたが下がり「視線の下向き」が大きくなるので、それも求める
    if let down, down < cfg.lookDownMinWhenBowed { return nil }
    if let earRatio, earRatio < cfg.earRatioStrongWhenDown { return .down }
    if let personal, personal >= cfg.personalCloseScoreWhenDown { return .personal }
    return nil
  }
  // 目の形(EAR)がはっきり小さい
  if let earRatio, earRatio < cfg.earRatioAlone { return .ear }
  guard let blink = f.blink else {
    if let earRatio, earRatio < cfg.earRatioStrong { return .ear }
    return nil
  }
  // 目の形がやや小さく、閉じ具合もやや高い。目の形だけでは判定しない
  let blinkWithEar = Swift.max(blinkThr - cfg.blinkSlackWithEar, cfg.blinkMinWithEar)
  if let earRatio, earRatio < cfg.earRatioStrong, blink >= blinkWithEar { return .earBlink }
  // 閉じ具合が高く、目の形も基準より小さい
  if blink >= blinkThr && (earRatio == nil || earRatio! < cfg.earRatioWithBlink) { return .blink }
  // 本人の目を閉じたときの基準に近い(カメラ・置き方・メガネで値が変わっても使える)
  if let personal, personal >= cfg.personalCloseScore { return .personal }
  return nil
}

/// 閉眼の判定(このフレームの値だけで判断する)
public func eyeClosureReason(_ f: Features, _ cal: Calibration?, _ cfg: AnalysisConfig) -> ClosureReason? {
  eyeClosureReason(f, cal, cfg, personalScore: personalClosedScore(f, cal), lookDown: f.eyeLookDown)
}

public func isEyesClosed(_ f: Features, _ cal: Calibration?, _ cfg: AnalysisConfig) -> Bool {
  eyeClosureReason(f, cal, cfg) != nil
}

/// 指先が顔の範囲(少し広げたもの)に入っているか。
public func handCoversFace(_ f: Features) -> Bool {
  guard f.faceVisible, let b = f.faceBox, !f.hands.isEmpty else { return false }
  let mx = (b.maxX - b.minX) * 0.1
  let my = (b.maxY - b.minY) * 0.1
  return f.hands.contains { h in
    LM.handTips.contains { i in
      guard let p = h.point(i) else { return false }
      return p.x > b.minX - mx && p.x < b.maxX + mx && p.y > b.minY - my && p.y < b.maxY + my
    }
  }
}
