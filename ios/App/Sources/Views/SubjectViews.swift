import StudyCore
import SwiftUI

/// 学習項目を選ぶ(前回 → よく使う順 → 自分で足したもの → よく使う教科)。自分で入力して足せる。自分で足したものは長押しで消せる
struct SubjectPicker: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  var onPick: (String) -> Void
  @State private var newName = ""

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("前回のものを次も引き継ぐよ。変えるときだけ選んでね")
            .font(AppFont.regular(15)).foregroundStyle(Palette.subInk)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(model.subjectChoices, id: \.self) { name in
              Button(name) { onPick(name) }
                .buttonStyle(OutlineButtonStyle(selected: model.settings.subject == name, height: 50))
                .contextMenu {
                  if model.settings.customSubjects.contains(name) {
                    Button("この項目を消す", role: .destructive) { model.removeCustomSubject(name) }
                  }
                }
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            Text("自分で入力する").font(AppFont.bold(15))
            HStack(spacing: 10) {
              TextField("例:世界史、単語帳", text: $newName)
                .font(AppFont.regular(17))
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Palette.line, lineWidth: 2))
                .submitLabel(.done)
                .onSubmit(add)
              Button("決める", action: add)
                .buttonStyle(OutlineButtonStyle(selected: true, height: 50))
                .frame(width: 96)
                .disabled(Subjects.normalize(newName) == nil)
            }
          }
        }
        .padding(20)
      }
      .background(PaperBackground())
      .foregroundStyle(Palette.ink)
      .navigationTitle("何を勉強する?")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("閉じる") { dismiss() } }
    }
  }

  private func add() {
    guard let name = Subjects.normalize(newName) else { return }
    onPick(name)
  }
}
