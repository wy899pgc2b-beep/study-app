import StudyCore
import SwiftUI

// 画面の見た目(設計書 5.5、決定事項 D-20):「机と日誌」の雰囲気。方眼ノートの背景、付箋、机のランプの印。
// 丸みのある文字(Zen Maru Gothic。入っていなければ端末の文字)。下がったところや居眠りを赤で目立たせない。

extension Color {
  init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
  }
}

enum Palette {
  static let paper = Color(hex: 0xF7F3EA)
  static let gridLine = Color(hex: 0xECE5D6)
  static let ink = Color(hex: 0x22303C)
  static let subInk = Color(hex: 0x4B5560)
  static let green = Color(hex: 0x2F6B5A)
  static let greenDark = Color(hex: 0x1F4F42)
  static let greenSoft = Color(hex: 0xE7F1EC)
  static let focus = Color(hex: 0x3E8A6E)
  static let focusTrack = Color(hex: 0xE7EFEA)
  static let focusFill = Color(hex: 0xDCEBE3)
  static let barSoft = Color(hex: 0x9CC7B4)
  static let lamp = Color(hex: 0xC9791E)
  static let lampGlow = Color(hex: 0xE9B868)
  static let lampText = Color(hex: 0x8A4F0C)
  static let sticky = Color(hex: 0xFBE9A6)
  static let stickyText = Color(hex: 0x6B5A1E)
  static let stickyButton = Color(hex: 0xFFF6D6)
  static let tape = Color(hex: 0xF1D98B)
  static let line = Color(hex: 0xD6D0C2)
  static let cardEdge = Color(hex: 0xE3DCCB)
  static let breakBackground = Color(hex: 0xEAF3EE)
  static let breakTrack = Color(hex: 0xD3E5DB)
  static let blue = Color(hex: 0x3E6FB0)
  static let dimText = Color(hex: 0x8A8A8A)
}

enum AppFont {
  static func regular(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
    .custom("ZenMaruGothic-Regular", size: size, relativeTo: style)
  }

  static func medium(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
    .custom("ZenMaruGothic-Medium", size: size, relativeTo: style)
  }

  static func bold(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
    .custom("ZenMaruGothic-Bold", size: size, relativeTo: style)
  }
}

/// 方眼ノートの背景
struct PaperBackground: View {
  var body: some View {
    Canvas { ctx, size in
      let step: CGFloat = 22
      var path = Path()
      var x: CGFloat = 0
      while x <= size.width {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x, y: size.height))
        x += step
      }
      var y: CGFloat = 0
      while y <= size.height {
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        y += step
      }
      ctx.stroke(path, with: .color(Palette.gridLine), lineWidth: 1)
    }
    .background(Palette.paper)
    .ignoresSafeArea()
  }
}

extension View {
  /// 白いカード
  func card(padding: CGFloat = 18) -> some View {
    self.padding(padding)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
      .shadow(color: Palette.cardEdge, radius: 0, x: 0, y: 1)
  }
}

/// 付箋(「今日の一手」「明日の一手」)
struct StickyNote<Footer: View>: View {
  var title: String
  var text: String
  var angle: Double = -1.2
  @ViewBuilder var footer: () -> Footer

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: "pin.fill")
        .font(AppFont.bold(13, relativeTo: .caption))
        .foregroundStyle(Palette.stickyText)
      Text(text)
        .font(AppFont.medium(17))
        .foregroundStyle(Palette.ink)
        .lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
      footer()
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.sticky, in: RoundedRectangle(cornerRadius: 6))
    .shadow(color: Color(hex: 0x78601E).opacity(0.14), radius: 6, x: 0, y: 6)
    .rotationEffect(.degrees(angle))
  }
}

extension StickyNote where Footer == EmptyView {
  init(title: String, text: String, angle: Double = -1.2) {
    self.init(title: title, text: text, angle: angle) { EmptyView() }
  }
}

/// 割合の輪
struct RingView: View {
  var progress: Double
  var lineWidth: CGFloat = 10
  var color: Color = Palette.focus
  var track: Color = Palette.focusTrack
  var label: String?

  var body: some View {
    ZStack {
      Circle().stroke(track, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: Swift.max(0, Swift.min(1, progress)))
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
      if let label {
        Text(label).font(AppFont.bold(15)).foregroundStyle(Palette.ink)
      }
    }
    .padding(lineWidth / 2)
  }
}

/// 1 分ごとの集中度を、なだらかな線で見せる(「集中の波」)。評価できなかった分は飛ばす
struct WaveChart: View {
  var scores: [Int?]

