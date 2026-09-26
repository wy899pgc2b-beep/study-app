import StudyCore
import SwiftUI

/// 案内のしかた(声と音/消音)を選ぶカード。イヤホンをつけていなければ、周りに人がいるときの勧めを出す(決定事項 D-21)
struct SoundModeCard: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let mode = model.settings.soundMode
    VStack(alignment: .leading, spacing: 10) {
      Text("案内のしかた").font(AppFont.bold(17))
      HStack(spacing: 8) {
        ForEach(SoundMode.allCases, id: \.self) { m in
          Button {
            model.update { $0.soundMode = m }
            model.usage("sound_mode", ["value": m.rawValue])
          } label: {
            Label(m.label, systemImage: m.icon)
          }
          .buttonStyle(OutlineButtonStyle(selected: mode == m, height: 48))
          .accessibilityAddTraits(mode == m ? .isSelected : [])
        }
      }
      SoundAdvice(mode: mode, headphones: model.headphones)
    }
    .card()
  }
}

/// イヤホンの勧めと、消音モードの振動の意味
struct SoundAdvice: View {
  var mode: SoundMode
  var headphones: Bool

  var body: some View {
    Label {
      Text(text).font(AppFont.regular(14)).fixedSize(horizontal: false, vertical: true)
    } icon: {
      Image(systemName: mode == .vibrate ? mode.icon : "headphones")
    }
    .foregroundStyle(Palette.subInk)
  }

  private var text: String {
    switch mode {
    case .vibrate:
      "声と音は出さず、振動で知らせるよ。1 回:位置が合った(はじめは目を閉じてひと呼吸)。2 回:目を開けて教材を見る(うとうとしたときも)。3 回:休憩の始まりと終わり。長い振動:まだ位置が合っていない。長い 2 回:仮眠のおすすめ。机の上では、振動の音が少し聞こえることがあるよ"
    case .voice:
      headphones
        ? "イヤホンから聞こえるよ。居眠りのアラームは、耳にやさしい大きさまでにしているよ"
        : "声と音が出るよ。周りに人がいるときは、イヤホンをつけてね。つけられないときは「消音」にしよう"
    }
  }
}

extension SoundMode {
  var icon: String {
    switch self {
    case .voice: "speaker.wave.2"
    case .vibrate: "iphone.radiowaves.left.and.right"
    }
  }
}
