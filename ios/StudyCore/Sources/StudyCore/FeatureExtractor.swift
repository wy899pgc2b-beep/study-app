import Foundation

// 1 フレーム分の検出結果から特徴量を取り出す(設計書 4.3)。試作品の extractFeatures と同じ計算。

enum LM {
  static let leftEye = (outer: 33, inner: 133, top: [160, 158], bottom: [144, 153])
  static let rightEye = (outer: 263, inner: 362, top: [385, 387], bottom: [380, 373])
  static let forehead = 10
  static let chin = 152
  static let faceLeftOuter = 33
  static let faceRightOuter = 263
  static let irisLeft = [469, 470, 471, 472]
  static let irisRight = [474, 475, 476, 477]
  static let poseNose = 0
  static let poseLeftEye = 2
  static let poseRightEye = 5
  static let poseLeftShoulder = 11
  static let poseRightShoulder = 12
  static let handTips = [4, 8, 12, 16, 20]
  static let handKnuckles = [0, 5, 9, 13, 17]
}

private struct Px {
  var x: Double
  var y: Double
  var z: Double
}

@inline(__always) private func toPx(_ p: Landmark, _ w: Double, _ h: Double) -> Px {
  Px(x: p.x * w, y: p.y * h, z: (p.z ?? 0) * w)
}

@inline(__always) private func dist(_ a: Px, _ b: Px) -> Double { hypot(a.x - b.x, a.y - b.y) }

private func eyeAspectRatio(
  _ lm: [Landmark], _ eye: (outer: Int, inner: Int, top: [Int], bottom: [Int]), _ w: Double, _ h: Double
) -> Double? {
  let p = { (i: Int) in toPx(lm[i], w, h) }
  let width = dist(p(eye.outer), p(eye.inner))
  if width == 0 { return nil }
  let h1 = dist(p(eye.top[0]), p(eye.bottom[0]))
  let h2 = dist(p(eye.top[1]), p(eye.bottom[1]))
  return (h1 + h2) / (2 * width)
}

private func irisDiameterPx(_ lm: [Landmark], _ ring: [Int], _ w: Double, _ h: Double) -> Double {
  let q = ring.map { toPx(lm[$0], w, h) }
  return (dist(q[0], q[2]) + dist(q[1], q[3])) / 2
}

extension HandFeatures {
  /// i 番目の特徴点(なければ nil)
  func point(_ i: Int) -> Landmark? { i < pts.count ? pts[i] : nil }
}

