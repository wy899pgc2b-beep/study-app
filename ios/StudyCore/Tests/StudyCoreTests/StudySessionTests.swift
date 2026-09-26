import Foundation
import XCTest

@testable import StudyCore

/// 1 回の学習の流れ(開始の儀式・一時停止・休憩・終了)を確かめる
final class StudySessionTests: XCTestCase {
  /// 正面を向いて教材を見ている顔(ear・blink で目の開き具合を変える)
  func face(_ t: Double, ear: Double = 0.3, blink: Double = 0.1) -> Features {
    var f = Features(t: t)
    f.faceVisible = true
    f.present = true
    f.ear = ear
    f.blink = blink
    f.yawDeg = 0
    f.pitchDeg = 0
    f.rollDeg = 0
    f.eyeMid = Point2(x: 0.5, y: 0.35)
    f.faceBox = Box(minX: 0.4, maxX: 0.6, minY: 0.2, maxY: 0.5)
    f.chin = Point2(x: 0.5, y: 0.5)
    f.faceWidthNorm = 0.2
    f.faceHeightNorm = 0.3
    return f
  }

  /// 横向きの位置合わせに合う顔(ペンを持った手が映り、傾きは 15°)
  func guideFace(_ t: Double) -> Features {
    var f = face(t)
    f.cameraTiltDeg = 15
    let hand = HandFeatures(pts: Array(repeating: Landmark(x: 0.5, y: 0.8), count: 21), centroid: Point2(x: 0.5, y: 0.8))
    f.hands = [hand]
    return f
  }

  /// 儀式を最後まで行い、計測を始めた時刻を返す。儀式の間の合図を cues に集める
  func runRitual(_ s: inout StudySession, from t0: Double, cues: inout [SessionCue]) -> Double {
    cues += s.beginRitual(at: t0)
    var t = t0
    while s.phase != .studying {
      t += 200
      let closing = s.phase == .ritual(.closeEyes)
      cues += s.process(closing ? face(t, ear: 0.1, blink: 0.9) : face(t))
      XCTAssertLessThan(t - t0, 30_000, "儀式が終わらない")
      if t - t0 >= 30_000 { break }
    }
    return t
  }

  func testRitualOrderAndCalibration() {
    var s = StudySession()
    var cues: [SessionCue] = []
    let start = runRitual(&s, from: 0, cues: &cues)
    XCTAssertEqual(cues, [.ritual(.closeEyes), .ritual(.openEyes), .ritual(.posture), .started])
    // 目を閉じる約 6 秒(案内 3 秒 + 記録 3 秒)、目を開けた直後の 1 秒、姿勢の 3 秒
    XCTAssertEqual(start, 10_000, accuracy: 400)
    let cal = s.calibration
    XCTAssertNotNil(cal?.closedRef, "目を閉じたときの基準が取れる")
    XCTAssertEqual(cal?.ear ?? 0, 0.3, accuracy: 1e-9, "姿勢の記録は目を開けた値だけを使う")
    XCTAssertEqual(s.startT, start)
  }

  func testRitualFailsWithoutFace() {
    var s = StudySession()
    var cues = s.beginRitual(at: 0)
    var t = 0.0
    while t < 12_000 {
      t += 200
      cues += s.process(Features(t: t))
    }
    XCTAssertTrue(cues.contains(.ritualFailed))
    XCTAssertTrue(cues.contains(.guideStarted(.landscape)))
    XCTAssertEqual(s.phase, .guide, "位置合わせからやり直す")
    XCTAssertNil(s.recorder)
  }

  func testMissingClosedReferenceIsReported() {
    var s = StudySession()
    var cues = s.beginRitual(at: 0)
    var t = 0.0
    while s.phase != .studying && t < 30_000 {
      t += 200
      cues += s.process(face(t))  // 目を閉じてくれなかった
    }
    XCTAssertEqual(cues.suffix(2), [.closedReferenceMissing, .started])
    XCTAssertNil(s.calibration?.closedRef)
  }

  func testPauseIsNotCountedAsStudy() {
    var s = StudySession()
    var cues: [SessionCue] = []
    var t = runRitual(&s, from: 0, cues: &cues)
    for _ in 0..<50 {  // 10 秒学習
      t += 200
      _ = s.process(face(t))
    }
    s.pause(at: t, reason: .touch)
    XCTAssertEqual(s.phase, .paused(.touch))
    for _ in 0..<25 {  // 5 秒一時停止
      t += 200
      _ = s.process(face(t))
    }
    s.resume(at: t)
    for _ in 0..<25 {  // 5 秒学習
      t += 200
      _ = s.process(face(t))
    }
    let summary = s.finish(at: t)
    XCTAssertEqual(s.phase, .finished)
    XCTAssertEqual(summary?.pausedSec ?? 0, 5, accuracy: 0.01)
    XCTAssertEqual(summary?.studySec ?? 0, 15, accuracy: 0.01)
    XCTAssertEqual(summary?.totals.think ?? 0, 15, accuracy: 0.01)
  }

