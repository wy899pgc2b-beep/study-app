import Foundation

// 端末に保存する記録(設計書 6.2 の STUDY_SESSION・MINUTE_SCORE・STATE_INTERVAL・BEHAVIOR_EVENT と、F-27 の利用状況)。
// 保存のしかた(SQLite)はアプリの側に置き、ここでは記録の形と、学習日・合計の計算だけを持つ。
// 映像・画像・特徴点は含めない。

public enum EndReason: String, Codable, Sendable {
  /// 本人が終了した
  case manual
  /// アプリが強制終了された(次の起動で、それまでの 1 分ごとの記録から締める)
  case appKilled = "app_killed"
}

public enum SelfRating: String, Codable, Sendable, CaseIterable {
  case good, normal, poor
}

/// 1 回の学習(STUDY_SESSION)
public struct SessionRecord: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  /// 学習日(04:00 区切り。"yyyy-MM-dd")
  public var studyDate: String
  public var startedAt: Date
  public var endedAt: Date?
  public var setup: SetupStyle
  /// none / 25_5 / 50_10 / custom(休憩タイマー)
  public var timerPreset: String
  public var studySec: Double = 0
  public var awaySec: Double = 0
  public var pausedSec: Double = 0
  public var breakSec: Double = 0
  public var avgFocus: Int?
  public var effectiveFocusMin: Double = 0
  public var styleHands: String?
  public var stylePattern: String?
  /// 画面に触れた・アプリを離れた回数
  public var deviceUseCount: Int = 0
  public var selfRating: SelfRating?
  public var endReason: EndReason?
  /// 結果カードの文(次に同じ文を続けないため、ホームに「今日の一手」を出すため)
  public var praise: String?
  public var nextStep: String?
  /// 学習項目(数学、英単語など)。選んでいなければ nil
  public var subject: String?

  public init(id: UUID = UUID(), studyDate: String, startedAt: Date, setup: SetupStyle, timerPreset: String, subject: String? = nil) {
    self.id = id
    self.studyDate = studyDate
    self.startedAt = startedAt
    self.setup = setup
    self.timerPreset = timerPreset
    self.subject = subject
  }
}

/// 1 分ごとの記録(MINUTE_SCORE)。状態ごとの秒数を持つ(割合はここから求められる)
public struct MinuteRow: Codable, Equatable, Sendable {
  public var sessionId: UUID
  public var minuteIndex: Int
  public var focusPct: Int?
  public var secs: MinuteSecs
  public var habitCount: Int
  public var interruptionCount: Int

  public init(sessionId: UUID, minute: MinuteRecord, focusPct: Int?) {
    self.sessionId = sessionId
    self.minuteIndex = minute.index
    self.focusPct = focusPct
    self.secs = minute.secs
    self.habitCount = minute.habits
    self.interruptionCount = minute.interruptions
  }

  public var minute: MinuteRecord {
    MinuteRecord(index: minuteIndex, secs: secs, habits: habitCount, interruptions: interruptionCount)
  }
}

/// 出来事(BEHAVIOR_EVENT。居眠り・姿勢・離席など)
public struct EventRow: Codable, Equatable, Sendable {
  public var sessionId: UUID
  public var type: AnalysisEventType
  public var at: Date

  public init(sessionId: UUID, type: AnalysisEventType, at: Date) {
    self.sessionId = sessionId
    self.type = type
    self.at = at
  }
}

/// 状態の区間(STATE_INTERVAL。一時停止・休憩)
public struct IntervalRow: Codable, Equatable, Sendable {
  public enum Kind: String, Codable, Sendable {
    case pausedTouch = "paused_touch"
    case pausedApp = "paused_app"
    case breakTime = "break"
  }

  public var sessionId: UUID
  public var kind: Kind
  public var startedAt: Date
  public var endedAt: Date

  public init(sessionId: UUID, kind: Kind, startedAt: Date, endedAt: Date) {
    self.sessionId = sessionId
    self.kind = kind
    self.startedAt = startedAt
    self.endedAt = endedAt
  }
}

/// 利用状況のイベント(F-27。設計書 3.27 の名前。時刻・回数・時間・スコアだけで、映像や顔のデータは含めない)
public struct UsageEvent: Codable, Equatable, Sendable {
  public var name: String
  public var at: Date
  public var properties: [String: String]

  public init(name: String, at: Date, properties: [String: String] = [:]) {
    self.name = name
    self.at = at
    self.properties = properties
  }
}

/// 端末に保存した記録の書き出し(設定の「記録を書き出す」)。α 版の協力者が 1 週間ごとに送る(MVP の設計 7 章)。
/// 時刻・時間・回数・スコアだけで、映像・画像・特徴点は含めない
public struct RecordsExport: Encodable, Sendable {
  public var version = 1
  public var app = "ツクエログ"
  public var appVersion: String
  public var exportedAt: Date
  /// 学年(オンボーディングで選んだもの。選んでいなければ nil)
  public var grade: String?
  public var sessions: [SessionRecord]
  public var minutes: [MinuteRow]
  public var events: [EventRow]
  public var intervals: [IntervalRow]
  public var usage: [UsageEvent]

