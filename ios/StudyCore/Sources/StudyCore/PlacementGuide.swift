import Foundation

// 設置位置ガイド(設計書 3.4、MVP の設計 S-04)。試作品の app.js の guideStep と同じ確かめ方。
// 顔の位置と大きさ、明るさ、(正面に立てるとき)肩、(横向きのとき)傾き 10〜20° とペンを持った手が、3 秒続けてそろったら次に進む。
// バックカメラでは画面が見えないので、足りないものは声で知らせる。同じ種類の案内は一定の間をあける。

/// 位置合わせで読み上げる案内
public enum GuidePrompt: Equatable, Sendable {
  /// 顔の位置・大きさ・明るさ・肩
  case framing(FramingIssue)
  /// ペンを持った手を置いてもらう
  case placeHand
  /// 手を置いても映らない:スマホを起こすか遠ざける
  case handNotVisible(canRaise: Bool)
  /// 傾きが目安より小さい(寝かせる)・大きい(起こす)
  case tiltTooLow
  case tiltTooHigh
  /// 横向きに置いていない
  case turnLandscape

  public var speech: String {
    switch self {
    case .framing(let issue): return issue.speech
    case .placeHand: return "ペンを持った手を、ノートに書くときの位置に置いてください"
    case .handNotVisible(let canRaise):
      return canRaise ? "手元が映っていません。スマホをもう少し起こすか、少し遠ざけてください" : "手元が映っていません。スマホを少し遠ざけてください"
    case .tiltTooLow: return "スマホをもう少し寝かせてください"
    case .tiltTooHigh: return "スマホをもう少し起こしてください"
    case .turnLandscape: return "スマホを横向きにしてください"
    }
  }

  /// 同じ種類の案内を繰り返さない間隔の、種類の名前
  var key: String {
    switch self {
    case .framing: return "guide"
    case .placeHand, .handNotVisible: return "hand"
    case .tiltTooLow, .tiltTooHigh: return "tilt"
    case .turnLandscape: return "landscape"
    }
  }
}

/// 画面に並べる確認の項目
public struct GuideCheck: Equatable, Sendable {
  public var label: String
  public var ok: Bool
}

public struct PlacementGuide: Sendable {
  public let setup: SetupStyle
  /// そろってから次に進むまでの秒数
  public var holdSec = 3.0

  private var okSince: Double?
  private var handAt: Double?
  private var noHandSince: Double?
  private var lastSpoken: [String: Double] = [:]

  public init(setup: SetupStyle) {
    self.setup = setup
  }

  /// 位置合わせを始めるときの案内
  public static func introSpeech(_ setup: SetupStyle) -> String {
    switch setup {
    case .stand: return "スマホの位置を合わせます。顔と肩が映るように置いてください"
    case .tilt: return "スマホの位置を合わせます。スマホを45度くらいに寝かせて、顔と手元が映るように置いてください"
    // 胸から 45〜50cm では、体の近くの手元と頭の上の両方を収める余裕がほとんどない(技術検証の 14 回目)
    case .landscape:
      return "スマホの位置を合わせます。スマホを横向きにして、胸から60センチくらい離し、少し後ろに傾けて立てかけてください。ペンを持った手を、ノートに書くときの位置に置いてください"
    case .flat: return "スマホの位置を合わせます。顔が映るように置いてください"
    }
  }

  public struct Step: Equatable, Sendable {
    public var checks: [GuideCheck]
    public var prompts: [GuidePrompt]
    /// そろった状態が holdSec 続いた
    public var ready: Bool
  }

