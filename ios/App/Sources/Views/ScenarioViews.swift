import StudyCore
import SwiftUI

/// 検証モードの残りの場面の数と、かかる分(ホームの付箋と、勧める画面に出す)
func scenarioEstimate(_ phases: [Int]) -> (count: Int, minutes: Int) {
  let sec = phases.reduce(0.0) { $0 + Scenario.transitionSec + Scenario.phases[$1].sec }
  return (phases.count, Int((sec / 60).rounded(.up)))
}

/// オンボーディングの後に、検証モードを勧める(「あとで」にすると、ホームに付箋を残す)
struct ScenarioInviteView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let est = scenarioEstimate(model.scenarioPending)
    ZStack {
      PaperBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          VStack(alignment: .leading, spacing: 4) {
            Text("はじめに、ひとつお願い").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
            Text("検証モードで、判定を確かめよう").font(AppFont.bold(26, relativeTo: .title)).fixedSize(horizontal: false, vertical: true)
          }
          VStack(alignment: .leading, spacing: 10) {
            row("list.number", "声の指示に合わせて、読む・書く・目を閉じる・居眠りのまね・よそ見・離席など \(est.count) つの場面を行うよ(約 \(est.minutes) 分)")
            row("checkmark.seal", "判定が合っているかを確かめるためのもので、学習の記録には入らないよ")
            row("forward", "いまはできない場面(離席や机に伏せるなど)は、画面に触れると飛ばせるよ。飛ばした場面は、あとで行えるよ")
          }
          .card()
          SoundAdvice(mode: .voice, headphones: model.headphones)
            .padding(.horizontal, 4)
          Button("検証モードを始める") { model.startScenario() }
            .buttonStyle(PrimaryButtonStyle(height: 68, fontSize: 22))
          Button("あとで") { model.postponeScenario() }
            .font(AppFont.regular(16))
            .foregroundStyle(Palette.green)
            .frame(maxWidth: .infinity, minHeight: 44)
          Text("「あとで」にすると、ホームに付箋を貼っておくよ")
            .font(AppFont.regular(13)).foregroundStyle(Palette.subInk).frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
      }
    }
    .foregroundStyle(Palette.ink)
    .onAppear { model.usage("scenario_invite_view") }
  }

  private func row(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: icon).foregroundStyle(Palette.green).frame(width: 22).accessibilityHidden(true)
      Text(text).font(AppFont.regular(15)).fixedSize(horizontal: false, vertical: true)
    }
  }
}
