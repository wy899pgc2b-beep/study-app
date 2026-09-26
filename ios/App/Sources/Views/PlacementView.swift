import StudyCore
import SwiftUI

/// 置く前の説明(設計書 5.5 の 5):置くと画面が見えないので、置く前に 1 回だけ、置き方の絵と手順を見せる
struct PlacementView: View {
  @Environment(AppModel.self) private var model

  private var steps: [String] {
    model.settings.setup == .landscape
      ? [
        "スマホを横向きにして、カメラをこちらに向ける", "本などに立てかけて、少しだけ後ろに傾ける(15°くらい)", "胸から60cmくらい離す(ノート2冊分)",
        "ペンを持った手を、書くときの位置に置く",
      ]
      : ["スマホを縦向きにして、机の奥に立てる", "カメラをこちらに向ける", "顔と肩が映る距離に置く"]
  }

  var body: some View {
    ZStack {
      PaperBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text("置く前に 1 回だけ見てね").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
            Text("こう置くと、よく見えるよ").font(AppFont.bold(26, relativeTo: .title))
          }
          if model.settings.setup == .landscape {
            PlacementIllustration()
              .frame(height: 220)
              .card(padding: 8)
              .accessibilityElement(children: .ignore)
              .accessibilityLabel("横から見た置き方。胸から約60センチ、スマホを横向きにして約15度後ろに傾ける")
          }
          VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, text in
              HStack(spacing: 12) {
                Text("\(i + 1)")
                  .font(AppFont.bold(16))
                  .foregroundStyle(.white)
                  .frame(width: 30, height: 30)
                  .background(Palette.green, in: Circle())
                Text(text).font(AppFont.regular(16)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 12)
              .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
          }
          if model.settings.soundMode == .voice {
            Label("置いたあとは画面を見なくて大丈夫。ずれているところは、声で教えるね", systemImage: "speaker.wave.2")
              .font(AppFont.regular(14))
              .foregroundStyle(Palette.subInk)
          }
          SoundAdvice(mode: model.settings.soundMode, headphones: model.headphones)
          Button("置いたよ") { model.start() }
            .buttonStyle(PrimaryButtonStyle(height: 72, fontSize: 24))
          Button("次からはこの説明を省く") {
            model.update { $0.skipPlacementIntro = true }
            model.start()
          }
          .font(AppFont.regular(15))
          .foregroundStyle(Palette.green)
          .frame(maxWidth: .infinity, minHeight: 44)
          Button("ホームに戻る") { model.backHome() }
            .font(AppFont.regular(15))
            .foregroundStyle(Palette.subInk)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
      }
    }
    .foregroundStyle(Palette.ink)
  }
}

/// 横から見た置き方の絵(胸から約 60cm、横向きのスマホを約 15° 後ろに傾けて、本に立てかける)
struct PlacementIllustration: View {
  var body: some View {
    Canvas { ctx, size in
      // 330×220 の絵を、枠の大きさに合わせて縮める
      let s = Swift.min(size.width / 330, size.height / 220)
      ctx.translateBy(x: (size.width - 330 * s) / 2, y: (size.height - 220 * s) / 2)
      ctx.scaleBy(x: s, y: s)
      let ink = GraphicsContext.Shading.color(Palette.ink)
      let wood = GraphicsContext.Shading.color(Color(hex: 0xB08A5A))
      let round = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)

      // 机
      var desk = Path()
      desk.move(to: CGPoint(x: 8, y: 182))
      desk.addLine(to: CGPoint(x: 322, y: 182))
      desk.move(to: CGPoint(x: 40, y: 182))
      desk.addLine(to: CGPoint(x: 40, y: 212))
      desk.move(to: CGPoint(x: 300, y: 182))
      desk.addLine(to: CGPoint(x: 300, y: 212))
      ctx.stroke(desk, with: wood, style: StrokeStyle(lineWidth: 4, lineCap: .round))

      // 人(頭、背中、腕)
      ctx.stroke(Path(ellipseIn: CGRect(x: 42, y: 38, width: 40, height: 40)), with: ink, style: round)
      var body = Path()
      body.move(to: CGPoint(x: 38, y: 176))
      body.addCurve(to: CGPoint(x: 62, y: 88), control1: CGPoint(x: 38, y: 136), control2: CGPoint(x: 42, y: 104))
      body.addCurve(to: CGPoint(x: 100, y: 110), control1: CGPoint(x: 82, y: 72), control2: CGPoint(x: 94, y: 92))
      body.move(to: CGPoint(x: 98, y: 112))
      body.addLine(to: CGPoint(x: 136, y: 152))
      body.addLine(to: CGPoint(x: 162, y: 178))
      ctx.stroke(body, with: ink, style: round)
      // ペン
      var pen = Path()
      pen.move(to: CGPoint(x: 150, y: 178))
      pen.addLine(to: CGPoint(x: 190, y: 174))
      ctx.stroke(pen, with: .color(Palette.green), style: round)

      // 本とスマホ(約 15° 後ろに傾ける)
      let book = Path(roundedRect: CGRect(x: 276, y: 150, width: 30, height: 32), cornerRadius: 3)
      ctx.fill(book, with: .color(Color(hex: 0xE7DCC8)))
      ctx.stroke(book, with: wood, lineWidth: 2)
      var phoneCtx = ctx
      phoneCtx.translateBy(x: 268, y: 181)
      phoneCtx.rotate(by: .degrees(15))
      let phone = Path(roundedRect: CGRect(x: -6, y: -73, width: 12, height: 74), cornerRadius: 4)
      phoneCtx.fill(phone, with: .color(.white))
      phoneCtx.stroke(phone, with: ink, lineWidth: 3)
      phoneCtx.fill(Path(ellipseIn: CGRect(x: -9, y: -66, width: 6, height: 6)), with: .color(Palette.lamp))

      // 距離(約 60cm)
      var dist = Path()
      dist.move(to: CGPoint(x: 104, y: 96))
      dist.addLine(to: CGPoint(x: 244, y: 96))
      ctx.stroke(dist, with: .color(Palette.lamp), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, dash: [6, 6]))
      var head = Path()
      head.move(to: CGPoint(x: 238, y: 90))
      head.addLine(to: CGPoint(x: 246, y: 96))
      head.addLine(to: CGPoint(x: 238, y: 102))
      ctx.stroke(head, with: .color(Palette.lamp), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
      ctx.draw(Text("約60cm").font(AppFont.bold(15)).foregroundColor(Palette.lampText), at: CGPoint(x: 174, y: 80))

      // 傾き(約 15°)
      var up = Path()
      up.move(to: CGPoint(x: 268, y: 181))
      up.addLine(to: CGPoint(x: 268, y: 138))
      ctx.stroke(up, with: .color(Palette.blue), style: StrokeStyle(lineWidth: 1.6, dash: [3, 4]))
      ctx.draw(Text("15°").font(AppFont.bold(15)).foregroundColor(Color(hex: 0x2E5588)), at: CGPoint(x: 296, y: 124))
    }
  }
}
