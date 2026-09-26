import Foundation
import XCTest

@testable import StudyCore

/// カメラの映像を判定に渡すまでの計算(髪の面積、傾き、画像の向き)を確かめる。
final class VisionHelperTests: XCTestCase {
  struct VisionFixture: Decodable {
    struct SegmentCase: Decodable {
      let width: Int
      let height: Int
      let step: Int
      let mask: String
      let stats: JSONValue
    }

    let appVersion: String
    let segment: [SegmentCase]
  }

  /// 試作品の vision.js の segmentStats と同じ結果になる
  func testSegmentStatsMatchesPrototype() throws {
    let fx = try loadFixture(VisionFixture.self, "vision")
    XCTAssertEqual(fx.appVersion, AnalysisConfig.prototypeVersion)
    XCTAssertFalse(fx.segment.isEmpty)
    var mismatches: [String] = []
    for (i, c) in fx.segment.enumerated() {
      let mask = [UInt8](try XCTUnwrap(Data(base64Encoded: c.mask)))
      XCTAssertEqual(mask.count, c.width * c.height)
      let stats = segmentStats(mask: mask, width: c.width, height: c.height, step: c.step)
      diffJSON(try toJSON(stats), c.stats, "case\(i)", &mismatches)
    }
    reportMismatches(mismatches, "髪・顔の肌・人の面積")
  }

  func testSegmentStatsRejectsBadInput() {
    XCTAssertNil(segmentStats(mask: [], width: 0, height: 0))
    XCTAssertNil(segmentStats(mask: [0, 1], width: 2, height: 2))
  }

  /// 重力から求めた傾きが、試作品(ブラウザの beta・gamma)の式と同じになる
  func testTiltFromGravityMatchesOrientationFormula() {
    for beta in stride(from: -170.0, through: 170.0, by: 17.0) {
      for gamma in stride(from: -85.0, through: 85.0, by: 17.0) {
        // ブラウザの beta・gamma のときの重力(端末の座標)
        let b = rad(beta)
        let g = rad(gamma)
        let gx = cos(b) * sin(g)
        let gy = -sin(b)
        let gz = -cos(b) * cos(g)
        for back in [true, false] {
          let fromGravity = cameraTiltFromGravity(x: gx, y: gy, z: gz, backCamera: back)
          let fromOrientation = cameraTiltFromOrientation(betaDeg: beta, gammaDeg: gamma, backCamera: back)
          XCTAssertEqual(fromGravity!, fromOrientation!, accuracy: 1e-9, "beta \(beta) gamma \(gamma) back \(back)")
        }
      }
    }
  }

  func testTiltFromGravityExamples() {
    // 画面を上にして平らに置く:バックカメラは真下、フロントカメラは真上
    XCTAssertEqual(cameraTiltFromGravity(x: 0, y: 0, z: -1, backCamera: true)!, -90, accuracy: 1e-9)
    XCTAssertEqual(cameraTiltFromGravity(x: 0, y: 0, z: -1, backCamera: false)!, 90, accuracy: 1e-9)
    // 横向きに立て、バックカメラが 15° 上を向くように後ろへ傾ける(推奨の置き方)
    let t = rad(15)
    XCTAssertEqual(cameraTiltFromGravity(x: -cos(t), y: 0, z: sin(t), backCamera: true)!, 15, accuracy: 1e-9)
    // 重力が取れていない
    XCTAssertNil(cameraTiltFromGravity(x: 0, y: 0, z: 0, backCamera: true))
  }

  func testBackCameraImageRotation() {
    XCTAssertEqual(backCameraImageRotation(gravityX: 0, gravityY: -1), .right)  // 縦向き
    XCTAssertEqual(backCameraImageRotation(gravityX: 0, gravityY: 1), .left)  // 縦向き(上下逆)
    XCTAssertEqual(backCameraImageRotation(gravityX: -1, gravityY: 0), .up)  // 横向き(上端が左)
    XCTAssertEqual(backCameraImageRotation(gravityX: 1, gravityY: 0), .down)  // 横向き(上端が右)
    XCTAssertEqual(backCameraImageRotation(gravityX: -0.96, gravityY: -0.1), .up)  // 横向きで少し傾いている
    XCTAssertNil(backCameraImageRotation(gravityX: 0.1, gravityY: 0.1))  // 平らに置いている
    XCTAssertEqual(deviceIsLandscape(gravityX: -0.9, gravityY: 0.2), true)
    XCTAssertEqual(deviceIsLandscape(gravityX: 0.1, gravityY: -0.9), false)
    XCTAssertNil(deviceIsLandscape(gravityX: 0.05, gravityY: 0.05))
  }
}
