import Foundation

// 試作品(JavaScript)と同じ結果になるよう、数の扱いをそろえる小さな関数。

@inline(__always) func deg(_ r: Double) -> Double { r * 180 / Double.pi }
@inline(__always) func rad(_ d: Double) -> Double { d * Double.pi / 180 }
@inline(__always) func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { Swift.min(hi, Swift.max(lo, v)) }
@inline(__always) func dist(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double { hypot(ax - bx, ay - by) }
@inline(__always) func dist(_ a: Point2, _ b: Point2) -> Double { hypot(a.x - b.x, a.y - b.y) }

/// JavaScript の Math.round(0.5 は切り上げ、-0.5 は -0)
@inline(__always) func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

/// JavaScript で「真」とみなされる数(nil・0・NaN は偽)。真ならその値を返す
@inline(__always) func truthy(_ x: Double?) -> Double? {
  guard let x, x != 0, !x.isNaN else { return nil }
  return x
}

/// 中央値。nil と有限でない値は除く(試作品の median と同じ)。値がなければ nil
public func median(_ values: [Double?]) -> Double? {
  let v = values.compactMap { $0 }.filter { $0.isFinite }.sorted()
  if v.isEmpty { return nil }
  let m = v.count / 2
  return v.count % 2 == 1 ? v[m] : (v[m - 1] + v[m]) / 2
}

public func median(_ values: [Double]) -> Double? {
  median(values.map { Optional($0) })
}
