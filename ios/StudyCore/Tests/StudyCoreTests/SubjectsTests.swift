import XCTest

@testable import StudyCore

/// 学習項目の並べ方と、時間の内訳
final class SubjectsTests: XCTestCase {
  func testRankedPutsLastThenMostUsedThenCustomThenSuggestions() {
    let history = ["英語", "数学", "数学", "物理", "数学", "英語"]  // 新しい順
    let ranked = Subjects.ranked(history: history, custom: ["物理", "漢字"])
    XCTAssertEqual(Array(ranked.prefix(4)), ["英語", "数学", "物理", "漢字"], "前回 → よく使う順 → 自分で足したもの")
    XCTAssertEqual(ranked.count, 10, "前回・よく使う・自分で足した 4 つと、残りの候補 6 つ")
    XCTAssertEqual(Set(ranked).count, ranked.count, "同じ名前は 1 回だけ")
    XCTAssertTrue(ranked.contains("国語"))
  }

  func testRankedWithoutHistoryStartsWithSuggestions() {
    XCTAssertEqual(Subjects.ranked(history: [], custom: []), Subjects.suggestions)
    XCTAssertEqual(Subjects.ranked(history: [], custom: [], limit: 3), ["数学", "英語", "国語"])
  }

  func testSameCountPrefersRecent() {
    // 回数が同じ(2 回ずつ)なら、最近使った方を先に
    let ranked = Subjects.ranked(history: ["国語", "理科", "社会", "理科", "社会"], custom: [])
    XCTAssertEqual(Array(ranked.prefix(3)), ["国語", "理科", "社会"])
  }

  func testNormalize() {
    XCTAssertEqual(Subjects.normalize("  数学 "), "数学")
    XCTAssertNil(Subjects.normalize("   "))
    XCTAssertEqual(Subjects.normalize(String(repeating: "あ", count: 30))?.count, Subjects.maxLength)
    XCTAssertEqual(Subjects.normalize("世界史\n近代"), "世界史 近代")
    XCTAssertFalse(Subjects.isCustom("数学"))
    XCTAssertTrue(Subjects.isCustom("物理"))
  }

  func testTimeBreakdown() {
    let s = SessionSummary(
      totals: MinuteSecs(), studySec: 1800, awaySec: 120, pausedSec: 60, avgFocus: 70, effectiveFocusMin: 21, scores: [], counts: [:],
      style: learningStyle(workSec: 0, thinkSec: 0, minuteScores: []))
    let slices = timeBreakdown(s, breakSec: 300)
    XCTAssertEqual(slices.map(\.kind), TimeSlice.Kind.allCases)
    XCTAssertEqual(slices.map(\.sec), [1260, 540, 120, 60, 300])
    // 集中の時間が学習時間を超えることはない
    var over = s
    over.effectiveFocusMin = 40
    XCTAssertEqual(timeBreakdown(over, breakSec: 0)[0].sec, 1800)
    XCTAssertEqual(timeBreakdown(over, breakSec: 0)[1].sec, 0)
  }
}
