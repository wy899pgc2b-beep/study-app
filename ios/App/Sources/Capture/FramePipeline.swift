import CoreVideo
import Foundation
import StudyCore

/// カメラのフレームから特徴量を作る(試作品の app.js の processFrame と同じ間引き方)。カメラのフレームの列で動かす。
final class FramePipeline: @unchecked Sendable {
  struct Result: Sendable {
    var features: Features
    /// 解析にかかった時間(ミリ秒)
    var processingMs: Double
    var rotation: ImageRotation
  }

  private let vision: VisionEngine
  private let motion: MotionSensor
  private let cfg: AnalysisConfig
  private var frameNo = 0
  private var lastPose: [Landmark]?
  private var lastPoseT = -Double.infinity
  private var lastT: Double?
  private var brightness: Double?
  /// 横向き立てかけが既定の置き方なので、分かるまでは横向きとみなす
  private var rotation: ImageRotation = .up

  init(vision: VisionEngine, motion: MotionSensor, cfg: AnalysisConfig) {
    self.vision = vision
    self.motion = motion
    self.cfg = cfg
  }

  func process(_ pixelBuffer: CVPixelBuffer, timestampMs t: Double) throws -> Result {
    let started = Date()
    frameNo += 1
    let gravity = motion.latest
    if let g = gravity, let r = backCameraImageRotation(gravityX: g.x, gravityY: g.y) { rotation = r }

    // 上半身は 2 回に 1 回、髪の領域分けは 5 回に 1 回(約 1 秒に 1 回)
    let withPose = frameNo % 2 == 1 || lastPose == nil
    let det = try vision.detect(pixelBuffer, rotation: rotation, timestampMs: t, withPose: withPose, withSegment: frameNo % 5 == 1)
    let interval = lastT.map { t - $0 } ?? 0
    lastT = t
    if withPose {
      lastPose = det.pose
      lastPoseT = t
    }
    // 上半身を解析しなかったフレームでは、直前の結果を使い回す(間隔に合わせて猶予を延ばす)
    let pose = withPose ? det.pose : (t - lastPoseT < Swift.max(1000, 2.5 * interval) ? lastPose : nil)
    if frameNo % 10 == 1 { brightness = Self.brightness(of: pixelBuffer) }

    let w = Double(CVPixelBufferGetWidth(pixelBuffer))
    let h = Double(CVPixelBufferGetHeight(pixelBuffer))
    let upright = rotation == .up || rotation == .down
    let frame = Frame(
      t: t,
      width: upright ? w : h,
      height: upright ? h : w,
      face: det.face,
      hands: det.hands,
      pose: pose,
      brightness: brightness,
      cameraTiltDeg: gravity.flatMap { cameraTiltFromGravity(x: $0.x, y: $0.y, z: $0.z, backCamera: true) },
      segment: det.segment
    )
    let features = extractFeatures(frame, cfg)
    return Result(features: features, processingMs: Date().timeIntervalSince(started) * 1000, rotation: rotation)
  }

  /// 画面全体の明るさ(0〜255)。試作品と同じく、16×12 の点の明るさの平均
  static func brightness(of pixelBuffer: CVPixelBuffer) -> Double? {
    guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else { return nil }
    CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
    let bytes = base.assumingMemoryBound(to: UInt8.self)
    var sum = 0.0
    let cols = 16
    let rows = 12
    for r in 0..<rows {
      let y = (2 * r + 1) * height / (2 * rows)
      for c in 0..<cols {
        let x = (2 * c + 1) * width / (2 * cols)
        let p = bytes + y * stride + x * 4
        sum += 0.114 * Double(p[0]) + 0.587 * Double(p[1]) + 0.299 * Double(p[2])
      }
    }
    return sum / Double(cols * rows)
  }
}
