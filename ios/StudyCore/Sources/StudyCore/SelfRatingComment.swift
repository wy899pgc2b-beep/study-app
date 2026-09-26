import Foundation

// 体感と判定を並べる一言(設計書 3.14 の要件 4、決定事項 D-20)。
// 体感の 1 タップ(集中できた/ふつう/いまいち)と、平均集中度から見た段階を比べる。どちらが上でも責めない。

public enum FocusLevel: Int, Comparable, Sendable {
  case low, middle, high

  public static func < (a: FocusLevel, b: FocusLevel) -> Bool { a.rawValue < b.rawValue }

  /// 平均集中度からの段階(仮の区切り:70% 以上・45% 以上。α 版の体感の記録で見直す)
  public init?(avgFocus: Int?) {
    guard let v = avgFocus else { return nil }
    self = v >= 70 ? .high : v >= 45 ? .middle : .low
  }

  public init(_ rating: SelfRating) {
    switch rating {
    case .good: self = .high
    case .normal: self = .middle
    case .poor: self = .low
    }
  }
}

public func selfRatingComment(_ rating: SelfRating, avgFocus: Int?, focusMin: Double) -> String {
  let m = Int(jsRound(focusMin))
  guard let judged = FocusLevel(avgFocus: avgFocus) else { return "記録したよ。次の振り返りに使うね" }
  let felt = FocusLevel(rating)
  if felt == judged {
    switch felt {
    case .high: return "「集中できた」の感覚どおり、\(m)分しっかり集中していたよ"
    case .middle: return "感覚どおり、落ち着いて続けられていたよ。集中時間は\(m)分"
    case .low: return "感覚どおり、集中しにくい日だったみたい。それでも\(m)分は集中できていたよ"
    }
  }
  if felt < judged { return "感覚よりも、実際は集中できていたよ(\(m)分)" }
  return "集中できた感覚は大切にしよう。記録では\(m)分の集中だったよ"
}