  var body: some View {
    GeometryReader { geo in
      let pts = points(in: geo.size)
      ZStack {
        if pts.count >= 2 {
          area(pts, height: geo.size.height).fill(Palette.focusFill)
          curve(pts).stroke(Palette.focus, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        Path { p in
          p.move(to: CGPoint(x: 0, y: geo.size.height))
          p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
        }
        .stroke(Palette.line, lineWidth: 1.5)
      }
    }
    .accessibilityLabel("1分ごとの集中度の変化")
  }

  private func points(in size: CGSize) -> [CGPoint] {
    let n = scores.count
    guard n >= 2 else { return [] }
    return scores.enumerated().compactMap { i, v in
      guard let v else { return nil }
      let x = size.width * CGFloat(i) / CGFloat(n - 1)
      let y = size.height * (1 - CGFloat(v) / 100) * 0.9 + size.height * 0.05
      return CGPoint(x: x, y: y)
    }
  }

  private func curve(_ pts: [CGPoint]) -> Path {
    var p = Path()
    p.move(to: pts[0])
    for i in 1..<pts.count {
      let mid = CGPoint(x: (pts[i - 1].x + pts[i].x) / 2, y: (pts[i - 1].y + pts[i].y) / 2)
      p.addQuadCurve(to: mid, control: pts[i - 1])
    }
    p.addLine(to: pts[pts.count - 1])
    return p
  }

  private func area(_ pts: [CGPoint], height: CGFloat) -> Path {
    var p = curve(pts)
    p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: height))
    p.addLine(to: CGPoint(x: pts[0].x, y: height))
    p.closeSubpath()
    return p
  }
}

/// 体感の顔(集中できた・ふつう・いまいち)
struct FaceIcon: View {
  var rating: SelfRating
  var color: Color

  var body: some View {
    Canvas { ctx, size in
      let w = size.width
      let r = w / 2 - 2
      let c = CGPoint(x: w / 2, y: w / 2)
      ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 2.4)
      for dx in [-0.3, 0.3] {
        let e = CGRect(x: c.x + dx * w - 1.8, y: c.y - 0.18 * w - 1.8, width: 3.6, height: 3.6)
        ctx.fill(Path(ellipseIn: e), with: .color(color))
      }
      var mouth = Path()
      let y = c.y + 0.16 * w
      switch rating {
      case .good:
        mouth.move(to: CGPoint(x: c.x - 0.18 * w, y: y - 0.03 * w))
        mouth.addQuadCurve(to: CGPoint(x: c.x + 0.18 * w, y: y - 0.03 * w), control: CGPoint(x: c.x, y: y + 0.14 * w))
      case .normal:
        mouth.move(to: CGPoint(x: c.x - 0.17 * w, y: y))
        mouth.addLine(to: CGPoint(x: c.x + 0.17 * w, y: y))
      case .poor:
        mouth.move(to: CGPoint(x: c.x - 0.17 * w, y: y + 0.06 * w))
        mouth.addQuadCurve(to: CGPoint(x: c.x + 0.17 * w, y: y + 0.06 * w), control: CGPoint(x: c.x, y: y - 0.08 * w))
      }
      ctx.stroke(mouth, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
    }
    .accessibilityHidden(true)
  }
}

/// 大きな緑のボタン(「机に向かう」など)
struct PrimaryButtonStyle: ButtonStyle {
  var height: CGFloat = 76
  var fontSize: CGFloat = 26

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(AppFont.bold(fontSize, relativeTo: .title2))
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: height)
      .background(Palette.green, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
      .shadow(color: Palette.greenDark, radius: 0, x: 0, y: configuration.isPressed ? 2 : 6)
      .offset(y: configuration.isPressed ? 4 : 0)
  }
}

/// 枠だけのボタン
struct OutlineButtonStyle: ButtonStyle {
  var selected = true
  var height: CGFloat = 56

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(selected ? AppFont.bold(17) : AppFont.regular(17))
      .foregroundStyle(selected ? Palette.greenDark : Palette.ink)
      .frame(maxWidth: .infinity, minHeight: height)
      .background(selected ? Palette.greenSoft : Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Palette.green : Palette.line, lineWidth: 2))
      .opacity(configuration.isPressed ? 0.7 : 1)
  }
}

enum Wording {
  /// 時間帯のあいさつ
  static func greeting(_ date: Date = Date()) -> String {
    let h = Calendar.current.component(.hour, from: date)
    switch h {
    case 4..<11: return "おはよう"
    case 11..<17: return "こんにちは"
    default: return "こんばんは"
    }
  }

  /// 9月26日(土)
  static func day(_ date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "M月d日(E)"
    return f.string(from: date)
  }

  static func clock(_ date: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "H:mm"
    return f.string(from: date)
  }

  /// 1時間5分 / 48分
  static func minutes(_ sec: Double) -> String {
    let m = Int((sec / 60).rounded())
    return m >= 60 ? "\(m / 60)時間\(m % 60)分" : "\(m)分"
  }

  /// 曜日の 1 文字
  static func weekday(_ studyDate: String) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ja_JP")
    f.dateFormat = "yyyy-MM-dd"
    guard let d = f.date(from: studyDate) else { return "" }
    f.dateFormat = "E"
    return f.string(from: d)
  }
}
