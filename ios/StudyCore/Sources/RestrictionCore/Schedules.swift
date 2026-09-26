import Foundation

// スマホ制限の時間割・1 日の時間制限・開く回数の制限(Opal の Schedules・App Limits・Open Limits にあたる)

/// 時間割。決めた曜日の決めた時刻に、選んだアプリを制限する。日付をまたいでもよい(22:00〜7:00 など)
public struct WeeklySchedule: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  /// 曜日(1=日曜 … 7=土曜。Calendar の weekday と同じ)。日付をまたぐときは、始まる日の曜日
  public var weekdays: Set<Int>
  /// 始まりと終わり(0 時からの分)。終わりが始まり以前なら、次の日の終わりの時刻まで
  public var startMinute: Int
  public var endMinute: Int
  public var difficulty: Difficulty
  public var enabled: Bool

  public init(
    id: String = UUID().uuidString, name: String, weekdays: Set<Int> = Set(1...7), startMinute: Int, endMinute: Int,
    difficulty: Difficulty = .normal, enabled: Bool = true
  ) {
    self.id = id
    self.name = name
    self.weekdays = weekdays
    self.startMinute = startMinute
    self.endMinute = endMinute
    self.difficulty = difficulty
    self.enabled = enabled
  }

  /// 日付をまたぐ
  public var overnight: Bool { endMinute <= startMinute }

  public var durationMinutes: Int { overnight ? endMinute + 1440 - startMinute : endMinute - startMinute }

  /// 決められない時間割のわけ(決められるなら nil)。DeviceActivity は 15 分より短い区間を見張れないので、
  /// 日付をまたぐときは、その日のうちの部分(始まり〜23:59)も 15 分以上にする
  public var problem: String? {
    let minMin = RestrictionRules.minMonitorMinutes
    if weekdays.isEmpty { return "曜日を 1 つ以上選んでね" }
    if !(0..<1440).contains(startMinute) || !(0..<1440).contains(endMinute) { return "時刻が正しくありません" }
    if durationMinutes < minMin { return "\(minMin) 分以上にしてね" }
    if overnight && 1439 - startMinute < minMin { return "日付をまたぐときは、\(clock(1439 - minMin)) までに始めてね" }
    return nil
  }

  public var isValid: Bool { problem == nil }

  /// DeviceActivity で毎日見張る区間(0 時からの分)。日付をまたぐときは 2 つに分ける(その日の終わりまでと、次の日の 0 時から)。
  /// 曜日は、区間が始まったときに window(containing:) で調べる
  public var dailyIntervals: [(start: Int, end: Int)] {
    guard overnight else { return [(startMinute, endMinute)] }
    var parts = [(start: startMinute, end: 1439)]
    // 0 時ちょうどに終わるときは、その日の終わりまでで足りる
    if endMinute > 0 { parts.append((0, Swift.max(endMinute, RestrictionRules.minMonitorMinutes))) }
    return parts
  }

  /// now を含む区間(始まりと終わりの時刻)。区間の外なら nil
  public func window(containing now: Date, calendar: Calendar = .current) -> (start: Date, end: Date)? {
    let today = calendar.startOfDay(for: now)
    // 今日始まる区間と、昨日始まる区間(日付をまたぐとき)を調べる
    for offset in [0, -1] {
      guard let day = calendar.date(byAdding: .day, value: offset, to: today),
        weekdays.contains(calendar.component(.weekday, from: day)),
        let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0, of: day),
        let endDay = calendar.date(byAdding: .day, value: overnight ? 1 : 0, to: day),
        let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0, of: endDay)
      else { continue }
      if now >= start && now < end { return (start, end) }
    }
    return nil
  }

  public func isActive(at now: Date, calendar: Calendar = .current) -> Bool {
    window(containing: now, calendar: calendar) != nil
  }

  /// 「月〜金 22:00〜7:00」のような表し方
  public var summary: String {
    "\(Weekdays.label(weekdays)) \(clock(startMinute))〜\(clock(endMinute))"
  }
}

