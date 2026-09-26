import Foundation
import XCTest

@testable import StudyCore

/// 結果カードの文の規則(MVP の設計 4 章)
final class ResultCardTests: XCTestCase {
  struct SeededRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      return state
    }
  }

  /// minutes 分、kind の状態で学習した記録。scores を渡すと、1 分ごとの集中度がその値になるように作る
  func summary(minutes: Int, kind: TimeKind = .think, events: [AnalysisEvent] = []) -> SessionSummary {
    var rec = SessionRecorder(startT: 0, cfg: AnalysisConfig())
    for sec in 1...(minutes * 60) { rec.add(t: Double(sec) * 1000 - 1, dtSec: 1, kind: kind) }
    for e in events { rec.addEvent(e) }
    return rec.summary()
  }

  func card(_ input: ResultCardInput, seed: UInt64 = 1) -> ResultCard {
    var rng = SeededRandom(state: seed)
    return buildResultCard(input, using: &rng)
  }

  func testPraiseRulesInOrder() {
    let s40 = summary(minutes: 40)
    // 過去 7 日の平均より長い
    let longer = card(ResultCardInput(summary: s40, events: [], pauseCount: 1, recentFocusMin: [20, 30]))
    XCTAssertEqual(longer.praiseRule, .longerThanWeek)
    XCTAssertTrue(longer.praise.contains("15"), longer.praise)  // 40 − 25 = 15 分
    // 平均より短ければ、次の規則(居眠りなく 30 分以上)
    XCTAssertEqual(card(ResultCardInput(summary: s40, events: [], pauseCount: 1, recentFocusMin: [60])).praiseRule, .stayedAwake)
    // 30 分未満で、スマホに触らなかった
    XCTAssertEqual(card(ResultCardInput(summary: summary(minutes: 10), events: [], pauseCount: 0)).praiseRule, .noTouch)
    // どれでもない
    XCTAssertEqual(card(ResultCardInput(summary: summary(minutes: 10), events: [], pauseCount: 2)).praiseRule, .showedUp)
    // 居眠りがあれば「眠らずに」は言わない
    let sleepy = [AnalysisEvent(type: .sleep, t: 60_000)]
    XCTAssertEqual(card(ResultCardInput(summary: s40, events: sleepy, pauseCount: 1)).praiseRule, .showedUp)
  }

  func testNextStepRulesInOrder() {
    let s = summary(minutes: 20)
    let posture = [AnalysisEvent(type: .postureClose, t: 1000), AnalysisEvent(type: .postureSlouch, t: 2000)]
    XCTAssertEqual(card(ResultCardInput(summary: s, events: [AnalysisEvent(type: .drowsy, t: 1)] + posture, pauseCount: 5)).nextStepRule, .sleepy)
    XCTAssertEqual(card(ResultCardInput(summary: s, events: posture, pauseCount: 5)).nextStepRule, .posture)
    XCTAssertEqual(card(ResultCardInput(summary: s, events: [posture[0]], pauseCount: 3)).nextStepRule, .touchedOften)
    XCTAssertEqual(card(ResultCardInput(summary: s, events: [], pauseCount: 2)).nextStepRule, .keepGoing)
  }

  func testFocusDropMinute() {
    XCTAssertNil(focusDropMinute(Array(repeating: 80, count: 14)), "15 分に満たなければ判断しない")
    XCTAssertNil(focusDropMinute(Array(repeating: 80, count: 40)))
    // 最初の 10 分は 80、22 分目から 40 に下がる → 直近 5 分の平均が 56 を下回るのは 20 分目からの窓
    let scores: [Int?] = Array(repeating: 80, count: 22) + Array(repeating: 40, count: 18)
    XCTAssertEqual(focusDropMinute(scores), 20)
    // 評価できなかった分(nil)は飛ばす
    XCTAssertEqual(focusDropMinute([nil] + scores), 20)
    // 集中度が下がった日は、その分数で休憩をすすめる
    var rec = SessionRecorder(startT: 0, cfg: AnalysisConfig())
    for m in 0..<40 {
      let kind: TimeKind = m < 22 ? .think : .lookaway
      for sec in 0..<60 { rec.add(t: Double(m * 60 + sec) * 1000 + 1, dtSec: 1, kind: kind) }
    }
    let c = card(ResultCardInput(summary: rec.summary(), events: [], pauseCount: 0))
    XCTAssertEqual(c.nextStepRule, .focusDropped)
    // 22 分目から 0 になる → 19 分目からの 5 分の平均が 7 割を下回る → 5 分単位に切り下げて 15 分
    XCTAssertTrue(c.nextStep.contains("15"), c.nextStep)
  }

  func testVariantsAvoidPreviousAndFillPlaceholders() {
    let s = summary(minutes: 40)
    for seed in 1...50 {
      let first = card(ResultCardInput(summary: s, events: [], pauseCount: 0, recentFocusMin: [10]), seed: UInt64(seed))
      let second = card(
        ResultCardInput(
          summary: s, events: [], pauseCount: 0, recentFocusMin: [10], previousPraise: first.praise, previousNextStep: first.nextStep),
        seed: UInt64(seed))
      XCTAssertNotEqual(first.praise, second.praise)
      XCTAssertNotEqual(first.nextStep, second.nextStep)
      for text in [first.praise, first.nextStep, second.praise, second.nextStep] {
        XCTAssertFalse(text.contains("{"), text)
      }
    }
  }

  func testNoBlamingWords() {
    // 本人の学習について「評価」「監視」という言葉を使わない(設計書 5.4 節)
    let all = ResultCardText.praise.values.flatMap { $0 } + ResultCardText.nextStep.values.flatMap { $0 }
    for text in all {
      XCTAssertFalse(text.contains("評価") || text.contains("監視"), text)
    }
    XCTAssertEqual(Set(ResultCardText.praise.keys), Set(PraiseRule.allCases))
    XCTAssertEqual(Set(ResultCardText.nextStep.keys), Set(NextStepRule.allCases))
    XCTAssertTrue(ResultCardText.praise.values.allSatisfy { $0.count >= 3 })
    XCTAssertTrue(ResultCardText.nextStep.values.allSatisfy { $0.count >= 3 })
  }
}
