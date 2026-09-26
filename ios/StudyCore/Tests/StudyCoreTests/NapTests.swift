import XCTest

@testable import StudyCore

/// 仮眠のすすめ(決定事項 D-23)と、利用者の設定の反映
final class NapTests: XCTestCase {
  func ev(_ type: AnalysisEventType, _ min: Double, _ sec: Double = 0) -> AnalysisEvent {
    AnalysisEvent(type: type, t: (min * 60 + sec) * 1000)
  }

  func testSuggestsAfterThreeEpisodesInTwentyMinutes() {
    var a = NapAdvisor()
    // 1 回目:うとうと → 居眠り → 起きる(1 回と数える)
    XCTAssertFalse(a.observe(ev(.drowsy, 0)))
    XCTAssertFalse(a.observe(ev(.sleep, 0, 10)))
    XCTAssertFalse(a.observe(ev(.wake, 0, 40)))
    XCTAssertEqual(a.episodes, 1)
    // 2 回目
    XCTAssertFalse(a.observe(ev(.drowsy, 6)))
    XCTAssertEqual(a.episodes, 2)
    // 3 回目:居眠りの間は勧めず、起きたところで勧める
    XCTAssertFalse(a.observe(ev(.sleep, 12)))
    XCTAssertEqual(a.episodes, 3)
    XCTAssertTrue(a.observe(ev(.wake, 12, 30)))
    // 1 時間は勧めない
    XCTAssertFalse(a.observe(ev(.drowsy, 14)))
  }

  func testOldEpisodesDropOutOfTheWindow() {
    var a = NapAdvisor()
    _ = a.observe(ev(.drowsy, 0))
    _ = a.observe(ev(.drowsy, 10))
    // 25 分後:最初のうとうとは 20 分の窓から外れる
    XCTAssertFalse(a.observe(ev(.drowsy, 25)))
    XCTAssertEqual(a.episodes, 2)
    XCTAssertTrue(a.observe(ev(.drowsy, 28)))
  }

  func testCloseEventsAreOneEpisode() {
    var a = NapAdvisor()
    for s in stride(from: 0.0, through: 240, by: 60) {
      XCTAssertFalse(a.observe(ev(.drowsy, 0, s)), "1 分おきのうとうとは、続いた 1 回")
    }
    XCTAssertEqual(a.episodes, 1)
    XCTAssertFalse(a.observe(ev(.yawn, 5)), "ほかの出来事は数えない")
  }

  func testAfterNapCountsStartOverAndCooldownEnds() {
    var a = NapAdvisor()
    _ = a.observe(ev(.drowsy, 0))
    _ = a.observe(ev(.drowsy, 5))
    XCTAssertTrue(a.observe(ev(.drowsy, 10)))
    a.napTaken()
    XCTAssertEqual(a.episodes, 0)
    _ = a.observe(ev(.drowsy, 55))
    _ = a.observe(ev(.drowsy, 62))
    XCTAssertFalse(a.observe(ev(.drowsy, 68)), "3 回来ていても、前に勧めてから 1 時間たっていない")
    XCTAssertTrue(a.observe(ev(.drowsy, 71)))
  }

  func testTunedConfigClampsToTheSettingRanges() {
    let base = AnalysisConfig()
    XCTAssertEqual(base.tuned(awaySec: 30, closeRatio: 0.3).awaySec, 30)
    XCTAssertEqual(base.tuned(awaySec: 30, closeRatio: 0.3).eyeDeskCloseRatio, 0.3)
    XCTAssertEqual(base.tuned(awaySec: 5, closeRatio: 0.9).awaySec, 10)
    XCTAssertEqual(base.tuned(awaySec: 5, closeRatio: 0.9).eyeDeskCloseRatio, 0.4)
    XCTAssertEqual(base.tuned(awaySec: 120, closeRatio: 0.01).awaySec, 60)
    XCTAssertEqual(base.tuned(awaySec: 120, closeRatio: 0.01).eyeDeskCloseRatio, 0.15)
    // 既定の値は試作品(poc-24)のまま
    XCTAssertEqual(base.tuned(awaySec: 20, closeRatio: 0.25), base)
  }

  func testNapBreakIsRecordedAsNap() {
    var s = StudySession(breakTimer: BreakTimer(enabled: false))
    _ = s.beginRitual(at: 0)
    var t = 0.0
    while s.phase != .studying && t < 30_000 {
      t += 200
      var f = Features(t: t)
      f.faceVisible = true
      f.present = true
      f.ear = s.phase == .ritual(.closeEyes) ? 0.1 : 0.3
      f.blink = s.phase == .ritual(.closeEyes) ? 0.9 : 0.1
      f.yawDeg = 0
      f.pitchDeg = 0
      f.rollDeg = 0
      f.faceBox = Box(minX: 0.4, maxX: 0.6, minY: 0.2, maxY: 0.5)
      f.chin = Point2(x: 0.5, y: 0.5)
      f.eyeMid = Point2(x: 0.5, y: 0.35)
      f.faceWidthNorm = 0.2
      _ = s.process(f)
    }
    XCTAssertEqual(s.phase, .studying)
    s.pause(at: t + 1000, reason: .touch)
    s.startBreak(at: t + 2000, minutes: NapAdvisor.napMinutes, nap: true)
    XCTAssertTrue(s.breakIsNap)
    XCTAssertEqual(s.currentBreakMin, 20)
    XCTAssertEqual(s.napCount, 1)
    XCTAssertEqual(s.tick(at: t + 2000 + 19 * 60_000), [])
    XCTAssertEqual(s.tick(at: t + 2000 + 20 * 60_000), [.breakOver])
    _ = s.endBreak(at: t + 2000 + 21 * 60_000)
    XCTAssertFalse(s.breakIsNap)
    XCTAssertEqual(s.intervals.last?.kind, .nap)
    XCTAssertEqual(s.breakSec, 21 * 60, accuracy: 1e-6)
  }
}
