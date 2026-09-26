import XCTest

@testable import RestrictionCore

/// スマホ制限の決まり(決定事項 D-24、設計書 3.30)
final class RestrictionCoreTests: XCTestCase {
  var cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Tokyo")!
    return c
  }()

  /// 2026-09-28 は月曜日
  func at(_ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour, minute: minute, second: second))!
  }

  func session(_ d: Difficulty, kind: SessionKind = .manual, minutes: Double = 60) -> ActiveSession {
    ActiveSession(key: "session", kind: kind, difficulty: d, startAt: at(28, 10, 0), endAt: at(28, 10, 0).addingTimeInterval(minutes * 60))
  }

  // MARK: 厳しさ

  func testNormalNeedsASecondPressAfterSixSeconds() {
    var s = session(.normal)
    let t = at(28, 10, 10)
    XCTAssertEqual(s.requestBreak(now: t), .confirmAgain(afterSec: 6))
    XCTAssertTrue(s.breakPending(at: t.addingTimeInterval(2)))
    XCTAssertEqual(s.requestBreak(now: t.addingTimeInterval(2)), .confirmAgain(afterSec: 4), "6 秒たつ前に押しても休憩にならない")
    XCTAssertEqual(s.requestBreak(now: t.addingTimeInterval(7)), .allowed(until: t.addingTimeInterval(7 + 300)))
    XCTAssertTrue(s.onBreak(at: t.addingTimeInterval(60)))
    XCTAssertEqual(s.requestBreak(now: t.addingTimeInterval(60)), .alreadyOnBreak(until: t.addingTimeInterval(307)))
    XCTAssertFalse(s.onBreak(at: t.addingTimeInterval(307)))
    XCTAssertEqual(s.breaksTaken, 1)
  }

  func testNormalFirstPressIsForgottenAfterAMinute() {
    var s = session(.normal)
    let t = at(28, 10, 10)
    _ = s.requestBreak(now: t)
    XCTAssertFalse(s.breakPending(at: t.addingTimeInterval(61)))
    XCTAssertEqual(s.requestBreak(now: t.addingTimeInterval(61)), .confirmAgain(afterSec: 6), "1 分たったら 1 回目からやり直す")
  }

  func testNormalEndAlsoNeedsTwoPresses() {
    var s = session(.normal)
    let t = at(28, 10, 10)
    XCTAssertEqual(s.requestEnd(now: t), .confirmAgain(afterSec: 6))
    XCTAssertEqual(s.requestEnd(now: t.addingTimeInterval(6)), .allowed)
    var over = session(.normal)
    XCTAssertEqual(over.requestEnd(now: at(28, 11, 0)), .allowed, "時間になったら、すぐ終われる")
  }

  func testStudyBreakSkipsTheConfirmation() {
    var s = session(.normal, kind: .study)
    let t = at(28, 10, 10)
    XCTAssertEqual(s.requestBreak(now: t, minutes: 10, confirm: false), .allowed(until: t.addingTimeInterval(600)))
  }

  func testTimeoutWaitGrowsFifteenThirtySixty() {
    XCTAssertEqual((1...5).map(RestrictionRules.timeoutWait(afterBreak:)), [15, 30, 60, 60, 60])
    var s = session(.timeout, minutes: 240)
    var t = at(28, 10, 10)
    XCTAssertTrue(s.canBreak(at: t))
    XCTAssertEqual(s.requestBreak(now: t), .allowed(until: t.addingTimeInterval(300)), "確かめなしで休憩できる")
    s.breakEnded()
    XCTAssertEqual(s.requestBreak(now: t.addingTimeInterval(10 * 60)), .notUntil(t.addingTimeInterval(15 * 60)))
    XCTAssertEqual(s.requestEnd(now: t.addingTimeInterval(10 * 60)), .notUntil(t.addingTimeInterval(15 * 60)), "次の休憩までは終われない")
    t = t.addingTimeInterval(15 * 60)
    XCTAssertEqual(s.requestBreak(now: t), .allowed(until: t.addingTimeInterval(300)))
    s.breakEnded()
    XCTAssertEqual(s.nextBreakAllowedAt, t.addingTimeInterval(30 * 60))
    t = t.addingTimeInterval(30 * 60)
    _ = s.requestBreak(now: t)
    XCTAssertEqual(s.nextBreakAllowedAt, t.addingTimeInterval(60 * 60))
    XCTAssertEqual(s.requestEnd(now: t.addingTimeInterval(60 * 60)), .allowed)
  }

  func testDeepAllowsNeitherBreakNorEndUntilTheTime() {
    var s = session(.deep)
    XCTAssertFalse(s.canBreak(at: at(28, 10, 30)))
    XCTAssertEqual(s.requestBreak(now: at(28, 10, 30)), .notAllowed)
    XCTAssertEqual(s.requestEnd(now: at(28, 10, 59)), .notAllowed)
    XCTAssertEqual(s.requestEnd(now: at(28, 11, 0)), .allowed)
    XCTAssertEqual(s.remainingSec(at: at(28, 10, 30)), 1800)
  }

  func testCodableKeepsTheBreakState() throws {
    var s = session(.timeout)
    _ = s.requestBreak(now: at(28, 10, 10))
    let back = try JSONDecoder().decode(ActiveSession.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(back, s)
  }

  // MARK: 見張りの区間

  func testShortWindowsStartInThePast() {
    let now = at(28, 10, 0)
    let short = monitorWindow(until: now.addingTimeInterval(5 * 60), now: now)
    XCTAssertEqual(short.end, now.addingTimeInterval(5 * 60))
    XCTAssertEqual(short.end.timeIntervalSince(short.start), 16 * 60, "15 分に 1 分の余裕を足す")
    let long = monitorWindow(until: now.addingTimeInterval(60 * 60), now: now)
    XCTAssertEqual(long.start, now)
  }

  // MARK: 時間割

  func testWeekdaySchedule() {
    let s = WeeklySchedule(name: "学校", weekdays: [2, 3, 4, 5, 6], startMinute: 8 * 60 + 30, endMinute: 15 * 60 + 30)
    XCTAssertTrue(s.isValid)
    XCTAssertEqual(s.summary, "平日 8:30〜15:30")
    XCTAssertEqual(s.dailyIntervals.map(\.start), [510])
    XCTAssertEqual(s.dailyIntervals.map(\.end), [930])
    XCTAssertTrue(s.isActive(at: at(28, 9, 0), calendar: cal), "月曜")
    XCTAssertFalse(s.isActive(at: at(27, 9, 0), calendar: cal), "日曜")
    XCTAssertFalse(s.isActive(at: at(28, 15, 30), calendar: cal), "終わりの時刻は含まない")
    XCTAssertEqual(s.window(containing: at(28, 12, 0), calendar: cal)?.end, at(28, 15, 30))
  }

  func testOvernightScheduleBelongsToTheDayItStarts() {
    // 日曜の夜から月曜の朝まで(日曜だけ選ぶ)
    let s = WeeklySchedule(name: "寝る前", weekdays: [1], startMinute: 22 * 60, endMinute: 7 * 60)
    XCTAssertTrue(s.overnight)
    XCTAssertEqual(s.durationMinutes, 540)
    XCTAssertEqual(s.dailyIntervals.map(\.start), [1320, 0])
    XCTAssertEqual(s.dailyIntervals.map(\.end), [1439, 420])
    XCTAssertTrue(s.isActive(at: at(27, 23, 0), calendar: cal))
    XCTAssertTrue(s.isActive(at: at(28, 6, 59), calendar: cal), "月曜の朝も、日曜に始まった区間の中")
    XCTAssertFalse(s.isActive(at: at(28, 22, 30), calendar: cal), "月曜の夜は選んでいない")
    XCTAssertFalse(s.isActive(at: at(27, 6, 0), calendar: cal), "日曜の朝は、土曜に始まる区間(選んでいない)")
    XCTAssertEqual(s.window(containing: at(28, 1, 0), calendar: cal)?.start, at(27, 22, 0))
  }

  func testScheduleProblems() {
    XCTAssertNotNil(WeeklySchedule(name: "", weekdays: [], startMinute: 0, endMinute: 60).problem)
    XCTAssertNotNil(WeeklySchedule(name: "", startMinute: 600, endMinute: 610).problem, "15 分より短い")
    XCTAssertEqual(WeeklySchedule(name: "", startMinute: 1430, endMinute: 420).problem, "日付をまたぐときは、23:44 までに始めてね")
    XCTAssertNil(WeeklySchedule(name: "", startMinute: 1424, endMinute: 420).problem)
    // 0 時ちょうどに終わるなら、その日の部分だけ見張る。0 時すぎの短い終わりは 15 分に延ばす
    XCTAssertEqual(WeeklySchedule(name: "", startMinute: 1320, endMinute: 0).dailyIntervals.count, 1)
    XCTAssertEqual(WeeklySchedule(name: "", startMinute: 1320, endMinute: 5).dailyIntervals.last?.end, 15)
  }

  func testWeekdayLabels() {
    XCTAssertEqual(Weekdays.label(Set(1...7)), "毎日")
    XCTAssertEqual(Weekdays.label([1, 7]), "土日")
    XCTAssertEqual(Weekdays.label([1, 2, 4]), "月・水・日")
    XCTAssertEqual(clock(7 * 60 + 5), "7:05")
    XCTAssertEqual(clock(at(28, 23, 59), calendar: cal), "23:59")
  }

  // MARK: 開く回数

  func testOpenCounterResetsEachDay() {
    let limit = OpenLimit(name: "SNS", maxOpens: 2)
    var c = OpenCounter()
    let mon = DayKey.of(at(28, 9, 0), calendar: cal)
    XCTAssertEqual(mon, "2026-09-28")
    XCTAssertEqual(c.remaining(limit, day: mon), 2)
    XCTAssertTrue(c.open(limit, day: mon))
    XCTAssertTrue(c.open(limit, day: mon))
    XCTAssertFalse(c.open(limit, day: mon))
    XCTAssertEqual(c.remaining(limit, day: mon), 0)
    let tue = DayKey.of(at(29, 0, 1), calendar: cal)
    XCTAssertEqual(c.remaining(limit, day: tue), 2, "0 時で数え直す")
    XCTAssertTrue(c.open(limit, day: tue))
    XCTAssertEqual(c.used(limit.id, day: tue), 1)
    XCTAssertEqual(DayKey.endOfDay(at(28, 9, 0), calendar: cal), at(29, 0, 0))
  }

  // MARK: プリセットと時間割のひな形(D-25)

  func testPresetsAndDurationLabels() {
    XCTAssertEqual(durationLabel(25), "25分")
    XCTAssertEqual(durationLabel(60), "1時間")
    XCTAssertEqual(durationLabel(90), "1時間半")
    XCTAssertEqual(durationLabel(100), "1時間40分")
    XCTAssertEqual(durationLabel(150), "2時間半")
    let home = FocusPreset.defaults.first { $0.id == FocusPreset.defaultHomeID }
    XCTAssertEqual(home?.label, "1時間半", "ホームのワンタップは 1時間半")
    XCTAssertEqual(home?.difficulty, .normal)
    XCTAssertLessThanOrEqual(FocusPreset.defaults.count, FocusPreset.maxCount)
    XCTAssertTrue(FocusPreset.defaults.allSatisfy { FocusPreset.choices.contains($0.minutes) })
  }

  func testScheduleTemplatesAreValid() {
    for t in ScheduleTemplate.all {
      XCTAssertNil(t.make().problem, t.name)
    }
    XCTAssertEqual(ScheduleTemplate.all.last?.summary, "毎日 22:30〜6:30")
    XCTAssertTrue(ScheduleTemplate.all.last!.make().isActive(at: at(29, 2, 0), calendar: cal), "寝る前は、夜中も続く")
  }

  // MARK: シールドの文言

  func testShieldCopyFollowsTheDifficulty() {
    let now = at(28, 10, 10)
    var normal = session(.normal)
    XCTAssertEqual(ShieldCopyMaker.session(normal, name: nil, now: now, calendar: cal).secondary, "5 分休憩する")
    _ = normal.requestBreak(now: now)
    let pressed = ShieldCopyMaker.session(normal, name: nil, now: now.addingTimeInterval(1), calendar: cal)
    XCTAssertEqual(pressed.subtitle, "5 秒待ってから、もう一度押してね")
    XCTAssertEqual(pressed.secondary, "もう一度押す")

    var timeout = session(.timeout)
    _ = timeout.requestBreak(now: now)
    timeout.breakEnded()
    let waiting = ShieldCopyMaker.session(timeout, name: nil, now: now.addingTimeInterval(600), calendar: cal)
    XCTAssertEqual(waiting.subtitle, "11:00 まで。次は 10:25 からできます")
    XCTAssertNil(waiting.secondary)

    let deep = ShieldCopyMaker.session(session(.deep), name: nil, now: now, calendar: cal)
    XCTAssertNil(deep.secondary)
    XCTAssertEqual(deep.primary, "閉じる")

    let limit = ActiveSession(key: "limit.a", kind: .limit, difficulty: .normal, startAt: now, endAt: at(29, 0, 0))
    let limitCopy = ShieldCopyMaker.session(limit, name: "SNS", now: now, calendar: cal)
    XCTAssertEqual(limitCopy.title, "「SNS」は今日の時間を使い切りました")
    XCTAssertEqual(limitCopy.secondary, "あと 5 分使う")

    let open = OpenLimit(name: "動画", maxOpens: 3, minutesPerOpen: 10)
    XCTAssertEqual(ShieldCopyMaker.open(open, remaining: 2).secondary, "開く(あと 2 回)")
    XCTAssertNil(ShieldCopyMaker.open(open, remaining: 0).secondary)
  }
}