/// 1 日の時間制限。選んだアプリを合わせて、1 日に決めた分だけ使える。使い切ったら、次の日まで制限する
public struct DailyLimit: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var minutes: Int
  /// 使い切った後に「あと 5 分」を使えるか(ふつう:6 秒待つ、タイムアウト:間をあける、ディープフォーカス:使えない)
  public var difficulty: Difficulty
  public var enabled: Bool

  public static let choices = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180]

  public init(id: String = UUID().uuidString, name: String, minutes: Int, difficulty: Difficulty = .normal, enabled: Bool = true) {
    self.id = id
    self.name = name
    self.minutes = minutes
    self.difficulty = difficulty
    self.enabled = enabled
  }

  public var isValid: Bool { minutes >= 1 && minutes < 1440 }
}

/// 開く回数の制限。選んだアプリを 1 日に決めた回数だけ開ける。1 回開くと、決めた分だけ使える
public struct OpenLimit: Codable, Equatable, Identifiable, Sendable {
  public var id: String
  public var name: String
  public var maxOpens: Int
  /// 1 回に使える分
  public var minutesPerOpen: Int
  public var enabled: Bool

  public static let openChoices = [1, 2, 3, 5, 10]
  public static let minuteChoices = [5, 10, 15, 30]

  public init(id: String = UUID().uuidString, name: String, maxOpens: Int, minutesPerOpen: Int = 5, enabled: Bool = true) {
    self.id = id
    self.name = name
    self.maxOpens = maxOpens
    self.minutesPerOpen = minutesPerOpen
    self.enabled = enabled
  }
}

/// 今日、何回開いたか。日付が変わったら数え直す
public struct OpenCounter: Codable, Equatable, Sendable {
  public var day: String = ""
  public var counts: [String: Int] = [:]

  public init() {}

  public func used(_ id: String, day today: String) -> Int {
    day == today ? counts[id] ?? 0 : 0
  }

  public func remaining(_ limit: OpenLimit, day today: String) -> Int {
    Swift.max(0, limit.maxOpens - used(limit.id, day: today))
  }

  /// 1 回開く。もう開けなければ false
  public mutating func open(_ limit: OpenLimit, day today: String) -> Bool {
    if day != today {
      day = today
      counts = [:]
    }
    guard remaining(limit, day: today) > 0 else { return false }
    counts[limit.id, default: 0] += 1
    return true
  }
}

public enum DayKey {
  /// 暦の日付("2026-09-26")。開く回数は 0 時で数え直す(学習日の 4 時の区切りとは別)
  public static func of(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return "\(c.year ?? 0)-\(pad2(c.month ?? 0))-\(pad2(c.day ?? 0))"
  }

  /// 次の 0 時
  public static func endOfDay(_ date: Date, calendar: Calendar = .current) -> Date {
    let start = calendar.startOfDay(for: date)
    return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
  }
}

public enum Weekdays {
  static let names = ["日", "月", "火", "水", "木", "金", "土"]

  /// 1(日)〜7(土)の曜日の名前
  public static func name(_ weekday: Int) -> String { names[(weekday - 1 + 7) % 7] }

  /// 表示の順(月曜から)
  public static let order = [2, 3, 4, 5, 6, 7, 1]

  public static func label(_ days: Set<Int>) -> String {
    if days.count == 7 { return "毎日" }
    if days == [2, 3, 4, 5, 6] { return "平日" }
    if days == [1, 7] { return "土日" }
    return order.filter(days.contains).map(name).joined(separator: "・")
  }
}

/// 0 時からの分を「7:05」にする
public func clock(_ minute: Int) -> String {
  let m = ((minute % 1440) + 1440) % 1440
  return "\(m / 60):\(pad2(m % 60))"
}

func pad2(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

/// 時刻を「7:05」にする
public func clock(_ date: Date, calendar: Calendar = .current) -> String {
  let c = calendar.dateComponents([.hour, .minute], from: date)
  return clock((c.hour ?? 0) * 60 + (c.minute ?? 0))
}
