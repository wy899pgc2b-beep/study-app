import Foundation

// 結果カード(設計書 3.14、MVP の設計 4 章「結果カードの文」)。
// 1 行目は褒め言葉、2 行目は集中時間と平均集中度、3 行目は明日の一手。数字が低い日も責めない。
// 同じ文が続くと飽きるので、規則ごとに言い回しを複数用意し、前回と同じ文は続けて出さない(競合アプリの分析)。

public struct ResultCard: Equatable, Sendable {
  public var praise: String
  /// 集中時間(分)
  public var focusMin: Double
  /// 平均集中度(%)
  public var avgFocus: Int?
  /// 学習時間(分)
  public var studyMin: Double
  public var nextStep: String
  /// どの規則で選んだか(記録と確認のため)
  public var praiseRule: PraiseRule
  public var nextStepRule: NextStepRule
}

public enum PraiseRule: String, Codable, Sendable, CaseIterable {
  /// 集中時間が過去 7 日の平均より長い
  case longerThanWeek
  /// 居眠りがなく、30 分以上続けた
  case stayedAwake
  /// 一時停止(スマホに触った)が 0 回
  case noTouch
  case showedUp
}

public enum NextStepRule: String, Codable, Sendable, CaseIterable {
  /// 居眠り・うとうとがあった
  case sleepy
  /// 集中度が下がり始めた時間がある
  case focusDropped
  /// 近すぎ・前かがみが 2 回以上
  case posture
  /// 一時停止が 3 回以上
  case touchedOften
  case keepGoing
}

public struct ResultCardInput: Sendable {
  public var summary: SessionSummary
  public var events: [AnalysisEvent]
  public var pauseCount: Int
  /// 過去 7 日の学習の集中時間(分)。記録がなければ空
  public var recentFocusMin: [Double]
  /// 前回の結果カードの文(同じ文を続けないため)
  public var previousPraise: String?
  public var previousNextStep: String?

  public init(
    summary: SessionSummary, events: [AnalysisEvent], pauseCount: Int, recentFocusMin: [Double] = [], previousPraise: String? = nil,
    previousNextStep: String? = nil
  ) {
    self.summary = summary
    self.events = events
    self.pauseCount = pauseCount
    self.recentFocusMin = recentFocusMin
    self.previousPraise = previousPraise
    self.previousNextStep = previousNextStep
  }
}

public enum ResultCardText {
  /// {n}:平均より長かった分、{m}:学習した分、{x}:集中が下がり始めた分
  public static let praise: [PraiseRule: [String]] = [
    .longerThanWeek: [
      "集中時間が、この 1 週間の平均より {n} 分長かったね",
      "この 1 週間の平均より {n} 分多く集中できたね",
      "いつもより {n} 分長く集中できたね",
    ],
    .stayedAwake: [
      "最後まで眠らずに続けられたね",
      "眠気に負けずに、最後までやりきったね",
      "{m} 分、しっかり起きて続けられたね",
    ],
    .noTouch: [
      "一度もスマホに触らなかったね",
      "スマホに触らずに、最後まで続けられたね",
      "スマホを置いたまま、学習に向き合えたね",
    ],
    .showedUp: [
      "今日も机に向かえたね",
      "机に向かえたことが、何よりの一歩だね",
      "今日も始められたね。おつかれさま",
    ],
  ]

  public static let nextStep: [NextStepRule: [String]] = [
    .sleepy: [
      "眠くなる前に、25 分ごとに短く休もう",
      "眠気が来る前に、25 分で一度立ち上がってみよう",
      "明日は休憩タイマーを 25 分 + 5 分にしてみよう",
    ],
    .focusDropped: [
      "{x} 分を過ぎると集中が下がりやすいので、明日は {x} 分で休憩しよう",
      "集中が続くのは {x} 分くらい。明日は {x} 分で一度休もう",
      "{x} 分ごとに休むと、集中が続きやすいかも",
    ],
    .posture: [
      "教材を少し立てると、顔が近づきにくくなるよ",
      "目と教材の間を、少しだけ広げてみよう",
      "背すじを伸ばしやすい椅子の高さを試してみよう",
    ],
    .touchedOften: [
      "スマホは手の届かないところに置いてみよう",
      "始める前に、通知を切っておこう",
      "触りたくなったら、休憩まで待ってみよう",
    ],
    .keepGoing: [
      "明日も同じ時間に始めよう",
      "明日も、この調子で机に向かおう",
      "明日は、今日より 5 分だけ長くやってみよう",
    ],
  ]
}

