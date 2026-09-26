import AVFoundation

/// 効果音(設計書 3.13)。試作品の voice.js と同じ音:
/// うとうとの注意音(高い音から低い音への 2 音)、居眠りのアラーム(音量を段階的に上げる)、区切りのやさしい音。
@MainActor
final class SoundPlayer {
  private let engine = AVAudioEngine()
  private let player = AVAudioPlayerNode()
  private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
  private var alarmTimer: Timer?
  private var alarmVolume: Float = 0.2

  init() {
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
  }

  /// 1 つの音:周波数(Hz)、長さ(秒)、音量(0〜1)。音量は指数的に小さくして消す
  struct Tone {
    var freq: Double
    var sec: Double
    var volume: Float
    /// この音を鳴らし始めてから、次の音までの秒数
    var next: Double
  }

  func play(_ tones: [Tone]) {
    guard let buffer = makeBuffer(tones) else { return }
    do {
      try AVAudioSession.sharedInstance().setActive(true)
      if !engine.isRunning { try engine.start() }
    } catch {
      return
    }
    player.scheduleBuffer(buffer, completionHandler: nil)
    if !player.isPlaying { player.play() }
  }

  /// 「うとうと」の注意音。短い効果音では聞こえにくかったため、長め・大きめ(技術検証の 8 回目)
  func chime() {
    play([Tone(freq: 988, sec: 0.35, volume: 0.8, next: 0.38), Tone(freq: 740, sec: 0.5, volume: 0.8, next: 0.5)])
  }

  /// 開始・休憩・終了の区切りのやさしい音(競合アプリの分析:終了の音がやさしいと好まれる)
  func gentle() {
    play([Tone(freq: 659, sec: 0.6, volume: 0.25, next: 0.25), Tone(freq: 880, sec: 0.9, volume: 0.25, next: 0.9)])
  }

  /// 位置が合ったときの短い音
  func ok() {
    play([Tone(freq: 784, sec: 0.15, volume: 0.3, next: 0.15)])
  }

  /// 居眠りのアラーム。止めるまで鳴らし、音量を段階的に上げる(設計書 3.8)
  func startAlarm() {
    guard alarmTimer == nil else { return }
    alarmVolume = 0.2
    ringAlarm()
    alarmTimer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.ringAlarm() }
    }
  }

  func stopAlarm() {
    alarmTimer?.invalidate()
    alarmTimer = nil
  }

  var alarmActive: Bool { alarmTimer != nil }

  private func ringAlarm() {
    play([Tone(freq: 1320, sec: 0.25, volume: alarmVolume, next: 0.3), Tone(freq: 990, sec: 0.25, volume: alarmVolume, next: 0.25)])
    alarmVolume = Swift.min(1, alarmVolume + 0.1)
  }

  private func makeBuffer(_ tones: [Tone]) -> AVAudioPCMBuffer? {
    let rate = format.sampleRate
    let total = tones.enumerated().reduce(0.0) { acc, e in
      Swift.max(acc, tones[..<e.offset].reduce(0) { $0 + $1.next } + e.element.sec)
    }
    let frames = AVAudioFrameCount((total + 0.02) * rate)
    guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames), let data = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = frames
    for i in 0..<Int(frames) { data[i] = 0 }
    var start = 0.0
    for tone in tones {
      let first = Int(start * rate)
      let count = Int(tone.sec * rate)
      let v = Double(Swift.max(tone.volume, 0.0002))
      for j in 0..<count where first + j < Int(frames) {
        let t = Double(j) / rate
        // 音量を volume から 0.0001 まで指数的に下げる(試作品の exponentialRampToValueAtTime と同じ)
        let gain = v * pow(0.0001 / v, t / tone.sec)
        data[first + j] += Float(gain * sin(2 * Double.pi * tone.freq * t))
      }
      start += tone.next
    }
    return buffer
  }
}
