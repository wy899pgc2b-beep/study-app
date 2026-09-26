import Foundation

// Opal のよいところを再現する(決定事項 D-25):
// 気になったときに、プリセットをワンタップするだけで集中セッションを始められる(ホーム・ショートカット・Siri)。
// 時間割は、ひな形を選ぶだけで作れ、一度決めたら毎日そのまま動く。

/// 集中セッションのプリセット(長さと厳しさ)。制限するアプリは「制限するアプリ」を使う
public struct FocusPreset: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var minutes: Int
  public var difficulty: Difficulty

  public init(id: String = UUID().uuidString, minutes: Int, difficulty: Difficulty = .normal) {
    self.id = id
    self.minutes = minutes
    self.difficulty = difficulty
  }

  /// 「1時間半」
  public var label: String { durationLabel(minutes) }

  /// プリセットにできる長さ(分)
  public static let choices = [15, 25, 30, 45, 60, 90, 120, 150, 180, 240]
  public static let maxCount = 4
  /// はじめのプリセット。ホームのワンタップは 1時間半
  public static let defaults = [
    FocusPreset(id: "preset.25", minutes: 25),
    FocusPreset(id: "preset.60", minutes: 60),
    FocusPreset(id: "preset.90", minutes: 90),
  ]
  public static let defaultHomeID = "preset.90"
}

/// 分を「25分」「1時間」「1時間半」「1時間40分」にする
public func durationLabel(_ minutes: Int) -> String {
  let h = minutes / 60
  let m = minutes % 60
  if h == 0 { return "\(m)分" }
  if m == 0 { return "\(h)時間" }
  if m == 30 { return "\(h)時間半" }
  return "\(h)時間\(m)分"
}

/// 時間割のひな形(選んだあと、曜日と時刻は変えられる)
public struct ScheduleTemplate: Equatable, Sendable {
  public var name: String
  public var weekdays: Set<Int>
  public var startMinute: Int
  public var endMinute: Int

  public func make(difficulty: Difficulty = .normal) -> WeeklySchedule {
    WeeklySchedule(name: name, weekdays: weekdays, startMinute: startMinute, endMinute: endMinute, difficulty: difficulty)
  }

  public var summary: String { make().summary }

  static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]

  public static let all = [
    ScheduleTemplate(name: "朝の勉強", weekdays: weekdaysOnly, startMinute: 6 * 60, endMinute: 7 * 60 + 30),
    ScheduleTemplate(name: "学校の間", weekdays: weekdaysOnly, startMinute: 8 * 60 + 30, endMinute: 15 * 60 + 30),
    ScheduleTemplate(name: "夜の勉強", weekdays: Set(1...7), startMinute: 19 * 60, endMinute: 22 * 60),
    ScheduleTemplate(name: "寝る前", weekdays: Set(1...7), startMinute: 22 * 60 + 30, endMinute: 6 * 60 + 30),
  ]
}
