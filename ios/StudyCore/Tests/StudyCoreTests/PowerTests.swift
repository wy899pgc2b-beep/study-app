import XCTest

@testable import StudyCore

/// 熱と電池の決め方
final class PowerTests: XCTestCase {
  func testAnalysisFpsDropsWhenHot() {
    XCTAssertEqual(PowerPolicy.analysisFps(base: 5, thermal: .nominal), 5)
    XCTAssertEqual(PowerPolicy.analysisFps(base: 5, thermal: .fair), 5)
    XCTAssertEqual(PowerPolicy.analysisFps(base: 5, thermal: .serious), 3)
    XCTAssertEqual(PowerPolicy.analysisFps(base: 5, thermal: .critical), 2)
    XCTAssertEqual(PowerPolicy.analysisFps(base: 2, thermal: .serious), 2, "もとの回数より増やさない")
    XCTAssertTrue(PowerPolicy.shouldWarnHeat(.critical))
    XCTAssertFalse(PowerPolicy.shouldWarnHeat(.serious))
    XCTAssertTrue(ThermalLevel.serious > .fair)
  }

  func testBatteryActions() {
    XCTAssertEqual(PowerPolicy.batteryAction(level: 0.5, charging: false, warned: false), .none)
    XCTAssertEqual(PowerPolicy.batteryAction(level: 0.15, charging: false, warned: false), .warn)
    XCTAssertEqual(PowerPolicy.batteryAction(level: 0.12, charging: false, warned: true), .none, "知らせるのは 1 回だけ")
    XCTAssertEqual(PowerPolicy.batteryAction(level: 0.05, charging: false, warned: true), .finish)
    XCTAssertEqual(PowerPolicy.batteryAction(level: 0.03, charging: true, warned: false), .none, "充電中は何もしない")
    XCTAssertEqual(PowerPolicy.batteryAction(level: -1, charging: false, warned: false), .none, "分からないとき")
  }

  func testBatteryPerHour() {
    XCTAssertEqual(PowerPolicy.batteryPerHour(start: 0.8, end: 0.7, hours: 0.5) ?? -1, 20, accuracy: 1e-9)
    XCTAssertNil(PowerPolicy.batteryPerHour(start: 0.8, end: 0.7, hours: 0.05), "短すぎる")
    XCTAssertNil(PowerPolicy.batteryPerHour(start: 0.5, end: 0.6, hours: 1), "充電して増えた")
    XCTAssertNil(PowerPolicy.batteryPerHour(start: nil, end: 0.6, hours: 1))
    XCTAssertNil(PowerPolicy.batteryPerHour(start: -1, end: 0.6, hours: 1), "分からない")
  }
}
