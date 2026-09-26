import Foundation
import GRDB
import StudyCore
import os

// 端末の DB(SQLite。GRDB を使う)。学習の記録を 1 分ごとに保存し、アプリが強制終了されても残るようにする(MVP の完了の条件 7)。
// 映像・画像・特徴点は保存しない。

extension SessionRecord: @retroactive FetchableRecord, @retroactive PersistableRecord {
  public static var databaseTableName: String { "session" }
}

extension MinuteRow: @retroactive FetchableRecord, @retroactive PersistableRecord {
  public static var databaseTableName: String { "minute" }
  // 同じ分を保存し直したら置き換える
  public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
}

extension EventRow: @retroactive FetchableRecord, @retroactive PersistableRecord {
  public static var databaseTableName: String { "event" }
}

extension IntervalRow: @retroactive FetchableRecord, @retroactive PersistableRecord {
  public static var databaseTableName: String { "interval" }
}

extension UsageEvent: @retroactive FetchableRecord, @retroactive PersistableRecord {
  public static var databaseTableName: String { "usageEvent" }
}

@MainActor
final class Store {
  private let db: DatabaseQueue
  private let log = Logger(subsystem: "TsukueLog", category: "Store")

  init() throws {
    let dir = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("TsukueLog", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    db = try DatabaseQueue(path: dir.appendingPathComponent("records.sqlite").path)
    try Self.migrator.migrate(db)
  }

  private static var migrator: DatabaseMigrator {
    var m = DatabaseMigrator()
    m.registerMigration("v1") { db in
      try db.create(table: "session") { t in
        t.column("id", .blob).primaryKey()
        t.column("studyDate", .text).notNull().indexed()
        t.column("startedAt", .datetime).notNull()
        t.column("endedAt", .datetime)
        t.column("setup", .text).notNull()
        t.column("timerPreset", .text).notNull()
        t.column("studySec", .double).notNull()
        t.column("awaySec", .double).notNull()
        t.column("pausedSec", .double).notNull()
        t.column("breakSec", .double).notNull()
        t.column("avgFocus", .integer)
        t.column("effectiveFocusMin", .double).notNull()
        t.column("styleHands", .text)
        t.column("stylePattern", .text)
        t.column("deviceUseCount", .integer).notNull()
        t.column("selfRating", .text)
        t.column("endReason", .text)
        t.column("praise", .text)
        t.column("nextStep", .text)
      }
      try db.create(table: "minute") { t in
        t.column("sessionId", .blob).notNull().references("session", onDelete: .cascade)
        t.column("minuteIndex", .integer).notNull()
        t.column("focusPct", .integer)
        t.column("secs", .text).notNull()
        t.column("habitCount", .integer).notNull()
        t.column("interruptionCount", .integer).notNull()
        t.primaryKey(["sessionId", "minuteIndex"])
      }
      try db.create(table: "event") { t in
        t.column("sessionId", .blob).notNull().indexed().references("session", onDelete: .cascade)
        t.column("type", .text).notNull()
        t.column("at", .datetime).notNull()
      }
      try db.create(table: "interval") { t in
        t.column("sessionId", .blob).notNull().indexed().references("session", onDelete: .cascade)
        t.column("kind", .text).notNull()
        t.column("startedAt", .datetime).notNull()
        t.column("endedAt", .datetime).notNull()
      }
      try db.create(table: "usageEvent") { t in
        t.column("name", .text).notNull()
        t.column("at", .datetime).notNull()
        t.column("properties", .text).notNull()
      }
    }
    return m
  }

  // MARK: - 書き込み

  func save(_ session: SessionRecord) {
    write { try session.save($0) }
  }

  func save(minutes: [MinuteRow]) {
    guard !minutes.isEmpty else { return }
    write { db in for m in minutes { try m.insert(db) } }
  }

  func add(events: [EventRow]) {
    guard !events.isEmpty else { return }
    write { db in for e in events { try e.insert(db) } }
  }

  func add(intervals: [IntervalRow]) {
    guard !intervals.isEmpty else { return }
    write { db in for i in intervals { try i.insert(db) } }
  }

  func log(_ event: UsageEvent) {
    write { try event.insert($0) }
  }

  func setSelfRating(_ rating: SelfRating, sessionId: UUID) {
    write { db in
      guard var s = try SessionRecord.fetchOne(db, key: sessionId) else { return }
      s.selfRating = rating
      try s.update(db)
    }
  }

  /// 強制終了されて締められていない学習を、保存してあった 1 分ごとの記録から締める。締めた数を返す
  @discardableResult
  func recoverUnfinished() -> Int {
    var count = 0
    write { db in
      let open = try SessionRecord.filter(Column("endedAt") == nil).fetchAll(db)
      for var s in open {
        let rows = try MinuteRow.filter(Column("sessionId") == s.id).fetchAll(db)
        if rows.isEmpty {
          // 1 分も記録していない学習は残さない
          try s.delete(db)
          continue
        }
        s.recover(from: rows)
        try s.update(db)
        count += 1
      }
    }
    return count
  }

  // MARK: - 読み出し

  /// studyDate 以降の学習日の、終わった学習
  func sessions(since studyDate: String) -> [SessionRecord] {
    read { db in
      try SessionRecord.filter(Column("studyDate") >= studyDate).filter(Column("endedAt") != nil).order(Column("startedAt")).fetchAll(db)
    } ?? []
  }

  /// いちばん新しい、終わった学習
  func latestFinished() -> SessionRecord? {
    read { db in
      try SessionRecord.filter(Column("endedAt") != nil).order(Column("startedAt").desc).fetchOne(db)
    } ?? nil
  }

  private func write(_ body: (Database) throws -> Void) {
    do {
      try db.write(body)
    } catch {
      log.error("保存できませんでした: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func read<T>(_ body: (Database) throws -> T) -> T? {
    do {
      return try db.read(body)
    } catch {
      log.error("読み出せませんでした: \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}