  /// deviceLandscape:端末が横向きか(重力から。分からなければ nil)
  public mutating func update(_ f: Features, deviceLandscape: Bool?) -> Step {
    let t = f.t
    let issues = checkFraming(f, setup: setup)
    let has = { (i: FramingIssue) in issues.contains(i) }
    var checks = [
      GuideCheck(label: "顔が映っている", ok: !has(.noFace)),
      GuideCheck(label: "顔が画面の中央付近にある", ok: f.faceVisible && !has(.offCenter)),
      GuideCheck(label: "スマホとの距離がちょうどよい", ok: f.faceVisible && !has(.tooFar) && !has(.tooClose)),
      GuideCheck(label: setup == .stand ? "肩まで映っている" : "(任意)肩まで映っている", ok: f.poseVisible),
      GuideCheck(label: "明るさが十分", ok: !has(.dark)),
    ]
    var prompts: [GuidePrompt] = []

    // 横向き:書く動作は手が映らないと判定できない(技術検証の 12・13 回目)。手の検出のちらつきは 1.5 秒まで許す
    let handRequired = setup == .landscape
    if !f.hands.isEmpty { handAt = t }
    let handOk = handAt.map { t - $0 <= 1500 } ?? false
    checks.append(GuideCheck(label: handRequired ? "ペンを持った手が、書く位置で映っている" : "(任意)手元の手が映っている", ok: handOk))
    if handRequired && !handOk {
      let since = noHandSince ?? t
      noHandSince = since
      // 手を置いても映らないときは、置き方を直してもらう(起こすと画面の下端が下がり、遠ざけると手元が画面に入る)
      if t - since > 12_000 {
        prompts.append(.handNotVisible(canRaise: f.cameraTiltDeg.map { $0 > 13 } ?? true))
      } else {
        prompts.append(.placeHand)
      }
    } else {
      noHandSince = nil
    }

    // 傾き:横向きは目安に入るまで進めない(技術検証の 9・12・13 回目)。斜め置きは知らせるだけ
    var tiltBlocks = false
    if let range = setup.tiltRangeDeg {
      let tiltRequired = setup == .landscape
      let tilt = f.cameraTiltDeg
      let inRange = tilt.map { range.contains($0) } ?? false
      tiltBlocks = tiltRequired && tilt != nil && !inRange
      let opt = tiltRequired ? "" : "(任意)"
      let label =
        tilt.map { "\(opt)スマホの傾き \(Int(jsRound($0)))°(目安 \(Int(range.lowerBound))〜\(Int(range.upperBound))°)" }
        ?? "\(opt)スマホの傾き:センサーを読めません"
      checks.append(GuideCheck(label: label, ok: inRange))
      if let tilt, !inRange { prompts.append(tilt < range.lowerBound ? .tiltTooLow : .tiltTooHigh) }
    }
    if setup == .landscape && deviceLandscape == false {
      checks.append(GuideCheck(label: "スマホが横向きになっていません", ok: false))
      prompts.append(.turnLandscape)
    }

    var ready = false
    if issues.isEmpty && !tiltBlocks && (handOk || !handRequired) && !(setup == .landscape && deviceLandscape == false) {
      let since = okSince ?? t
      okSince = since
      ready = t - since >= holdSec * 1000
    } else {
      okSince = nil
      if let first = issues.first { prompts.append(.framing(first)) }
    }
    return Step(checks: checks, prompts: ready ? [] : throttle(prompts, at: t), ready: ready)
  }

  /// 同じ種類の案内は、間をあけて読み上げる(試作品の voice.say の key と minIntervalSec)
  private mutating func throttle(_ prompts: [GuidePrompt], at t: Double) -> [GuidePrompt] {
    prompts.filter { p in
      let interval = Self.minIntervalSec(p, setup: setup)
      if let last = lastSpoken[p.key], t - last < interval * 1000 { return false }
      lastSpoken[p.key] = t
      return true
    }
  }

  static func minIntervalSec(_ p: GuidePrompt, setup: SetupStyle) -> Double {
    switch p {
    case .framing: return 7
    case .placeHand, .handNotVisible: return 8
    case .tiltTooLow, .tiltTooHigh: return setup == .landscape ? 8 : 30
    case .turnLandscape: return 15
    }
  }
}
