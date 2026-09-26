import CoreVideo
import Foundation
import MediaPipeTasksVision
import StudyCore
import UIKit

/// 端末内の AI(MediaPipe の顔・手・上半身の特徴点と、髪・顔の肌の領域分け)。試作品の vision.js と同じモデルと設定。
/// 1 つの列(カメラのフレームの列)からだけ呼ぶ。
final class VisionEngine: @unchecked Sendable {
  enum VisionError: LocalizedError {
    case missingModel(String)

    var errorDescription: String? {
      switch self {
      case .missingModel(let name): return "AI のモデル(\(name))が見つかりません"
      }
    }
  }

  struct Detection {
    var face: FaceDetection?
    var hands: [[Landmark]]
    var pose: [Landmark]?
    var segment: SegmentStats?
  }

  private let face: FaceLandmarker
  private let hand: HandLandmarker
  private let pose: PoseLandmarker
  /// 読み込めなくても、ほかの判定は続ける
  private let segmenter: ImageSegmenter?
  private var lastTimestamp = 0

  init() throws {
    func modelPath(_ name: String, _ ext: String) throws -> String {
      guard let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: "Models") else { throw VisionError.missingModel(name) }
      return path
    }

    let faceOptions = FaceLandmarkerOptions()
    faceOptions.baseOptions.modelAssetPath = try modelPath("face_landmarker", "task")
    faceOptions.runningMode = .video
    faceOptions.numFaces = 1
    faceOptions.outputFaceBlendshapes = true
    face = try FaceLandmarker(options: faceOptions)

    let handOptions = HandLandmarkerOptions()
    handOptions.baseOptions.modelAssetPath = try modelPath("hand_landmarker", "task")
    handOptions.runningMode = .video
    handOptions.numHands = 2
    hand = try HandLandmarker(options: handOptions)

    let poseOptions = PoseLandmarkerOptions()
    poseOptions.baseOptions.modelAssetPath = try modelPath("pose_landmarker_lite", "task")
    poseOptions.runningMode = .video
    poseOptions.numPoses = 1
    pose = try PoseLandmarker(options: poseOptions)

    let segmentOptions = ImageSegmenterOptions()
    segmentOptions.baseOptions.modelAssetPath = try modelPath("selfie_multiclass_256x256", "tflite")
    segmentOptions.runningMode = .video
    segmentOptions.shouldOutputCategoryMask = true
    segmentOptions.shouldOutputConfidenceMasks = false
    segmenter = try? ImageSegmenter(options: segmentOptions)
  }

  /// 1 フレームを解析する。上半身は withPose、髪の領域分けは withSegment のときだけ(重いため間引く)
  func detect(_ pixelBuffer: CVPixelBuffer, rotation: ImageRotation, timestampMs: Double, withPose: Bool, withSegment: Bool) throws -> Detection {
    // MediaPipe の時刻は、単調に増える必要がある
    let ts = Swift.max(Int(timestampMs), lastTimestamp + 1)
    lastTimestamp = ts
    let image = try MPImage(pixelBuffer: pixelBuffer, orientation: rotation.uiImageOrientation)

    let faceResult = try face.detect(videoFrame: image, timestampInMilliseconds: ts)
    var faceOut: FaceDetection?
    if let lms = faceResult.faceLandmarks.first {
      var blendshapes: [String: Double] = [:]
      for c in faceResult.faceBlendshapes.first?.categories ?? [] {
        if let name = c.categoryName { blendshapes[name] = Double(c.score) }
      }
      faceOut = FaceDetection(landmarks: lms.map(Self.landmark), blendshapes: blendshapes)
    }

    let handResult = try hand.detect(videoFrame: image, timestampInMilliseconds: ts)
    let hands = handResult.landmarks.map { $0.map(Self.landmark) }

    var poseOut: [Landmark]?
    if withPose {
      let poseResult = try pose.detect(videoFrame: image, timestampInMilliseconds: ts)
      poseOut = poseResult.landmarks.first?.map(Self.landmark)
    }

    var segment: SegmentStats?
    if withSegment, let segmenter, let mask = try segmenter.segment(videoFrame: image, timestampInMilliseconds: ts).categoryMask {
      let buffer = UnsafeBufferPointer(start: mask.uint8Data, count: mask.width * mask.height)
      segment = segmentStats(mask: buffer, width: mask.width, height: mask.height)
    }
    return Detection(face: faceOut, hands: hands, pose: poseOut, segment: segment)
  }

  private static func landmark(_ l: NormalizedLandmark) -> Landmark {
    Landmark(x: Double(l.x), y: Double(l.y), z: Double(l.z), visibility: l.visibility?.doubleValue)
  }
}

extension ImageRotation {
  var uiImageOrientation: UIImage.Orientation {
    switch self {
    case .up: return .up
    case .down: return .down
    case .left: return .left
    case .right: return .right
    }
  }
}