  func testBreakTimer() {
    var s = StudySession(breakTimer: BreakTimer(enabled: true, studyMin: 1, breakMin: 1))
    var cues: [SessionCue] = []
    var t = runRitual(&s, from: 0, cues: &cues)
    var due = false
    while !due && t < 200_000 {
      t += 200
      due = s.process(face(t)).contains(.breakDue)
    }
    XCTAssertTrue(due)
    XCTAssertEqual(s.phase, .onBreak)
    XCTAssertEqual(s.tick(at: t + 30_000), [], "休憩の途中")
    XCTAssertEqual(s.tick(at: t + 60_000), [.breakOver])
    XCTAssertEqual(s.tick(at: t + 61_000), [], "知らせるのは 1 回だけ")
    XCTAssertEqual(s.endBreak(at: t + 70_000), [.guideStarted(.landscape)], "位置を確かめてから戻る")
    XCTAssertEqual(s.phase, .guide)
    XCTAssertEqual(s.breakSec, 70, accuracy: 0.01)
    // 位置が合ったら、姿勢だけを記録して学習に戻る(目を閉じる段階は行わない)
    t += 70_000
    var back: [SessionCue] = []
    while s.phase != .studying {
      t += 200
      back += s.process(guideFace(t), deviceLandscape: true)
      XCTAssertLessThan(t, 400_000)
      if t > 400_000 { break }
    }
    XCTAssertEqual(back, [.guideReady, .ritual(.posture), .resumed])
    XCTAssertNotNil(s.calibration?.closedRef, "目を閉じたときの基準は前の値を使う")
    let summary = s.finish(at: t)
    XCTAssertEqual(summary?.studySec ?? 0, 60, accuracy: 0.5, "休憩と位置の確認は学習時間に入れない")
  }

  func testBreakFromPauseUsesGivenMinutes() {
    var s = StudySession(breakTimer: BreakTimer(enabled: false))
    var cues: [SessionCue] = []
    let t = runRitual(&s, from: 0, cues: &cues)
    s.pause(at: t + 1000, reason: .touch)
    s.startBreak(at: t + 2000, minutes: 5)
    XCTAssertEqual(s.phase, .onBreak)
    XCTAssertEqual(s.currentBreakMin, 5)
    XCTAssertEqual(s.tick(at: t + 2000 + 4 * 60_000), [])
    XCTAssertEqual(s.tick(at: t + 2000 + 5 * 60_000), [.breakOver])
  }

  func testPauseCount() {
    var s = StudySession()
    var cues: [SessionCue] = []
    var t = runRitual(&s, from: 0, cues: &cues)
    for _ in 0..<3 {
      t += 200
      _ = s.process(face(t))
      s.pause(at: t, reason: .touch)
      s.pause(at: t, reason: .touch)  // 一時停止中にもう一度触れても数えない
      s.resume(at: t)
    }
    XCTAssertEqual(s.pauseCount, 3)
  }

  func testGuideLeadsToRitual() {
    var s = StudySession()
    XCTAssertEqual(s.phase, .guide, "始めると位置合わせから")
    XCTAssertEqual(s.beginGuide(at: 0), [.guideStarted(.landscape)])
    var cues: [SessionCue] = []
    var t = 0.0
    while s.phase == .guide && t < 10_000 {
      t += 200
      cues += s.process(guideFace(t), deviceLandscape: true)
    }
    XCTAssertEqual(cues, [.guideReady, .ritual(.closeEyes)])
    XCTAssertEqual(t, 3200, accuracy: 1, "3 秒そろったら進む")
    let required = s.guideChecks.filter { !$0.label.hasPrefix("(任意)") }
    XCTAssertFalse(required.isEmpty)
    XCTAssertTrue(required.allSatisfy(\.ok), "\(required)")
  }

  func testFinishBeforeStartReturnsNil() {
    var s = StudySession()
    _ = s.beginRitual(at: 0)
    XCTAssertNil(s.finish(at: 1000))
    XCTAssertEqual(s.phase, .finished)
  }

  func testBreakTimerPresetsMatchDesign() {
    // 決定事項 D-9:25 分 + 5 分と 50 分 + 10 分は 1 タップ
    XCTAssertEqual(BreakTimer.presets.map(\.studyMin), [25, 50])
    XCTAssertEqual(BreakTimer.presets.map(\.breakMin), [5, 10])
    XCTAssertFalse(BreakTimer().enabled, "初めはオフ")
  }
}