/// 集中度が下がり始めた分(直近 5 分の平均が、最初の 10 分の平均の 7 割を下回った最初の分)。5 分単位に切り下げ、10 分以上
public func focusDropMinute(_ scores: [Int?]) -> Int? {
  let valid = scores.compactMap { $0 }.map(Double.init)
  guard valid.count >= 15 else { return nil }
  func avg(_ s: ArraySlice<Double>) -> Double { s.reduce(0, +) / Double(s.count) }
  let base = avg(valid[0..<10])
  guard base > 0 else { return nil }
  for i in 10...(valid.count - 5) where avg(valid[i..<(i + 5)]) < base * 0.7 {
    return Swift.max(10, i / 5 * 5)
  }
  return nil
}

public func buildResultCard<R: RandomNumberGenerator>(_ input: ResultCardInput, using rng: inout R) -> ResultCard {
  let s = input.summary
  let focusMin = s.effectiveFocusMin
  let studyMin = s.studySec / 60
  let sleepy = input.events.contains { $0.type == .sleep || $0.type == .drowsy }

  var praiseRule = PraiseRule.showedUp
  var n = 0
  if !input.recentFocusMin.isEmpty {
    let diff = focusMin - input.recentFocusMin.reduce(0, +) / Double(input.recentFocusMin.count)
    n = Int(jsRound(diff))
    if n >= 1 { praiseRule = .longerThanWeek }
  }
  if praiseRule == .showedUp {
    if !sleepy && studyMin >= 30 {
      praiseRule = .stayedAwake
    } else if input.pauseCount == 0 {
      praiseRule = .noTouch
    }
  }

  let drop = focusDropMinute(s.scores)
  let postureCount = input.events.filter { $0.type == .postureClose || $0.type == .postureSlouch }.count
  let nextRule: NextStepRule
  if sleepy {
    nextRule = .sleepy
  } else if drop != nil {
    nextRule = .focusDropped
  } else if postureCount >= 2 {
    nextRule = .posture
  } else if input.pauseCount >= 3 {
    nextRule = .touchedOften
  } else {
    nextRule = .keepGoing
  }

  let values = ["n": n, "m": Int(jsRound(studyMin)), "x": drop ?? 0]
  let praise = pick(ResultCardText.praise[praiseRule] ?? [], values: values, avoiding: input.previousPraise, using: &rng)
  let next = pick(ResultCardText.nextStep[nextRule] ?? [], values: values, avoiding: input.previousNextStep, using: &rng)
  return ResultCard(
    praise: praise, focusMin: focusMin, avgFocus: s.avgFocus, studyMin: studyMin, nextStep: next, praiseRule: praiseRule,
    nextStepRule: nextRule)
}

public func buildResultCard(_ input: ResultCardInput) -> ResultCard {
  var rng = SystemRandomNumberGenerator()
  return buildResultCard(input, using: &rng)
}

private func fill(_ template: String, _ values: [String: Int]) -> String {
  var s = template
  for (k, v) in values { s = s.replacingOccurrences(of: "{\(k)}", with: String(v)) }
  return s
}

private func pick<R: RandomNumberGenerator>(_ templates: [String], values: [String: Int], avoiding previous: String?, using rng: inout R)
  -> String
{
  let texts = templates.map { fill($0, values) }
  let fresh = texts.filter { $0 != previous }
  return (fresh.isEmpty ? texts : fresh).randomElement(using: &rng) ?? ""
}
