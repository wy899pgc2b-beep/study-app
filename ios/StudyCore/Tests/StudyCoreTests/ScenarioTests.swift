import Foundation
import XCTest

@testable import StudyCore

/// 検証シナリオの採点が、試作品(scenario.js)と同じになること
final class ScenarioTests: XCTestCase {
  struct Fixture: Decodable {
    struct PhaseCase: Decodable {
      let phase: Int
      let setup: SetupStyle
      let samples: [ScenarioSample]
      let result: JSONValue
    }

    struct AtCase: Decodable {
      let elapsed: Double
      let index: Int?
      let inTransition: Bool?
      let phaseElapsed: Double?
    }

    let appVersion: String
    let phases: [PhaseCase]
    let phaseAt: [AtCase]
    let totalSec: Double
  }

  func testEvaluatePhaseMatchesPrototype() throws {
    let fx = try loadFixture(Fixture.self, "scenario")
    XCTAssertEqual(fx.appVersion, AnalysisConfig.prototypeVersion)
    XCTAssertEqual(Scenario.phases.count, 9)
    XCTAssertFalse(fx.phases.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.phases.enumerated() {
      let result = evaluatePhase(Scenario.phases[c.phase], samples: c.samples, setup: c.setup)
      diffJSON(try toJSON(result), c.result, "case\(i)(\(Scenario.phases[c.phase].id)・\(c.setup.rawValue))", &mismatches)
    }
    reportMismatches(mismatches, "検証シナリオの採点")
  }

  func testPhaseAtMatchesPrototype() throws {
    let fx = try loadFixture(Fixture.self, "scenario")
    XCTAssertEqual(Scenario.totalSec, fx.totalSec)
    for c in fx.phaseAt {
      let p = Scenario.phaseAt(c.elapsed)
      XCTAssertEqual(p?.index, c.index, "elapsed \(c.elapsed)")
      XCTAssertEqual(p?.inTransition, c.inTransition, "elapsed \(c.elapsed)")
      XCTAssertEqual(p?.phaseElapsed ?? -1, c.phaseElapsed ?? -1, accuracy: 1e-6, "elapsed \(c.elapsed)")
    }
  }

  func testSampleFromAnalyzerOutput() {
    var a = Analyzer(cfg: AnalysisConfig())
    var f = Features(t: 0)
    f.faceVisible = true
    f.present = true
    f.yawDeg = 0
    f.pitchDeg = 0
    f.faceBox = Box(minX: 0.4, maxX: 0.6, minY: 0.2, maxY: 0.5)
    f.chin = Point2(x: 0.5, y: 0.5)
    let out = a.update(f)
    let s = ScenarioSample(phaseElapsed: 1, dt: 0.2, kind: TimeKind(out.state), output: out)
    XCTAssertEqual(s.state, out.state.rawValue)
    XCTAssertEqual(s.metrics?["faceVisible"], 1)
    XCTAssertEqual(s.metrics?["handsCount"], 0)
    XCTAssertNil(s.metrics?["eyeDeskCm"], "値のない項目は入れない")
    XCTAssertEqual(s.flags["writing"], false)
    let paused = ScenarioSample(phaseElapsed: 1, dt: 0.2, kind: .away, output: nil)
    XCTAssertTrue(paused.away)
    XCTAssertNil(paused.metrics)
  }
}

/// 検証モードの進み方と、記録の書き出し
final class ScenarioRunTests: XCTestCase {
  func testRunGoesThroughAllPhases() {
    var run = ScenarioRun(setup: .landscape)
    var cues: [(Double, ScenarioCue)] = []
    var t = 0.0
    while !run.finished && t < 400 {
      for c in run.update(elapsedSec: t, dt: 0.2, kind: .think, output: nil) { cues.append((t, c)) }
      t += 0.2
    }
    XCTAssertTrue(run.finished)
    XCTAssertEqual(cues.filter { if case .phaseIntro = $0.1 { return true } else { return false } }.count, 9)
    XCTAssertEqual(cues.filter { if case .phaseStart = $0.1 { return true } else { return false } }.count, 9)
    XCTAssertEqual(cues.first?.1, .phaseIntro(index: 0))
    XCTAssertEqual(cues.last?.1, .done)
    XCTAssertEqual(cues.last?.0 ?? 0, Scenario.totalSec, accuracy: 0.3)
    // 最初の場面は、指示の 5 秒の後に始まる
    let start0 = cues.first { $0.1 == .phaseStart(index: 0) }?.0 ?? 0
    XCTAssertEqual(start0, 5, accuracy: 0.21)
    XCTAssertEqual(ScenarioRun.introSpeech(2), "3つめ。顔を上げたまま、目を閉じてください。音が鳴るまで開けないでください")
    let results = run.results()
    XCTAssertEqual(results.map(\.id), Scenario.phases.map(\.id))
    // 「読む」は思考だけだったので合格、「書く」は作業がないので不合格
    XCTAssertEqual(results[0].pass, true)
    XCTAssertEqual(results[1].pass, false)
    XCTAssertEqual(Double(run.samples["read"]?.count ?? 0), 125, accuracy: 1)
  }

  func testExportEncodes() throws {
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
      f.faceBox = Box(minX: 0.4, maxX: 0.6, minY: 0.2, maxY: 0.5)
      f.chin = Point2(x: 0.5, y: 0.5)
      _ = s.process(f)
    }
    let summary = try XCTUnwrap(s.finish(at: t + 5000))
    let perf = perfSummary([60, 70, 80], frames: 3, spanSec: 0.4, errors: 0, videoSize: "1280×960", device: "test", fov: 69.4)
    let export = SessionExport(
      appVersion: "0.1.0", createdAt: Date(timeIntervalSince1970: 0), reason: "manual", mode: "free", session: s, summary: summary,
      durationSec: 5, scenario: nil, perf: perf)
    let obj = try JSONDecoder().decode(JSONValue.self, from: export.json())
    guard case .object(let o) = obj else { return XCTFail("object") }
    for key in ["version", "app", "appVersion", "prototypeVersion", "createdAt", "cfg", "calibration", "summary", "minutes", "events", "perf"] {
      XCTAssertNotNil(o[key], key)
    }
    XCTAssertEqual(perf.avgMs, 70)
    XCTAssertEqual(perf.effectiveFps, 5, accuracy: 1e-9)
  }
}
