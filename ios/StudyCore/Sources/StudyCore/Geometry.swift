import Foundation

// カメラと目の位置関係の計算(設計書 4.9)。試作品の analysis.js と同じ式。

/// カメラの焦点距離(ピクセル)。長辺の画角から求める。
public func focalLengthPx(width: Double, height: Double, fovLongSideDeg: Double) -> Double {
  Swift.max(width, height) / 2 / tan(rad(fovLongSideDeg) / 2)
}

/// 端末の傾き(ブラウザの DeviceOrientation の beta・gamma)から、カメラが水平より何度上を向いているかを求める。
/// 画面の法線(フロントカメラの向き)の上向き成分は cos(beta)·cos(gamma)。バックカメラは逆向き。
public func cameraTiltFromOrientation(betaDeg: Double, gammaDeg: Double, backCamera: Bool) -> Double? {
  guard betaDeg.isFinite, gammaDeg.isFinite else { return nil }
  let up = clamp(cos(rad(betaDeg)) * cos(rad(gammaDeg)), -1, 1)
  let elevation = deg(asin(up))
  return backCamera ? -elevation : elevation
}

/// カメラから見た目の高さ(cm)。カメラが上に tiltDeg 傾いているとき、目がカメラよりどれだけ上にあるか。
/// 値が欠けていれば NaN(試作品の undefined を含む計算と同じ)。
public func heightAboveCameraCm(depthCm: Double?, verticalOffsetCm: Double?, tiltDeg: Double?) -> Double {
  let t = rad(tiltDeg ?? .nan)
  return -(verticalOffsetCm ?? .nan) * cos(t) + (depthCm ?? .nan) * sin(t)
}

/// 目と机の距離の推定値(cm)。キャリブレーションがない、または虹彩が取れないときは nil。
/// 値が欠けて数にならないときも nil(試作品では NaN。比べると常に偽になるので同じ扱い)。
public func estimateEyeDeskCm(_ f: Features, _ cal: Calibration?) -> Double? {
  guard let cal, let cameraHeightCm = cal.cameraHeightCm, let camDistCm = f.camDistCm, camDistCm.isFinite else { return nil }
  let tilt = f.cameraTiltDeg ?? cal.tiltDeg
  let v = cameraHeightCm + heightAboveCameraCm(depthCm: camDistCm, verticalOffsetCm: f.verticalOffsetCm, tiltDeg: tilt)
  return v.isNaN ? nil : v
}

/// 端末が横向きか(DeviceOrientation の beta・gamma から)。平らに置いていて分からないときは nil。
public func deviceIsLandscape(betaDeg: Double, gammaDeg: Double) -> Bool? {
  guard betaDeg.isFinite, gammaDeg.isFinite else { return nil }
  let yUp = abs(sin(rad(betaDeg)))  // 端末の縦方向がどれだけ上を向いているか
  let xUp = abs(cos(rad(betaDeg)) * sin(rad(gammaDeg)))  // 横方向
  if Swift.max(xUp, yUp) < 0.3 { return nil }
  return xUp > yUp
}