  public init(
    appVersion: String, exportedAt: Date, grade: String?, sessions: [SessionRecord], minutes: [MinuteRow], events: [EventRow],
    intervals: [IntervalRow], usage: [UsageEvent]
  ) {
    self.appVersion = appVersion
    self.exportedAt = exportedAt
    self.grade = grade
    self.sessions = sessions
    self.minutes = minutes
    self.events = events
    self.intervals = intervals
    self.usage = usage
  }

  /// 読みやすい JSON
  public func json() throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    enc.dateEncodingStrategy = .iso8601
    enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
    return try enc.encode(self)
  }
}

// MARK: - 学習日と合計

public enum StudyDay {
  /// 学習日の区切り(04:00。夜中の学習は前の日に数える。設計書 3.15)
  public static let boundaryHour = 4

  public static func studyDate(_ date: Date, calendar: Calendar = .current) -> String {
    let shifted = date.addingTimeInterval(-Double(boundaryHour) * 3600)
    let c = calendar.dateComponents([.year, .month, .day], from: shifted)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// date の学習日から数えて、過去 n 日の学習日(古い順。最後が date の学習日)
  public static func recentDates(_ n: Int, until date: Date, calendar: Calendar = .current) -> [String] {
    (0..<n).reversed().map { back in
      studyDate(date.addingTimeInterval(-Double(back) * 86_400), calendar: calendar)
    }
  }
}

/// 1 日分の合計
public struct DayTotal: Equatable, Sendable {
  public var studyDate: String
  public var focusMin: Double
  public var studySec: Double
}

/// 学習日ごとの合計(dates の順)。記録のない日は 0
public func dayTotals(_ sessions: [SessionRecord], dates: [String]) -> [DayTotal] {
  dates.map { d in
    let s = sessions.filter { $0.studyDate == d }
    return DayTotal(studyDate: d, focusMin: s.reduce(0) { $0 + $1.effectiveFocusMin }, studySec: s.reduce(0) { $0 + $1.studySec })
  }
}

/// 結果カードの「この 1 週間の平均」に使う、過去 7 日の学習ごとの集中時間(今回の学習を除く)
public func recentFocusMin(_ sessions: [SessionRecord], excluding id: UUID, now: Date, calendar: Calendar = .current) -> [Double] {
  let dates = Set(StudyDay.recentDates(7, until: now, calendar: calendar))
  return sessions.filter { $0.id != id && dates.contains($0.studyDate) && $0.endedAt != nil && $0.studySec > 0 }.map(\.effectiveFocusMin)
}

extension SessionRecord {
  /// 学習の集計を書き込む(終了時)
  public mutating func apply(_ summary: SessionSummary, breakSec: Double, deviceUseCount: Int) {
    studySec = summary.studySec
    awaySec = summary.awaySec
    pausedSec = summary.pausedSec
    self.breakSec = breakSec
    avgFocus = summary.avgFocus
    effectiveFocusMin = summary.effectiveFocusMin
    styleHands = summary.style.hands?.rawValue
    stylePattern = summary.style.pattern?.rawValue
    self.deviceUseCount = deviceUseCount
  }

  /// 強制終了された学習を、保存してあった 1 分ごとの記録から締める(MVP の完了の条件 7)
  public mutating func recover(from minutes: [MinuteRow], cfg: AnalysisConfig = AnalysisConfig(), autoAway: Bool = true) {
    var rec = SessionRecorder(startT: 0, cfg: cfg, autoAway: autoAway)
    for m in minutes.sorted(by: { $0.minuteIndex < $1.minuteIndex }) {
      rec.restore(m.minute)
    }
    let summary = rec.summary()
    apply(summary, breakSec: breakSec, deviceUseCount: deviceUseCount)
    let lastMinute = minutes.map(\.minuteIndex).max() ?? -1
    endedAt = startedAt.addingTimeInterval(Double(lastMinute + 1) * 60)
    endReason = .appKilled
  }
}

extension SessionRecorder {
  /// 保存してあった 1 分の記録を戻す(強制終了からの回復)
  public mutating func restore(_ minute: MinuteRecord) {
    let t = startT + Double(minute.index) * 60_000
    for kind in TimeKind.allCases where minute.secs[kind] > 0 {
      add(t: t, dtSec: minute.secs[kind], kind: kind)
    }
    for _ in 0..<minute.habits { addEvent(AnalysisEvent(type: .habitFace, t: t)) }
    for _ in 0..<minute.interruptions { addEvent(AnalysisEvent(type: .lookaway, t: t)) }
  }
}