public func extractFeatures(_ frame: Frame, _ cfg: AnalysisConfig) -> Features {
  let W = frame.width
  let H = frame.height
  var f = Features(t: frame.t)
  f.width = W
  f.height = H
  f.brightness = frame.brightness
  f.cameraTiltDeg = frame.cameraTiltDeg
  f.hands = frame.hands.map { pts in
    let cx = pts.reduce(0) { $0 + $1.x } / Double(pts.count)
    let cy = pts.reduce(0) { $0 + $1.y } / Double(pts.count)
    var hand = HandFeatures(pts: pts, centroid: Point2(x: cx, y: cy))
    // 手の形:手の大きさ(手首〜中指の付け根)を 1 とした、親指と人差し指の先の距離(ペンを持つと小さくなる)
    let wrist = toPx(pts[0], W, H)
    let size = dist(wrist, toPx(pts[9], W, H))
    hand.sizeNorm = size / W
    if size > 0 {
      let tip = toPx(pts[8], W, H)
      hand.pinch = dist(toPx(pts[4], W, H), tip) / size
      hand.finger = Point2(x: (tip.x - wrist.x) / size, y: (tip.y - wrist.y) / size)
    }
    return hand
  }

  if let lm = frame.face?.landmarks, lm.count >= 468 {
    f.faceVisible = true
    var minX = 1.0, maxX = 0.0, minY = 1.0, maxY = 0.0
    for i in 0..<468 {
      let p = lm[i]
      if p.x < minX { minX = p.x }
      if p.x > maxX { maxX = p.x }
      if p.y < minY { minY = p.y }
      if p.y > maxY { maxY = p.y }
    }
    f.faceBox = Box(minX: minX, maxX: maxX, minY: minY, maxY: maxY)
    f.chin = Point2(x: lm[LM.chin].x, y: lm[LM.chin].y)

    let earL = eyeAspectRatio(lm, LM.leftEye, W, H)
    let earR = eyeAspectRatio(lm, LM.rightEye, W, H)
    if let earL, let earR { f.ear = (earL + earR) / 2 }

    let bs = frame.face?.blendshapes
    if let l = bs?["eyeBlinkLeft"], let r = bs?["eyeBlinkRight"] { f.blink = (l + r) / 2 }
    // 【記録のみ】視線の向き(表情係数)
    func pair(_ a: String, _ b: String) -> Double? {
      guard let x = bs?[a], let y = bs?[b] else { return nil }
      return (x + y) / 2
    }
    f.eyeLookDown = pair("eyeLookDownLeft", "eyeLookDownRight")
    f.eyeLookUp = pair("eyeLookUpLeft", "eyeLookUpRight")
    // 横向きの視線:両目が同じ向き(左目は外・右目は内、またはその逆)を向いている強さ
    if let sideA = pair("eyeLookOutLeft", "eyeLookInRight"), let sideB = pair("eyeLookInLeft", "eyeLookOutRight") {
      f.eyeLookSide = Swift.max(sideA, sideB)
    }
    // 【記録のみ】口の開き(あくび)
    f.jawOpen = bs?["jawOpen"]

    let a = toPx(lm[LM.faceLeftOuter], W, H)
    let b = toPx(lm[LM.faceRightOuter], W, H)
    let top = toPx(lm[LM.forehead], W, H)
    let chin = toPx(lm[LM.chin], W, H)
    f.rollDeg = deg(atan2(b.y - a.y, b.x - a.x))
    f.yawDeg = deg(atan2(b.z - a.z, b.x - a.x))
    // 正 = 下を向く(あごが額より奥に行く)
    f.pitchDeg = deg(atan2(chin.z - top.z, chin.y - top.y))
    let eyeMid = Point2(
      x: (lm[LM.faceLeftOuter].x + lm[LM.faceRightOuter].x) / 2, y: (lm[LM.faceLeftOuter].y + lm[LM.faceRightOuter].y) / 2)
    f.eyeMid = eyeMid
    f.faceWidthNorm = maxX - minX
    f.faceHeightNorm = maxY - minY

    if lm.count >= 478 {
      let irisPx = (irisDiameterPx(lm, LM.irisLeft, W, H) + irisDiameterPx(lm, LM.irisRight, W, H)) / 2
      f.irisPx = irisPx
      let fpx = focalLengthPx(width: W, height: H, fovLongSideDeg: cfg.cameraFovLongSideDeg)
      if irisPx > 0 {
        let camDist = (fpx * cfg.irisDiameterCm) / irisPx
        f.camDistCm = camDist
        let v = eyeMid.y * H
        f.verticalOffsetCm = ((v - H / 2) * camDist) / fpx  // 下向きが正
      }
    }
  }

  if let pose = frame.pose, pose.count > LM.poseRightShoulder {
    let ls = pose[LM.poseLeftShoulder]
    let rs = pose[LM.poseRightShoulder]
    if (ls.visibility ?? 1) > 0.5 && (rs.visibility ?? 1) > 0.5 {
      f.poseVisible = true
      let lsp = toPx(ls, W, H)
      let rsp = toPx(rs, W, H)
      let shoulderWidth = dist(lsp, rsp)
      f.shoulderTiltDeg = deg(atan2(lsp.y - rsp.y, lsp.x - rsp.x))
      let shoulderMid = Point2(x: (ls.x + rs.x) / 2, y: (ls.y + rs.y) / 2)
      f.shoulderMid = shoulderMid
      var eyeY: Double?
      if let eyeMid = f.eyeMid {
        eyeY = eyeMid.y * H
      } else {
        let le = pose[LM.poseLeftEye]
        let re = pose[LM.poseRightEye]
        if (le.visibility ?? 1) > 0.5 && (re.visibility ?? 1) > 0.5 { eyeY = ((le.y + re.y) / 2) * H }
      }
      if let eyeY, shoulderWidth > 0 { f.slouchRatio = (shoulderMid.y * H - eyeY) / shoulderWidth }
      // 肩から鼻までの高さ(肩幅を 1 とする)。顔の特徴点が取れないとき(顔を机に近づけた・伏せた)にも使える
      let nose = pose[LM.poseNose]
      if (nose.visibility ?? 1) >= 0.5 && shoulderWidth > 0 {
        f.headHeight = ((shoulderMid.y - nose.y) * H) / shoulderWidth
        // 頭の動きを測るための鼻の位置(肩幅を 1 とする)
        f.noseN = Point2(x: (nose.x * W) / shoulderWidth, y: (nose.y * H) / shoulderWidth)
      }
      f.headLow = f.eyeMid != nil ? false : (nose.visibility ?? 1) < 0.5 || nose.y > shoulderMid.y - 0.05
    }
  }

  // 髪・顔の肌などの面積(頭頂部の見え方。設計書 4.9)。5 フレームに 1 回だけ計算するので、ないこともある
  f.seg = frame.segment
  f.present = f.faceVisible || f.poseVisible
  return f
}
