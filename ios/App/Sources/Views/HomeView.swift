import StudyCore
import SwiftUI

/// S-02 ホーム:大きな「始める」ボタンと、休憩タイマーのスイッチ(決定事項 D-9)
struct HomeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let settings = model.settings
    NavigationStack {
      Form {
        Section {
          Button {
            model.start()
          } label: {
            Text("始める")
              .font(.title.bold())
              .frame(maxWidth: .infinity, minHeight: 72)
          }
          .buttonStyle(.borderedProminent)
          .listRowInsets(EdgeInsets())
        }

        Section("休憩タイマー") {
          Toggle("休憩タイマーを使う", isOn: binding(\.breakTimer.enabled))
          if settings.breakTimer.enabled {
            HStack {
              ForEach(Array(BreakTimer.presets.enumerated()), id: \.offset) { _, preset in
                Button("\(preset.studyMin)分 + \(preset.breakMin)分") {
                  model.update { $0.breakTimer = preset }
                }
                .buttonStyle(.bordered)
                .tint(isSelected(preset) ? Color.accentColor : Color.secondary)
              }
            }
            Stepper(
              "学習 \(settings.breakTimer.studyMin) 分", value: binding(\.breakTimer.studyMin), in: BreakTimer.studyRange, step: 5)
            Stepper("休憩 \(settings.breakTimer.breakMin) 分", value: binding(\.breakTimer.breakMin), in: BreakTimer.breakRange)
          }
        }

        Section("置き方") {
          Picker("置き方", selection: binding(\.setup)) {
            Text("横向きに立てかける").tag(SetupStyle.landscape)
            Text("正面に立てる").tag(SetupStyle.stand)
          }
          .pickerStyle(.segmented)
        }

        Section {
          Text("カメラの映像は、この iPhone の中だけで解析します。保存も送信もしません。")
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
      }
      .navigationTitle("学習")
    }
  }

  private func isSelected(_ preset: BreakTimer) -> Bool {
    model.settings.breakTimer.studyMin == preset.studyMin && model.settings.breakTimer.breakMin == preset.breakMin
  }

  private func binding<V>(_ path: WritableKeyPath<StudySettings, V>) -> Binding<V> {
    Binding(
      get: { model.settings[keyPath: path] },
      set: { value in model.update { $0[keyPath: path] = value } }
    )
  }
}
