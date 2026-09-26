import Foundation

/// 学習項目(設計書 1 章の用語、3.1 の要件 1、3.20 の要件 5)。前回のものを引き継ぎ、変えるときだけ選び直す。
/// 候補は、前回 → よく使う順 → 自分で足したもの → 受験生がよく使う教科 の順に並べる
public enum Subjects {
  /// 最初に出す候補(受験生がよく使う教科)
  public static let suggestions = ["数学", "英語", "国語", "理科", "社会", "英単語", "過去問", "小論文"]
  public static let maxLength = 20

  /// 名前を整える(前後の空白と改行を除き、20 文字まで)。空なら nil
  public static func normalize(_ name: String) -> String? {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
    guard !trimmed.isEmpty else { return nil }
    return String(trimmed.prefix(maxLength))
  }

  /// 並べる順。history は最近の学習の学習項目(新しい順)
  public static func ranked(history: [String], custom: [String], limit: Int = 12) -> [String] {
    var out: [String] = []
    func add(_ s: String) {
      if !out.contains(s) { out.append(s) }
    }
    if let last = history.first { add(last) }
    // よく使う順(回数が同じなら、最近使った方を先に)
    var count: [String: Int] = [:]
    var firstSeen: [String: Int] = [:]
    for (i, s) in history.enumerated() {
      count[s, default: 0] += 1
      if firstSeen[s] == nil { firstSeen[s] = i }
    }
    for s in count.keys.sorted(by: { (count[$0]!, -firstSeen[$0]!) > (count[$1]!, -firstSeen[$1]!) }) { add(s) }
    custom.forEach(add)
    suggestions.forEach(add)
    return Array(out.prefix(limit))
  }

  /// 自分で足した項目か(候補にない名前)
  public static func isCustom(_ name: String) -> Bool { !suggestions.contains(name) }
}

/// 結果の画面の「時間の内訳」(MVP の設計 S-08)。机に向かっていた時間を、集中・学習・離席・一時停止・休憩に分ける
public struct TimeSlice: Equatable, Sendable {
  public enum Kind: String, CaseIterable, Sendable {
    /// 集中していた時間(集中度で重みをつけた学習時間)
    case focus
    /// 学習していたが、集中度が下がっていた時間
    case study
    case away
    case paused
    case breakTime = "break"
  }

  public var kind: Kind
  public var sec: Double
}

public func timeBreakdown(_ s: SessionSummary, breakSec: Double) -> [TimeSlice] {
  let focus = Swift.min(s.studySec, Swift.max(0, s.effectiveFocusMin * 60))
  return [
    TimeSlice(kind: .focus, sec: focus),
    TimeSlice(kind: .study, sec: Swift.max(0, s.studySec - focus)),
    TimeSlice(kind: .away, sec: Swift.max(0, s.awaySec)),
    TimeSlice(kind: .paused, sec: Swift.max(0, s.pausedSec)),
    TimeSlice(kind: .breakTime, sec: Swift.max(0, breakSec)),
  ]
}
