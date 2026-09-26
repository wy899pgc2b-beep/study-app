import Foundation

/// 仮眠のすすめ(決定事項 D-23、設計書 3.8 の要件 6)。
/// 居眠り・うとうとが何度も来るとき(直近 20 分に 3 回)は、起きたところか、うとうとし始めたところで、20 分ほどの仮眠を勧める。
/// 眠っている間は勧めない(アラームで起こすのが先)。1 回勧めたら 1 時間は勧めない。回数と時間は仮の値(α 版の記録で見直す)
public struct NapAdvisor: Sendable {
  /// 仮眠の長さ(分)
  public static let napMinutes = 20

  public var windowSec: Double = 20 * 60
  /// これより短い間のうとうと・居眠りは、同じ 1 回と数える
  public var episodeGapSec: Double = 90
  public var minEpisodes = 3
  public var cooldownSec: Double = 60 * 60

  /// うとうと・居眠りの出来事の時刻(ミリ秒)
  public private(set) var times: [Double] = []
  private var lastSuggestT: Double?

  public init() {}

  /// 判定の出来事を渡す。仮眠を勧めるときは true
  public mutating func observe(_ ev: AnalysisEvent) -> Bool {
    switch ev.type {
    case .drowsy, .sleep: times.append(ev.t)
    case .wake: break
    default: return false
    }
    times.removeAll { ev.t - $0 > windowSec * 1000 }
    guard ev.type != .sleep else { return false }
    if let last = lastSuggestT, ev.t - last < cooldownSec * 1000 { return false }
    guard episodes >= minEpisodes else { return false }
    lastSuggestT = ev.t
    return true
  }

  /// 直近の窓の中の、うとうと・居眠りの回数(間が短いものは 1 回にまとめる)
  public var episodes: Int {
    var count = 0
    var last: Double?
    for t in times.sorted() {
      if last.map({ t - $0 > episodeGapSec * 1000 }) ?? true { count += 1 }
      last = t
    }
    return count
  }

  /// 仮眠をとった(それまでの回数は数え直す)
  public mutating func napTaken() {
    times = []
  }
}

extension AnalysisConfig {
  /// 利用者の設定(設計書の付録 A)を反映する。離席と判定するまでの時間(10〜60 秒)と、
  /// 「近すぎ」と判定する近づき方(キャリブレーションのときの距離より 15〜40% 近い)。検証モードでは使わない(試作品と同じ値で確かめる)
  public func tuned(awaySec: Double, closeRatio: Double) -> AnalysisConfig {
    var c = self
    c.awaySec = Swift.min(60, Swift.max(10, awaySec))
    c.eyeDeskCloseRatio = Swift.min(0.4, Swift.max(0.15, closeRatio))
    return c
  }
}
