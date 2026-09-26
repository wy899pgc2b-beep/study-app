import StudyCore
import SwiftUI
import UIKit

/// S-04〜S-07・S-19:開始の儀式、学習中、一時停止、休憩。
/// 学習中は画面を黒にし、画面に触れたら一時停止する(設計書 3.11)。開発中は確認用の表示を出せる。
struct SessionView: View {
  @Environment(AppModel.self) private var model
  @State private var showDebug = true

  var body: some View {
    let runner = model.runner
    ZStack {
      Color.black.ignoresSafeArea()
      VStack(spacing: 24) {
        switch runner.status {
        case .preparing, .idle:
          ProgressView("準備しています…").tint(.white).foregroundStyle(.white)
        case .failed(let message):
          Text(message).foregroundStyle(.white).multilineTextAlignment(.center)
          Button("ホームに戻る") { model.backHome() }.buttonStyle(.borderedProminent)
        case .running:
          content(runner)
        }
      }
      .padding()
      if showDebug, runner.status == .running {
        debugPanel(runner.debug).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if runner.phase == .studying { runner.pause(.touch) }
    }
    .onLongPressGesture(minimumDuration: 2) { showDebug.toggle() }
    .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    .statusBarHidden()
  }

  @ViewBuilder
  private func content(_ runner: SessionRunner) -> some View {
    switch runner.phase ?? .finished {
    case .ritual(.closeEyes):
      prompt("目を閉じて、ひと呼吸")
    case .ritual(.openEyes), .ritual(.posture):
      prompt("目を開けて、教材を見てください")
    case .studying:
      // 学習中は何も出さない(バックカメラでは画面が見えない)
      EmptyView()
    case .paused:
      prompt("一時停止中")
      Button("再開") { runner.resume() }.buttonStyle(.borderedProminent).controlSize(.large)
      Button("終了") { model.finish() }.buttonStyle(.bordered).tint(.white)
    case .onBreak:
      prompt("休憩中(カメラは止めています)")
      if let end = runner.breakEndsAt {
        Text(timerInterval: Date()...Swift.max(Date(), end), countsDown: true)
          .font(.largeTitle.monospacedDigit())
          .foregroundStyle(.white)
      }
      Button("休憩を終える") { runner.endBreak() }.buttonStyle(.borderedProminent).controlSize(.large)
      Button("終了") { model.finish() }.buttonStyle(.bordered).tint(.white)
    case .finished:
      EmptyView()
    }
  }

  private func prompt(_ text: String) -> some View {
    Text(text).font(.title2).foregroundStyle(.white).multilineTextAlignment(.center)
  }

  private func debugPanel(_ d: SessionRunner.DebugInfo) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(String(format: "解析 %.1f 回/秒・%.0f ms", d.fps, d.processingMs))
      Text("状態 \(d.state)")
      Text("顔 \(d.faceVisible ? "あり" : "なし")・手 \(d.handsCount)")
      Text("傾き \(d.tiltDeg.map { String(format: "%.1f°", $0) } ?? "—")・向き \(d.rotation)")
      Text("出来事 \(d.lastEvent)・エラー \(d.errors)")
    }
    .font(.caption.monospaced())
    .foregroundStyle(.green)
    .padding(8)
    .allowsHitTesting(false)
  }
}
