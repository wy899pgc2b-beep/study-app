import CoreMotion
import Foundation

/// 端末の傾き(重力の向き)。カメラの上向きの角度と、映像を正立させる向きに使う(MVP の設計 5 章)。
final class MotionSensor: @unchecked Sendable {
  struct Gravity: Sendable {
    var x: Double
    var y: Double
    var z: Double
  }

  private let manager = CMMotionManager()
  private let queue = OperationQueue()
  private let lock = NSLock()
  private var gravity: Gravity?

  func start() {
    guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
    manager.deviceMotionUpdateInterval = 0.1
    manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
      guard let self, let g = motion?.gravity else { return }
      self.lock.withLock { self.gravity = Gravity(x: g.x, y: g.y, z: g.z) }
    }
  }

  func stop() {
    manager.stopDeviceMotionUpdates()
  }

  /// 最新の重力(端末の座標。単位は g)。まだ取れていなければ nil
  var latest: Gravity? {
    lock.withLock { gravity }
  }
}
