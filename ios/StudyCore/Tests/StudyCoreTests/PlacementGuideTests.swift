import Foundation
import XCTest

@testable import StudyCore

/// 設置位置ガイド(試作品の app.js の guideStep と同じ確かめ方)
final class PlacementGuideTests: XCTestCase {
  func face(_ t: Double, tilt: Double? = 15, hand: Bool = true, pose: Bool = false) -> Features {
    var f = Features(t: t)
    f.faceVisible = true
    f.present = true
    f.faceBox = Box(minX: 0.4, maxX: 0.6, minY: 0.2, maxY: 0.5)
    f.faceWidthNorm = 0.2
    f.faceHeightNorm = 0.3
    f.width = 1280
    f.height = 960
    f.cameraTiltDeg = tilt
    f.poseVisible = pose
    if hand {
      f.hands = [HandFeatures(pts: Array(repeating: Landmark(x: 0.5, y: 0.8), count: 21), centroid: Point2(x: 0.5, y: 0.8))]
    }
    return f
  }

  /// frames を 200ms ごとに入れ、出た案内と、そろった時刻を返す
  func run(_ g: inout PlacementGuide, seconds: Double, deviceLandscape: Bool? = true, _ make: (Double) -> Features) -> (
    prompts: [(Double, GuidePrompt)], readyAt: Double?
  ) {
    var prompts: [(Double, GuidePrompt)] = []
    var t = 0.0
    while t < seconds * 1000 {
      t += 200
      let step = g.update(make(t), deviceLandscape: deviceLandscape)
      prompts += step.prompts.map { (t, $0) }
      if step.ready { return (prompts, t) }
    }
    return (prompts, nil)
  }

  func testReadyAfterThreeSeconds() {
    var g = PlacementGuide(setup: .landscape)
    let r = run(&g, seconds: 10) { self.face($0) }
    XCTAssertEqual(r.readyAt ?? 0, 3200, accuracy: 1)
    XCTAssertTrue(r.prompts.isEmpty)
  }

  func testLandscapeWaitsForHandAndEscalates() {
    var g = PlacementGuide(setup: .landscape)
    let r = run(&g, seconds: 20) { self.face($0, hand: false) }
    XCTAssertNil(r.readyAt, "ペンを持った手が映るまで進まない")
    let hand = r.prompts.filter { $0.1 == .placeHand || $0.1 == .handNotVisible(canRaise: true) }
    // 8 秒ごとに知らせ、12 秒たっても映らなければ置き方を直してもらう
    XCTAssertEqual(hand.map { $0.0 }, [200, 8200, 16_200])
    XCTAssertEqual(hand.map { $0.1 }, [.placeHand, .placeHand, .handNotVisible(canRaise: true)])
  }

  func testHandFlickerIsTolerated() {
    var g = PlacementGuide(setup: .landscape)
    // 手が 1 秒おきに消えても(1.5 秒以内のちらつき)、そろったとみなす
    let r = run(&g, seconds: 10) { t in self.face(t, hand: Int(t / 1000) % 2 == 0) }
    XCTAssertNotNil(r.readyAt)
  }

  func testTiltOutOfRangeBlocksLandscape() {
    var g = PlacementGuide(setup: .landscape)
    let high = run(&g, seconds: 10) { self.face($0, tilt: 25) }
    XCTAssertNil(high.readyAt)
    XCTAssertEqual(high.prompts.first?.1, .tiltTooHigh)
    XCTAssertEqual(GuidePrompt.tiltTooHigh.speech, "スマホをもう少し起こしてください")
    var g2 = PlacementGuide(setup: .landscape)
    let low = run(&g2, seconds: 10) { self.face($0, tilt: 5) }
    XCTAssertNil(low.readyAt)
    XCTAssertEqual(low.prompts.first?.1, .tiltTooLow)
    // センサーが読めないときは止めない(試作品と同じ)
    var g3 = PlacementGuide(setup: .landscape)
    XCTAssertNotNil(run(&g3, seconds: 10) { self.face($0, tilt: nil) }.readyAt)
  }

  func testLandscapeNeedsLandscapeDevice() {
    var g = PlacementGuide(setup: .landscape)
    let r = run(&g, seconds: 10, deviceLandscape: false) { self.face($0) }
    XCTAssertNil(r.readyAt)
    XCTAssertTrue(r.prompts.contains { $0.1 == .turnLandscape })
  }

  func testStandNeedsShouldersNotHand() {
    var g = PlacementGuide(setup: .stand)
    let noPose = run(&g, seconds: 10, deviceLandscape: false) { self.face($0, tilt: nil, hand: false) }
    XCTAssertNil(noPose.readyAt)
    XCTAssertEqual(noPose.prompts.first?.1, .framing(.noShoulders))
    // 同じ種類の案内は 7 秒あける
    XCTAssertEqual(noPose.prompts.map { $0.0 }, [200, 7200])
    var g2 = PlacementGuide(setup: .stand)
    XCTAssertNotNil(run(&g2, seconds: 10, deviceLandscape: false) { self.face($0, tilt: nil, hand: false, pose: true) }.readyAt)
  }

  func testNoFace() {
    var g = PlacementGuide(setup: .landscape)
    let r = run(&g, seconds: 5) { Features(t: $0) }
    XCTAssertNil(r.readyAt)
    XCTAssertTrue(r.prompts.contains { $0.1 == .framing(.noFace) })
  }
}
