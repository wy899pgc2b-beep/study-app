import Foundation
import XCTest

@testable import StudyCore

/// 端末に保存する記録の計算(学習日、合計、強制終了からの回復)
final class RecordsTests: XCTestCase {
  var tokyo: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
  }

  func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    tokyo.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
  }

  func session(_ day: String, focus: Double, studySec: Double = 1800, ended: Bool = true) -> SessionRecord {
    var s = SessionRecord(studyDate: day, startedAt: date(2026, 9, 20, 20), setup: .landscape, timerPreset: "none")
    s.effectiveFocusMin = focus
    s.studySec = studySec
    s.endedAt = ended ? s.startedAt.addingTimeInterval(studySec) : nil
    return s
  }

  func testStudyDateChangesAtFourAM() {
    XCTAssertEqual(StudyDay.studyDate(date(2026, 9, 26, 3, 59), calendar: tokyo), "2026-09-25", "夜中の学習は前の日")
    XCTAssertEqual(StudyDay.studyDate(date(2026, 9, 26, 4, 0), calendar: tokyo), "2026-09-26")
    XCTAssertEqual(StudyDay.studyDate(date(2026, 10, 1, 0, 30), calendar: tokyo), "2026-09-30", "月をまたぐ")
    let week = StudyDay.recentDates(7, until: date(2026, 9, 26, 21), calendar: tokyo)
    XCTAssertEqual(week, ["2026-09-20", "2026-09-21", "2026-09-22", "2026-09-23", "2026-09-24", "2026-09-25", "2026-09-26"])
  }

  func testDayTotals() {
    let sessions = [session("2026-09-25", focus: 20), session("2026-09-25", focus: 15), session("2026-09-26", focus: 40)]
    let totals = dayTotals(sessions, dates: ["2026-09-24", "2026-09-25", "2026-09-26"])
    XCTAssertEqual(totals.map(\.focusMin), [0, 35, 40])
    XCTAssertEqual(totals[1].studySec, 3600)
  }

  func testRecentFocusMinForResultCard() {
    let now = date(2026, 9, 26, 21)
    let current = session("2026-09-26", focus: 50)
    let sessions = [
      current,
      session("2026-09-26", focus: 30),
      session("2026-09-20", focus: 10),  // 7 日の中
      session("2026-09-19", focus: 99),  // 8 日前:入れない
      session("2026-09-25", focus: 77, ended: false),  // 終わっていない:入れない
      session("2026-09-24", focus: 0, studySec: 0),  // 計測を始める前に終えた:入れない
    ]
    XCTAssertEqual(recentFocusMin(sessions, excluding: current.id, now: now, calendar: tokyo).sorted(), [10, 30])
  }

  func testRecoverFromMinuteRows() {
    // 3 分学習したところで強制終了された
    var s = session("2026-09-26", focus: 0, studySec: 0, ended: false)
    var rec = SessionRecorder(startT: 0, cfg: AnalysisConfig())
    for sec in 0..<180 { rec.add(t: Double(sec) * 1000 + 1, dtSec: 1, kind: sec < 150 ? .think : .paused) }
    rec.addEvent(AnalysisEvent(type: .lookaway, t: 10_000))
    let rows = rec.minutes.enumerated().map { i, m in MinuteRow(sessionId: s.id, minute: m, focusPct: rec.scores()[i]) }
    s.deviceUseCount = 1
    s.recover(from: rows.reversed())
    XCTAssertEqual(s.endReason, .appKilled)
    XCTAssertEqual(s.endedAt, s.startedAt.addingTimeInterval(180))
    XCTAssertEqual(s.studySec, 150, accuracy: 1e-9)
    XCTAssertEqual(s.pausedSec, 30, accuracy: 1e-9)
    XCTAssertEqual(s.effectiveFocusMin, rec.summary().effectiveFocusMin, accuracy: 1e-9)
    XCTAssertEqual(s.avgFocus, rec.summary().avgFocus)
    XCTAssertEqual(s.deviceUseCount, 1)
  }

  func testRecordsRoundTripAsJSON() throws {
    var s = session("2026-09-26", focus: 12.5)
    s.selfRating = .good
    s.endReason = .manual
    s.praise = "今日も机に向かえたね"
    let back = try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(back, s)
    let row = EventRow(sessionId: s.id, type: .awayStart, at: s.startedAt)
    XCTAssertEqual(try JSONDecoder().decode(EventRow.self, from: JSONEncoder().encode(row)), row)
  }

  func testRecordsExportHasOnlyTheListedTables() throws {
    let s = session("2026-09-26", focus: 12.5)
    let export = RecordsExport(
      appVersion: "0.1.0", exportedAt: Date(timeIntervalSince1970: 0), grade: "high3", sessions: [s], minutes: [],
      events: [EventRow(sessionId: s.id, type: .awayStart, at: s.startedAt)], intervals: [],
      usage: [UsageEvent(name: "session_start", at: s.startedAt, properties: ["timer": "25_5"])])
    let obj = try JSONDecoder().decode(JSONValue.self, from: export.json())
    guard case .object(let o) = obj else { return XCTFail("object") }
    XCTAssertEqual(
      Set(o.keys), ["version", "app", "appVersion", "exportedAt", "grade", "sessions", "minutes", "events", "intervals", "usage"])
    guard case .string(let at) = o["exportedAt"] else { return XCTFail("exportedAt") }
    XCTAssertEqual(at, "1970-01-01T00:00:00Z")
  }

  func testSessionIntervals() {
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
    s.pause(at: t + 1000, reason: .touch)
    s.resume(at: t + 4000)
    s.pause(at: t + 5000, reason: .leftApp)
    s.startBreak(at: t + 6000)
    _ = s.endBreak(at: t + 66_000)
    s.finish(at: t + 70_000)
    XCTAssertEqual(
      s.intervals,
      [
        SessionInterval(kind: .pausedTouch, startT: t + 1000, endT: t + 4000),
        SessionInterval(kind: .pausedApp, startT: t + 5000, endT: t + 6000),
        SessionInterval(kind: .breakTime, startT: t + 6000, endT: t + 66_000),
      ])
  }
}
