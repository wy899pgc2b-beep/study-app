import Foundation

/// 特徴点(MediaPipe の正規化座標。x・y は画像の幅・高さを 1 とし、z は幅と同じ尺度)。
public struct Landmark: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var z: Double?
  public var visibility: Double?

  public init(x: Double, y: Double, z: Double? = nil, visibility: Double? = nil) {
    self.x = x
    self.y = y
    self.z = z
    self.visibility = visibility
  }
}

public struct Point2: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public struct Box: Codable, Equatable, Sendable {
  public var minX: Double
  public var maxX: Double
  public var minY: Double
  public var maxY: Double

  public init(minX: Double, maxX: Double, minY: Double, maxY: Double) {
    self.minX = minX
    self.maxX = maxX
    self.minY = minY
    self.maxY = maxY
  }
}

/// 髪・顔の肌・人の面積(画面を 1 とする割合)と、頭頂部の見える割合(設計書 4.9)。
public struct SegmentStats: Codable, Equatable, Sendable {
  public var crownRatio: Double?
  public var hairFrac: Double?
  public var faceSkinFrac: Double?
  public var personFrac: Double?

  public init(crownRatio: Double? = nil, hairFrac: Double? = nil, faceSkinFrac: Double? = nil, personFrac: Double? = nil) {
    self.crownRatio = crownRatio
    self.hairFrac = hairFrac
    self.faceSkinFrac = faceSkinFrac
    self.personFrac = personFrac
  }
}

public struct FaceDetection: Codable, Sendable {
  public var landmarks: [Landmark]
  /// 表情係数(eyeBlinkLeft など、MediaPipe の名前のまま)
  public var blendshapes: [String: Double]?

  public init(landmarks: [Landmark], blendshapes: [String: Double]?) {
    self.landmarks = landmarks
    self.blendshapes = blendshapes
  }
}

/// 1 フレーム分の検出結果。t はミリ秒。
public struct Frame: Codable, Sendable {
  public var t: Double
  public var width: Double
  public var height: Double
  public var face: FaceDetection?
  public var hands: [[Landmark]]
  public var pose: [Landmark]?
  public var brightness: Double?
  public var cameraTiltDeg: Double?
  public var segment: SegmentStats?

  public init(
    t: Double, width: Double, height: Double, face: FaceDetection? = nil, hands: [[Landmark]] = [], pose: [Landmark]? = nil,
    brightness: Double? = nil, cameraTiltDeg: Double? = nil, segment: SegmentStats? = nil
  ) {
    self.t = t
    self.width = width
    self.height = height
    self.face = face
    self.hands = hands
    self.pose = pose
    self.brightness = brightness
    self.cameraTiltDeg = cameraTiltDeg
    self.segment = segment
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    t = try c.decode(Double.self, forKey: .t)
    width = try c.decode(Double.self, forKey: .width)
    height = try c.decode(Double.self, forKey: .height)
    face = try c.decodeIfPresent(FaceDetection.self, forKey: .face)
    hands = try c.decodeIfPresent([[Landmark]].self, forKey: .hands) ?? []
    pose = try c.decodeIfPresent([Landmark].self, forKey: .pose)
    brightness = try c.decodeIfPresent(Double.self, forKey: .brightness)
    cameraTiltDeg = try c.decodeIfPresent(Double.self, forKey: .cameraTiltDeg)
    segment = try c.decodeIfPresent(SegmentStats.self, forKey: .segment)
  }
}

public struct HandFeatures: Codable, Sendable {
  public var pts: [Landmark]
  public var centroid: Point2
  /// 手の大きさ(手首〜中指の付け根。画像の幅を 1 とする)
  public var sizeNorm: Double?
  /// 手の形:手の大きさを 1 とした、親指と人差し指の先の距離
  public var pinch: Double?
  /// 人差し指の先の、手首に対する位置(手の大きさを 1 とする)
  public var finger: Point2?

  public init(pts: [Landmark], centroid: Point2, sizeNorm: Double? = nil, pinch: Double? = nil, finger: Point2? = nil) {
    self.pts = pts
    self.centroid = centroid
    self.sizeNorm = sizeNorm
    self.pinch = pinch
    self.finger = finger
  }
}

