import Foundation
import XCTest

@testable import StudyCore

/// 試作品(prototype/js/analysis.js、版 poc-24)と同じ判定になっているかを、試作品から書き出したデータで確かめる
/// (MVP の完成の条件「判定が試作品と一致する」)。
final class ParityTests: XCTestCase {
  // 大きいデータなので一度だけ読む
  static let analyzer = Result { try loadFixture(AnalyzerFixture.self, "analyzer") }
  static let misc = Result { try loadFixture(MiscFixture.self, "misc") }

  func testConfigMatchesPrototype() throws {
    let fx = try loadFixture(FeaturesFixture.self, "features")
    XCTAssertEqual(fx.appVersion, AnalysisConfig.prototypeVersion, "Config.swift が古い。prototype で node tools/gen-swift-config.mjs を実行する")
    var mismatches: [String] = []
    diffJSON(try toJSON(AnalysisConfig()), fx.cfg, "cfg", &mismatches)
    reportMismatches(mismatches, "しきい値")
  }

  func testFeatureExtraction() throws {
    let fx = try loadFixture(FeaturesFixture.self, "features")
    XCTAssertFalse(fx.cases.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.cases.enumerated() {
      diffJSON(try toJSON(extractFeatures(c.frame, AnalysisConfig())), c.features, "case\(i)", &mismatches)
    }
    reportMismatches(mismatches, "特徴量")
  }

  func testAnalyzer() throws {
    let fx = try Self.analyzer.get()
    XCTAssertEqual(fx.appVersion, AnalysisConfig.prototypeVersion)
    var mismatches: [String] = []
    var frames = 0
    var sessionsWithDiff = 0
    for (si, s) in fx.sessions.enumerated() {
      var a = Analyzer(cfg: s.cfg, autoAway: s.options.autoAway, setup: s.options.setup)
      var fi = 0
      var local: [String] = []
      for op in s.ops {
        switch op {
        case .calibration(let cal):
          a.setCalibration(cal)
        case .frame(let f, let expected, _):
          diffJSON(try toJSON(a.update(f)), expected, "session\(si).frame\(fi)", &local)
          fi += 1
          frames += 1
        }
      }
      if !local.isEmpty {
        sessionsWithDiff += 1
        // 一度ずれると後のフレームも全部ずれるので、各セッションの最初の数件だけ見せる
        mismatches += local.prefix(5)
      }
    }
    XCTAssertGreaterThan(frames, 1000)
    reportMismatches(mismatches, "判定(\(fx.sessions.count) セッション・\(frames) フレーム中、\(sessionsWithDiff) セッションで違い)")
  }

  func testCalibration() throws {
    let sessions = try Self.analyzer.get().sessions
    let fx = try Self.misc.get()
    XCTAssertFalse(fx.calibration.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.calibration.enumerated() {
      let s = sessions[c.session]
      let frames = s.frames
      let slice = { (from: Int, to: Int) in Array(frames[Swift.min(from, frames.count)..<Swift.min(to, frames.count)]) }
      let cal = computeCalibration(slice(c.from, c.to), measuredEyeDeskCm: c.opts.measuredEyeDeskCm, tiltDeg: c.opts.tiltDeg)
      diffJSON(try toJSON(cal), c.cal, "case\(i).cal", &mismatches)
      let closedRef = cal == nil ? nil : computeClosedReference(slice(c.closedFrom, c.closedTo), cal, s.cfg)
      diffJSON(try toJSON(closedRef), c.closedRef, "case\(i).closedRef", &mismatches)
      var withRef = cal
      withRef?.closedRef = closedRef
      let signal = cal == nil ? nil : eyeSignalQuality(withRef, s.cfg).rawValue
      if signal != c.eyeSignal { mismatches.append("case\(i).eyeSignal: swift \(signal ?? "nil") / js \(c.eyeSignal ?? "nil")") }
    }
    reportMismatches(mismatches, "キャリブレーション")
  }

  func testFraming() throws {
    let sessions = try Self.analyzer.get().sessions
    let fx = try Self.misc.get()
    XCTAssertFalse(fx.framing.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.framing.enumerated() {
      let issues = checkFraming(sessions[c.session].frames[c.frame], setup: c.setup)
      let codes = issues.map(\.rawValue)
      if codes != c.codes || issues.isEmpty != c.ok { mismatches.append("case\(i): swift \(codes) / js \(c.codes)") }
    }
    reportMismatches(mismatches, "位置合わせ")
  }

  func testSessionRecorder() throws {
    let sessions = try Self.analyzer.get().sessions
    let fx = try Self.misc.get()
    XCTAssertFalse(fx.recorder.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.recorder.enumerated() {
      // 試作品の app.js と同じように、状態(離席中は away)と出来事を 1 分ごとに集計する
      var rec = SessionRecorder(startT: c.startT, cfg: sessions[c.session].cfg, autoAway: c.autoAway)
      var prevT: Double?
      for (f, out) in sessions[c.session].outputs {
        let dt = prevT.map { Swift.min(1, (f.t - $0) / 1000) } ?? 0
        prevT = f.t
        rec.add(t: f.t, dtSec: dt, kind: out.away ? .away : TimeKind(out.state))
        for ev in out.events { rec.addEvent(ev) }
      }
      diffJSON(try toJSON(rec.summary()), c.summary, "case\(i).summary", &mismatches)
      diffJSON(try toJSON(rec.minutes), c.minutes, "case\(i).minutes", &mismatches)
    }
    reportMismatches(mismatches, "1 分ごとの集計")
  }

  func testScoreMinute() throws {
    let fx = try Self.misc.get()
    XCTAssertFalse(fx.scoreMinute.isEmpty)
    for (i, c) in fx.scoreMinute.enumerated() {
      let m = MinuteRecord(index: 0, secs: c.minute.secs, habits: c.minute.habits, interruptions: c.minute.interruptions)
      XCTAssertEqual(scoreMinute(m, AnalysisConfig(), autoAway: c.autoAway), c.score, "case\(i)")
    }
  }

  /// 突き合わせが違いを見逃さないこと(比べ方の誤りで、何でも「一致」にならないか)を確かめる
  func testComparisonDetectsDifferences() throws {
    var m: [String] = []
    diffJSON(.number(1), .number(1.001), "a", &m)
    diffJSON(.null, .number(0), "b", &m)
    diffJSON(.string("ear"), .string("personal"), "c", &m)
    diffJSON(.object(["x": .number(1)]), .object([:]), "d", &m)
    XCTAssertEqual(m.count, 4, "\(m)")
    m = []
    diffJSON(.string("NaN"), .null, "e", &m)
    diffJSON(nil, .null, "f", &m)
    diffJSON(.number(0.1 + 0.2), .number(0.3), "g", &m)
    XCTAssertEqual(m, [])

    // しきい値を 1 つ変えると、判定の突き合わせで違いが出る
    let s = try Self.analyzer.get().sessions.first { $0.ops.count > 20 }!
    var cfg = s.cfg
    cfg.lookAwaySec = 0
    cfg.drowsyClosedSec = 0
    var a = Analyzer(cfg: cfg, autoAway: s.options.autoAway, setup: s.options.setup)
    m = []
    for op in s.ops {
      switch op {
      case .calibration(let cal): a.setCalibration(cal)
      case .frame(let f, let expected, _): diffJSON(try toJSON(a.update(f)), expected, "frame", &m)
      }
    }
    XCTAssertFalse(m.isEmpty)
  }

  func testLearningStyle() throws {
    let fx = try Self.misc.get()
    XCTAssertFalse(fx.learningStyle.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.learningStyle.enumerated() {
      diffJSON(try toJSON(learningStyle(workSec: c.work, thinkSec: c.think, minuteScores: c.scores)), c.style, "case\(i)", &mismatches)
    }
    reportMismatches(mismatches, "学習スタイル")
  }
}
