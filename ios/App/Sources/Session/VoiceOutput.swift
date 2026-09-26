import AVFoundation

/// 音声の案内(日本語)。バックカメラでは画面が見えないので、案内は声で伝える(設計書 3.13)。
/// 消音スイッチがオンでも聞こえるようにする。マイクは使わない。
@MainActor
final class VoiceOutput {
  private let synth = AVSpeechSynthesizer()
  /// 音量(0〜1。設定の「音量」)
  var volume: Float = 0.6

  init() {
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
  }

  /// interrupt:読み上げ中の案内を止めてから読む(儀式の区切りなど)
  func say(_ text: String, interrupt: Bool = false) {
    if interrupt, synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    try? AVAudioSession.sharedInstance().setActive(true)
    let u = AVSpeechUtterance(string: text)
    u.voice = AVSpeechSynthesisVoice(language: "ja-JP")
    u.rate = AVSpeechUtteranceDefaultSpeechRate
    u.volume = volume
    synth.speak(u)
  }

  func stop() {
    synth.stopSpeaking(at: .immediate)
  }
}
