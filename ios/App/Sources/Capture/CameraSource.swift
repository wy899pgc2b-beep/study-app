import AVFoundation
import CoreVideo

/// バックカメラの映像を 4:3 で取り出し、毎秒 fps 回だけ渡す(MVP の設計 5 章 CameraSource)。
/// 映像はメモリの中だけで扱い、保存しない。
final class CameraSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
  enum CameraError: LocalizedError {
    case noCamera
    case cannotConfigure

    var errorDescription: String? {
      switch self {
      case .noCamera: return "カメラが見つかりません"
      case .cannotConfigure: return "カメラを準備できませんでした"
      }
    }
  }

  let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "camera.session")
  /// フレームを受け取る列(解析もこの列で行う)
  let frameQueue = DispatchQueue(label: "camera.frames")

  /// 解析する回数(毎秒)
  var fps: Double = 5
  /// 解析するフレーム(frameQueue で呼ぶ)。時刻はミリ秒
  var onFrame: ((CVPixelBuffer, Double) -> Void)?
  /// 使っている形式の、長辺の画角(度)
  private(set) var fovLongSideDeg: Double?
  private(set) var dimensions: CMVideoDimensions?
  private var lastMs = -Double.infinity

  static func requestAccess() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    default: return false
    }
  }

  func configure() throws {
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw CameraError.noCamera }
    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else { throw CameraError.cannotConfigure }
    session.addInput(input)

    // 必ず 4:3 の形式を使う。16:9 では上下が切られ、横向きで手元と頭が入らない(技術検証の 13〜15 回目)
    if let format = Self.pickFormat(device) {
      try device.lockForConfiguration()
      device.activeFormat = format
      // 解析は毎秒 5 回なので、カメラも 15 回に落として電池を節約する
      if format.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 15 && 15 <= $0.maxFrameRate }) {
        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 15)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
      }
      device.unlockForConfiguration()
      fovLongSideDeg = Double(format.videoFieldOfView)
      dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
    }

    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: frameQueue)
    guard session.canAddOutput(output) else { throw CameraError.cannotConfigure }
    session.addOutput(output)
  }

  /// 4:3 で、幅が 1280 に近い形式(試作品と同じ 1280×960 前後)
  static func pickFormat(_ device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    func width(_ f: AVCaptureDevice.Format) -> Int { Int(CMVideoFormatDescriptionGetDimensions(f.formatDescription).width) }
    let candidates = device.formats.filter { f in
      let d = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
      return Int(d.width) * 3 == Int(d.height) * 4 && d.width >= 960 && d.width <= 1920
        && CMFormatDescriptionGetMediaSubType(f.formatDescription) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    }
    return candidates.min { abs(width($0) - 1280) < abs(width($1) - 1280) }
  }

  /// 解析する回数を変える(熱いときに下げる)。フレームを受け取る列で書き換える
  func setAnalysisFps(_ value: Double) {
    frameQueue.async { [weak self] in self?.fps = value }
  }

  func start() {
    sessionQueue.async { [session] in
      if !session.isRunning { session.startRunning() }
    }
  }

  func stop() {
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    let ms = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer)) * 1000
    guard ms - lastMs >= 1000 / fps - 4 else { return }
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    lastMs = ms
    onFrame?(pixelBuffer, ms)
  }
}
