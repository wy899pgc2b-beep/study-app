import Foundation

/// 設置位置ガイドの問題点(設計書 3.4)。rawValue は試作品のコードと同じ。
public enum FramingIssue: String, Codable, Sendable {
  case noFace = "no_face"
  case offCenter = "off_center"
  case tooFar = "too_far"
  case tooClose = "too_close"
  case noShoulders = "no_shoulders"
  case dark

  /// 画面に出す文
  public var message: String {
    switch self {
    case .noFace: return "顔が映っていません"
    case .offCenter: return "顔が画面の端に寄っています"
    case .tooFar: return "スマホが遠すぎます"
    case .tooClose: return "スマホが近すぎます"
    case .noShoulders: return "肩が映っていません"
    case .dark: return "暗すぎます"
    }
  }

  /// 読み上げる文
  public var speech: String {
    switch self {
    case .noFace: return "顔が映っていません。スマホの位置を調整してください"
    case .offCenter: return "顔が画面の端に寄っています。スマホの向きを調整してください"
    case .tooFar: return "スマホを少し近づけてください"
    case .tooClose: return "スマホを少し遠ざけてください"
    case .noShoulders: return "肩まで映るように、スマホを少し遠ざけてください"
    case .dark: return "部屋が暗いようです。明かりをつけてください"
    }
  }
}

/// 設置位置ガイドの判定(設計書 3.4)。問題がなければ空の配列。
public func checkFraming(_ f: Features, setup: SetupStyle = .stand) -> [FramingIssue] {
  var issues: [FramingIssue] = []
  if !f.faceVisible {
    issues.append(.noFace)
  } else {
    let b = f.faceBox
    let cx = b.map { ($0.minX + $0.maxX) / 2 } ?? .nan
    let cy = b.map { ($0.minY + $0.maxY) / 2 } ?? .nan
    // 幅・高さが分からなければ大きさは判断しない(試作品では NaN になり、比べると偽になる)
    var size = Double.nan
    if let w = f.width, let h = f.height, let fw = f.faceWidthNorm { size = (fw * w) / Swift.min(w, h) }
    if cx < 0.2 || cx > 0.8 || cy < 0.1 || cy > 0.75 { issues.append(.offCenter) }
    if size < 0.1 { issues.append(.tooFar) }
    if size > 0.45 { issues.append(.tooClose) }
  }
  // 正面に立てるとき以外(斜め置き・平置き)は肩が映らないことが多いので、肩は求めない
  if !f.poseVisible && setup == .stand { issues.append(.noShoulders) }
  if let br = f.brightness, br < 50 { issues.append(.dark) }
  return issues
}
