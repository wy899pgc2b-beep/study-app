import Foundation

/// 手の動きの速さ。検出のゆらぎで「止まっている手」が動いて見えないよう、指先と手首の位置を平滑化してから測る。
/// 速さの単位は、顔の幅を 1 とした 1 秒あたりの移動量。
public struct HandMotion: Sendable {
  struct Track: Sendable {
    var tip: Point2?
    var wrist: Point2?
    var rawTip: Landmark?
    var rawWrist: Landmark?
    var centroid: Point2
    var finger: Point2?
  }

  let cfg: AnalysisConfig
  var prev: [Track] = []
  var prevT: Double?

  public init(cfg: AnalysisConfig) {
    self.cfg = cfg
  }

  /// 手の速さと、指先の手首に対する速さ(手の大きさ / 秒)。測れなければ nil。
  public mutating func update(_ hands: [HandFeatures], t: Double, scale: Double) -> (speed: Double, fingerSpeed: Double?)? {
    let a = cfg.handSmoothing
    let dtSec = prevT.map { (t - $0) / 1000 } ?? 0
    prevT = t
    var next: [Track] = []
    var best: Double?
    var bestFinger: Double?
    // 画面の外にはみ出した特徴点は推定値で、止まっていても大きくゆれる(14 回目)。動きは画面の内側の点だけで測る
    let m = cfg.handEdgeMargin
    func inFrame(_ p: Landmark?) -> Bool {
      guard let p else { return false }
      return p.x >= m && p.x <= 1 - m && p.y >= m && p.y <= 1 - m
    }
    func lerp(_ p: Point2?, _ q: Point2?) -> Point2? {
      guard let p, let q else { return nil }
      return Point2(x: p.x + (q.x - p.x) * a, y: p.y + (q.y - p.y) * a)
    }
    func point(_ l: Landmark?) -> Point2? { l.map { Point2(x: $0.x, y: $0.y) } }

    for h in hands {
      let tip = h.point(8)
      let wrist = h.point(0)
      let cur = Track(tip: point(tip), wrist: point(wrist), rawTip: tip, rawWrist: wrist, centroid: h.centroid, finger: h.finger)
      var nearest: Track?
      var nd = Double.infinity
      for p in prev {
        let d = dist(cur.centroid, p.centroid)
        if d < nd {
          nd = d
          nearest = p
        }
      }
      if let nearest, nd < 0.25 {
        var sm = cur
        sm.tip = lerp(nearest.tip, cur.tip)
        sm.wrist = lerp(nearest.wrist, cur.wrist)
        let tipOk = inFrame(cur.rawTip) && inFrame(nearest.rawTip)
        let wristOk = inFrame(cur.rawWrist) && inFrame(nearest.rawWrist)
        if dtSec > 0 && dtSec <= 1 && (tipOk || wristOk) {
          let tipMove = tipOk ? dist(sm.tip!, nearest.tip!) : 0
          let wristMove = wristOk ? dist(sm.wrist!, nearest.wrist!) : 0
          let v = Swift.max(tipMove, wristMove) / scale / dtSec
          best = Swift.max(best ?? 0, v)
          // 指先の手首に対する動き(手全体の移動を除く)。平滑化しない
          if tipOk && wristOk, let cf = cur.finger, let nf = nearest.finger {
            bestFinger = Swift.max(bestFinger ?? 0, dist(cf, nf) / dtSec)
          }
        }
        next.append(sm)
      } else {
        next.append(cur)
      }
    }
    prev = next
    guard let best else { return nil }
    return (best, bestFinger)
  }
}
