import AVFoundation
import AudioToolbox
import CoreHaptics

/// 消音モードの知らせ(振動だけ。決定事項 D-21)。置いたあとは画面が見えないので、区切りを振動の回数で伝える:
/// 1 回=位置が合った(はじめは目を閉じる)、2 回=目を開けて教材を見る(うとうとのときも)、3 回=休憩の始まりと終わり、
/// 長い 1 回=まだ位置が合っていない、長い 2 回=仮眠のおすすめ(D-23)、長い振動のくり返し=居眠りと仮眠の終わり
@MainActor
final class Vibrator {
  private let engine: CHHapticEngine?
  private var alarmTimer: Timer?

  init() {
    if CHHapticEngine.capabilitiesForHardware().supportsHaptics, let e = try? CHHapticEngine() {
      e.playsHapticsOnly = true
      e.isAutoShutdownEnabled = true
      e.resetHandler = { [weak e] in try? e?.start() }
      engine = e
    } else {
      engine = nil
    }
  }

  /// count 回、sec 秒ずつ振動する
  func pulse(_ count: Int, sec: Double = 0.3, gap: Double = 0.25) {
    guard count > 0 else { return }
    guard let engine else {
      fallback(count, interval: sec + gap)
      return
    }
    let events = (0..<count).map { i in
      CHHapticEvent(
        eventType: .hapticContinuous,
        parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4),
        ],
        relativeTime: Double(i) * (sec + gap), duration: sec)
    }
    do {
      try engine.start()
      let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
      try player.start(atTime: CHHapticTimeImmediate)
    } catch {
      fallback(count, interval: sec + gap)
    }
  }

  /// まだ位置が合っていない、やり直す(長い 1 回)
  func long() {
    pulse(1, sec: 0.9)
  }

  /// 居眠りのアラーム。止めるまで長い振動をくり返す
  func startAlarm() {
    guard alarmTimer == nil else { return }
    // 立てかけたスマホがずれないよう、続けて鳴らさずに間をあける(設計書 3.13 の要件 5)
    pulse(2, sec: 0.5, gap: 0.3)
    alarmTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.pulse(2, sec: 0.5, gap: 0.3) }
    }
  }

  func stopAlarm() {
    alarmTimer?.invalidate()
    alarmTimer = nil
  }

  /// Core Haptics が使えない機種では、標準の振動を回数だけ鳴らす
  private func fallback(_ count: Int, interval: Double) {
    for i in 0..<count {
      DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * Swift.max(0.6, interval)) {
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      }
    }
  }
}

/// 音の出先。イヤホン(有線・Bluetooth)がつながっているか
enum AudioRoute {
  static var headphonesConnected: Bool {
    let ports: Set<AVAudioSession.Port> = [.headphones, .bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .usbAudio]
    return AVAudioSession.sharedInstance().currentRoute.outputs.contains { ports.contains($0.portType) }
  }
}