/// 1 フレーム分の特徴量(設計書 4.3)。名前は試作品(prototype/js/analysis.js)と同じ。
/// 取れなかった値は nil(試作品の undefined と同じ扱い:比べると常に偽)。
public struct Features: Codable, Sendable {
  public var t: Double
  public var width: Double?
  public var height: Double?
  public var brightness: Double?
  public var cameraTiltDeg: Double?
  public var faceVisible: Bool = false
  public var poseVisible: Bool = false
  public var hands: [HandFeatures] = []
  public var faceBox: Box?
  public var chin: Point2?
  public var ear: Double?
  public var blink: Double?
  public var eyeLookDown: Double?
  public var eyeLookUp: Double?
  public var eyeLookSide: Double?
  public var jawOpen: Double?
  public var rollDeg: Double?
  public var yawDeg: Double?
  public var pitchDeg: Double?
  public var eyeMid: Point2?
  public var faceWidthNorm: Double?
  public var faceHeightNorm: Double?
  public var irisPx: Double?
  public var camDistCm: Double?
  public var verticalOffsetCm: Double?
  public var shoulderTiltDeg: Double?
  public var shoulderMid: Point2?
  public var slouchRatio: Double?
  public var headHeight: Double?
  public var noseN: Point2?
  public var headLow: Bool?
  public var seg: SegmentStats?
  public var present: Bool = false

  public init(t: Double) {
    self.t = t
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    t = try c.decode(Double.self, forKey: .t)
    width = try c.decodeIfPresent(Double.self, forKey: .width)
    height = try c.decodeIfPresent(Double.self, forKey: .height)
    brightness = try c.decodeIfPresent(Double.self, forKey: .brightness)
    cameraTiltDeg = try c.decodeIfPresent(Double.self, forKey: .cameraTiltDeg)
    faceVisible = try c.decodeIfPresent(Bool.self, forKey: .faceVisible) ?? false
    poseVisible = try c.decodeIfPresent(Bool.self, forKey: .poseVisible) ?? false
    hands = try c.decodeIfPresent([HandFeatures].self, forKey: .hands) ?? []
    faceBox = try c.decodeIfPresent(Box.self, forKey: .faceBox)
    chin = try c.decodeIfPresent(Point2.self, forKey: .chin)
    ear = try c.decodeIfPresent(Double.self, forKey: .ear)
    blink = try c.decodeIfPresent(Double.self, forKey: .blink)
    eyeLookDown = try c.decodeIfPresent(Double.self, forKey: .eyeLookDown)
    eyeLookUp = try c.decodeIfPresent(Double.self, forKey: .eyeLookUp)
    eyeLookSide = try c.decodeIfPresent(Double.self, forKey: .eyeLookSide)
    jawOpen = try c.decodeIfPresent(Double.self, forKey: .jawOpen)
    rollDeg = try c.decodeIfPresent(Double.self, forKey: .rollDeg)
    yawDeg = try c.decodeIfPresent(Double.self, forKey: .yawDeg)
    pitchDeg = try c.decodeIfPresent(Double.self, forKey: .pitchDeg)
    eyeMid = try c.decodeIfPresent(Point2.self, forKey: .eyeMid)
    faceWidthNorm = try c.decodeIfPresent(Double.self, forKey: .faceWidthNorm)
    faceHeightNorm = try c.decodeIfPresent(Double.self, forKey: .faceHeightNorm)
    irisPx = try c.decodeIfPresent(Double.self, forKey: .irisPx)
    camDistCm = try c.decodeIfPresent(Double.self, forKey: .camDistCm)
    verticalOffsetCm = try c.decodeIfPresent(Double.self, forKey: .verticalOffsetCm)
    shoulderTiltDeg = try c.decodeIfPresent(Double.self, forKey: .shoulderTiltDeg)
    shoulderMid = try c.decodeIfPresent(Point2.self, forKey: .shoulderMid)
    slouchRatio = try c.decodeIfPresent(Double.self, forKey: .slouchRatio)
    headHeight = try c.decodeIfPresent(Double.self, forKey: .headHeight)
    noseN = try c.decodeIfPresent(Point2.self, forKey: .noseN)
    headLow = try c.decodeIfPresent(Bool.self, forKey: .headLow)
    seg = try c.decodeIfPresent(SegmentStats.self, forKey: .seg)
    present = try c.decodeIfPresent(Bool.self, forKey: .present) ?? false
  }
}
