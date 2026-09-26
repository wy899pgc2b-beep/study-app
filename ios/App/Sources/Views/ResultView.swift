import StudyCore
import SwiftUI

/// S-08 学習結果:結果カード(褒め言葉を先に、集中時間はその後)と時間の内訳(設計書 3.14)
struct ResultView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    NavigationStack {
      List {
        if let s = model.runner.summary {
          if let card = model.runner.card {
            // 褒め言葉を先に、集中時間はその後に(設計書 3.14)
            Section {
              Text(card.praise).font(.title2.bold())
              LabeledContent("集中時間", value: minutes(card.focusMin * 60))
              LabeledContent("平均集中度", value: card.avgFocus.map { "\($0)%" } ?? "—")
              LabeledContent("学習時間", value: minutes(card.studyMin * 60)).font(.footnote)
              Text(card.nextStep)
            }
          }
          Section("時間の内訳") {
            LabeledContent("学習", value: minutes(s.studySec))
            LabeledContent("離席", value: minutes(s.awaySec))
            LabeledContent("一時停止", value: minutes(s.pausedSec))
          }
        } else {
          Text("計測を始める前に終了しました")
        }
        Button("ホームに戻る") { model.backHome() }
      }
      .navigationTitle("結果")
    }
  }

  private func minutes(_ sec: Double) -> String {
    let m = Int((sec / 60).rounded())
    return m >= 60 ? "\(m / 60)時間\(m % 60)分" : "\(m)分"
  }
}
