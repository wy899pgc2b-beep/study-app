import StudyCore
import SwiftUI
import UIKit

/// S-04〜S-07・S-19:位置合わせ、開始の儀式、学習中、一時停止、休憩(設計書 5.5)。
/// 置いたあとは画面が見えないので、位置合わせから学習中までは暗い画面にする。学習中に画面に触れたら一時停止する(設計書 3.11)。
struct SessionView: View {
  @Environment(AppModel.self) private var model
  @State private var showDebug = false
  @State private var savedBrightness: CGFloat?

  var body: some View {
    let runner = model.runner
    let phase = runner.phase ?? .finished
    ZStack {
      switch runner.status {
      case .preparing, .idle:
        darkScreen { ProgressView("準備しています…").tint(.white).foregroundStyle(.white).font(AppFont.regular(16)) }
      case .failed(let message):
        failed(message)
      case .cameraDenied:
        cameraDenied
      case .running:
        switch phase {
        case .paused:
          PausedScreen()
        case .onBreak:
          BreakScreen()
        default:
          darkScreen { darkContent(runner, phase) }
        }
      }
      if showDebug, runner.status == .running {
        debugPanel(runner.debug).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .onLongPressGesture(minimumDuration: 2) { showDebug.toggle() }
    .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
    .onDisappear {
      UIApplication.shared.isIdleTimerDisabled = false
      restoreBrightness()
    }
    .onChange(of: phase) { _, newPhase in
      // 学習中は画面を最低の明るさにする(MVP の設計 5 章)
      if newPhase == .studying { dimScreen() } else { restoreBrightness() }
    }
    .statusBarHidden()
  }

  private func darkScreen<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    ZStack {
      Color.black.ignoresSafeArea()
      content().padding(24)
    }
    .contentShape(Rectangle())
    .onTapGesture {
      if model.runner.phase == .studying { model.runner.pause(.touch) }
    }
  }

  @ViewBuilder
  private func darkContent(_ runner: SessionRunner, _ phase: SessionPhase) -> some View {
    switch phase {
    case .guide:
      VStack(spacing: 20) {
        Text("位置を合わせているよ").font(AppFont.bold(24)).foregroundStyle(.white)
        Text("声の案内に合わせて、スマホを動かしてね").font(AppFont.regular(15)).foregroundStyle(Palette.dimText)
        VStack(alignment: .leading, spacing: 10) {
          ForEach(Array(runner.guideChecks.enumerated()), id: \.offset) { _, check in
            Label(check.label, systemImage: check.ok ? "checkmark.circle.fill" : "circle")
              .font(AppFont.regular(15))
              .foregroundStyle(check.ok ? Palette.barSoft : Color.white)
          }
        }
        Button("位置合わせを省く") { runner.skipGuide() }
          .font(AppFont.regular(15))
          .foregroundStyle(Palette.dimText)
          .frame(minHeight: 44)
      }
    case .ritual(let step):
      RitualView(step: step)
    case .studying:
      if runner.mode == .scenario {
        ScenarioProgressView(position: runner.scenarioPosition)
      } else {
        StudyingLamp(startedAt: runner.studyStartedAt)
      }
    default:
      EmptyView()
    }
  }

  private func failed(_ message: String) -> some View {
    ZStack {
      PaperBackground()
      VStack(spacing: 20) {
        Text(message).font(AppFont.regular(17)).foregroundStyle(Palette.ink).multilineTextAlignment(.center)
        Button("ホームに戻る") { model.backHome() }.buttonStyle(PrimaryButtonStyle(height: 60, fontSize: 20))
      }
      .padding(24)
    }
  }

  /// カメラが許可されていないとき(MVP の設計 S-01。カメラなしで時間だけ記録する使い方は、後で加える)
  private var cameraDenied: some View {
    ZStack {
      PaperBackground()
      VStack(spacing: 18) {
        Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(Palette.subInk).accessibilityHidden(true)
        Text("カメラが使えません").font(AppFont.bold(22))
        Text("学習の様子を判定するには、カメラの許可が必要です。「設定を開く」から、ツクエログのカメラをオンにしてください。映像はこの iPhone の中だけで解析します")
          .font(AppFont.regular(15)).foregroundStyle(Palette.subInk).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        Button("設定を開く") {
          if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        .buttonStyle(PrimaryButtonStyle(height: 60, fontSize: 20))
        Button("ホームに戻る") { model.backHome() }
          .buttonStyle(OutlineButtonStyle(selected: false, height: 52))
      }
      .foregroundStyle(Palette.ink)
      .padding(24)
    }
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

  private var screen: UIScreen? {
    UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first
  }

  private func dimScreen() {
    guard let screen else { return }
    if savedBrightness == nil { savedBrightness = screen.brightness }
    screen.brightness = 0
  }

  private func restoreBrightness() {
    guard let screen, let b = savedBrightness else { return }
    screen.brightness = b
    savedBrightness = nil
  }
}

/// 開始の儀式:ゆっくり呼吸する円
struct RitualView: View {
  var step: RitualStep
  @State private var breathe = false

  var body: some View {
    VStack(spacing: 28) {
      Circle()
        .fill(Palette.focus.opacity(0.35))
        .frame(width: 140, height: 140)
        .scaleEffect(breathe ? 1.0 : 0.6)
        .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
        .onAppear { breathe = true }
      Text(step == .closeEyes ? "目を閉じて、ひと呼吸" : "目を開けて、教材を見てね")
        .font(AppFont.bold(24))
        .foregroundStyle(.white)
    }
  }
}

/// 学習中:黒い画面に、ランプの小さな灯りと経過時間を暗く出す(設計書 5.5 の 6)
struct StudyingLamp: View {
  var startedAt: Date?

  var body: some View {
    ZStack {
      VStack(spacing: 18) {
        ZStack {
          Circle().fill(Palette.lamp.opacity(0.10)).frame(width: 88, height: 88)
          Circle().fill(Palette.lamp.opacity(0.18)).frame(width: 52, height: 52)
          Circle().fill(Palette.lampGlow.opacity(0.85)).frame(width: 18, height: 18)
        }
        .accessibilityLabel("学習中")
        if let startedAt {
          TimelineView(.periodic(from: startedAt, by: 1)) { ctx in
            Text(elapsed(from: startedAt, to: ctx.date))
              .font(AppFont.regular(30).monospacedDigit())
              .foregroundStyle(Color(hex: 0x7A7A7A))
          }
        }
      }
      VStack {
        Spacer()
        Text("画面に触れると一時停止します").font(AppFont.regular(13)).foregroundStyle(Palette.dimText)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func elapsed(from start: Date, to now: Date) -> String {
    let s = Swift.max(0, Int(now.timeIntervalSince(start)))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
  }
}

/// 検証モードの学習中:いまの場面と残り時間(試作品の検証シナリオの表示と同じ)。指示は声で伝える
struct ScenarioProgressView: View {
  var position: Scenario.Position?

  var body: some View {
    VStack(spacing: 14) {
      Text("検証モード").font(AppFont.regular(14)).foregroundStyle(Palette.dimText)
      if let p = position {
        let phase = Scenario.phases[p.index]
        Text("\(p.index + 1) / \(Scenario.phases.count)").font(AppFont.regular(30).monospacedDigit()).foregroundStyle(Color(hex: 0x7A7A7A))
        Text(p.inTransition ? "次:\(phase.label)" : phase.label).font(AppFont.bold(20)).foregroundStyle(Color(hex: 0x9A9A9A))
        Text(p.inTransition ? "指示を聞いてください" : "あと \(Int((phase.sec - p.phaseElapsed).rounded(.up))) 秒")
          .font(AppFont.regular(15).monospacedDigit()).foregroundStyle(Palette.dimText)
        ProgressView(value: p.inTransition ? 0 : Swift.min(1, p.phaseElapsed / phase.sec))
          .tint(Palette.lampGlow)
          .frame(maxWidth: 240)
      } else {
        Text("まもなく始まります").font(AppFont.regular(17)).foregroundStyle(Color(hex: 0x9A9A9A))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// 一時停止(設計書 5.5 の 7):責めずに、続きをやる/休憩にする/今日はここまでにする
struct PausedScreen: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let runner = model.runner
    ZStack {
      PaperBackground()
      VStack(spacing: 18) {
        VStack(spacing: 10) {
          Image(systemName: "pause.circle").font(.system(size: 56)).foregroundStyle(Palette.green).accessibilityHidden(true)
          Text("ひと息ついてるね").font(AppFont.bold(28, relativeTo: .title))
          Text("ここまでの記録は、ちゃんと残っているよ").font(AppFont.regular(16)).foregroundStyle(Palette.subInk)
        }
        .padding(.top, 40)
        if let s = runner.pauseSummary {
          HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
              Text("机に向かった時間").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
              Text(Wording.minutes(s.studySec)).font(AppFont.bold(26))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
              Text("そのうち集中").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
              Text(Wording.minutes(s.effectiveFocusMin * 60)).font(AppFont.bold(26)).foregroundStyle(Palette.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
          .card()
        }
        if runner.pausedLong {
          Text("一時停止から10分たったよ。今日はここまでにする?")
            .font(AppFont.medium(16))
            .multilineTextAlignment(.center)
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(Palette.sticky, in: RoundedRectangle(cornerRadius: 8))
        }
        Spacer()
        Button("続きをやる") { runner.resume() }
          .buttonStyle(PrimaryButtonStyle(height: 76, fontSize: 25))
        Button("\(runner.pauseBreakMinutes)分休憩にする") { runner.breakFromPause() }
          .buttonStyle(OutlineButtonStyle(selected: true, height: 60))
        Button("今日はここまでにする") { model.finish() }
          .font(AppFont.regular(16))
          .foregroundStyle(Palette.subInk)
          .frame(maxWidth: .infinity, minHeight: 48)
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 24)
    }
    .foregroundStyle(Palette.ink)
  }
}

/// 休憩中(設計書 5.5 の 8):残り時間の輪と、休み方のヒントを 1 つずつ
struct BreakScreen: View {
  @Environment(AppModel.self) private var model

  static let tips: [(icon: String, title: String, detail: String)] = [
    ("eye", "窓の外を 20 秒ながめよう", "近くを見続けた目が、ひと休みできるよ"),
    ("drop", "水をひと口飲もう", "頭がすっきりして、また集中しやすくなるよ"),
    ("figure.cooldown", "肩をゆっくり回そう", "前かがみで固まった肩と背中がほぐれるよ"),
    ("wind", "深呼吸を 3 回しよう", "次の時間に向けて、気持ちを切り替えよう"),
  ]

  var body: some View {
    let runner = model.runner
    ZStack {
      Palette.breakBackground.ignoresSafeArea()
      VStack(spacing: 20) {
        VStack(spacing: 4) {
          Text("休憩中").font(AppFont.bold(26, relativeTo: .title))
          Text("カメラは止めているよ").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        }
        .padding(.top, 32)
        TimelineView(.periodic(from: Date(), by: 1)) { ctx in
          let remaining = Swift.max(0, runner.breakEndsAt.map { $0.timeIntervalSince(ctx.date) } ?? 0)
          let total = Swift.max(1, runner.breakTotalSec)
          let tip = Self.tips[Int(ctx.date.timeIntervalSinceReferenceDate / 20) % Self.tips.count]
          VStack(spacing: 20) {
            ZStack {
              RingView(progress: remaining / total, lineWidth: 16, color: Palette.focus, track: Palette.breakTrack)
              VStack(spacing: 2) {
                Text(String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60))
                  .font(AppFont.bold(46).monospacedDigit())
                Text(remaining > 0 ? "のこり" : "休憩おわり").font(AppFont.regular(15)).foregroundStyle(Palette.subInk)
              }
            }
            .frame(width: 230, height: 230)
            HStack(spacing: 14) {
              Image(systemName: tip.icon).font(.system(size: 30)).foregroundStyle(Palette.blue).frame(width: 44).accessibilityHidden(true)
              VStack(alignment: .leading, spacing: 4) {
                Text(tip.title).font(AppFont.bold(17))
                Text(tip.detail).font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
              }
            }
            .card()
          }
        }
        Spacer()
        Button("休憩を終えて机に戻る") { runner.endBreak() }
          .buttonStyle(PrimaryButtonStyle(height: 72, fontSize: 22))
        Button("今日はここまでにする") { model.finish() }
          .font(AppFont.regular(16))
          .foregroundStyle(Palette.subInk)
          .frame(maxWidth: .infinity, minHeight: 44)
      }
      .padding(.horizontal, 22)
      .padding(.bottom, 24)
    }
    .foregroundStyle(Palette.ink)
  }
}
