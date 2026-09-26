import StudyCore
import SwiftUI

/// S-02 ホーム(設計書 5.5):あいさつ、今日の集中時間、今日の一手(付箋)、休憩タイマー、「机に向かう」、この 1 週間
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var customTimer = false
  @State private var showSettings = false

  var body: some View {
    let settings = model.settings
    ZStack {
      PaperBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          header
          todayCard
          if let step = model.pinnedNextStep {
            StickyNote(title: "今日の一手(前回の結果から)", text: step)
          }
          breakTimerCard(settings)
          Button {
            model.beginFromHome()
          } label: {
            Label("机に向かう", systemImage: "lamp.desk.fill")
          }
          .buttonStyle(PrimaryButtonStyle())
          weekBars
          Label("映像はこの iPhone の中だけで解析します", systemImage: "lock")
            .font(AppFont.regular(13, relativeTo: .footnote))
            .foregroundStyle(Palette.subInk)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
      }
    }
    .foregroundStyle(Palette.ink)
    .sheet(isPresented: $showSettings) { SettingsSheet() }
  }

  private var header: some View {
    HStack(alignment: .bottom) {
      VStack(alignment: .leading, spacing: 2) {
        Text(Wording.day()).font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text(Wording.greeting()).font(AppFont.bold(26, relativeTo: .title))
      }
      Spacer()
      Button {
        showSettings = true
      } label: {
        Image(systemName: "gearshape").font(.title3).foregroundStyle(Palette.subInk).frame(width: 44, height: 44)
      }
      .accessibilityLabel("設定")
      Image(systemName: "lamp.desk").font(.system(size: 30)).foregroundStyle(Palette.lamp).accessibilityHidden(true)
    }
  }

  private var todayCard: some View {
    let focusMin = model.today?.focusMin ?? 0
    let studySec = model.today?.studySec ?? 0
    let ratio = studySec > 0 ? focusMin * 60 / studySec : 0
    return HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text("今日の集中時間").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text(Wording.minutes(focusMin * 60)).font(AppFont.bold(34, relativeTo: .largeTitle))
        Text(studySec > 0 ? "机に向かった時間 \(Wording.minutes(studySec))" : "今日の最初の 1 回を始めよう")
          .font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      }
      Spacer()
      RingView(progress: ratio, label: studySec > 0 ? "\(Int((ratio * 100).rounded()))%" : nil)
        .frame(width: 76, height: 76)
        .accessibilityLabel("集中の割合 \(Int((ratio * 100).rounded()))%")
    }
    .card()
  }

  private func breakTimerCard(_ settings: StudySettings) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Toggle(isOn: binding(\.breakTimer.enabled)) {
        Text("休憩タイマー").font(AppFont.bold(17))
      }
      .tint(Palette.green)
      if settings.breakTimer.enabled {
        HStack(spacing: 8) {
          ForEach(Array(BreakTimer.presets.enumerated()), id: \.offset) { _, preset in
            Button("\(preset.studyMin)分 + \(preset.breakMin)分") {
              customTimer = false
              model.update { $0.breakTimer = preset }
            }
            .buttonStyle(OutlineButtonStyle(selected: !customTimer && isPreset(preset), height: 48))
          }
          Button("自由") { customTimer = true }
            .buttonStyle(OutlineButtonStyle(selected: customTimer || !isAnyPreset, height: 48))
            .frame(width: 72)
        }
        if customTimer || !isAnyPreset {
          Stepper(value: binding(\.breakTimer.studyMin), in: BreakTimer.studyRange, step: 5) {
            Text("学習 \(settings.breakTimer.studyMin) 分").font(AppFont.regular(16))
          }
          Stepper(value: binding(\.breakTimer.breakMin), in: BreakTimer.breakRange) {
            Text("休憩 \(settings.breakTimer.breakMin) 分").font(AppFont.regular(16))
          }
        }
      }
    }
    .card()
  }

  private var weekBars: some View {
    let week = model.week
    let maxMin = Swift.max(30, week.map(\.focusMin).max() ?? 0)
    return VStack(alignment: .leading, spacing: 8) {
      Text("この1週間(集中時間)").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
      HStack(alignment: .bottom, spacing: 10) {
        ForEach(Array(week.enumerated()), id: \.offset) { i, day in
          let isToday = i == week.count - 1
          VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 6)
              .fill(day.focusMin > 0 ? (isToday ? Palette.lamp : Palette.barSoft) : Palette.cardEdge)
              .frame(height: Swift.max(6, 76 * day.focusMin / maxMin))
            Text(Wording.weekday(day.studyDate))
              .font(isToday ? AppFont.bold(13) : AppFont.regular(13))
              .foregroundStyle(isToday ? Palette.lampText : Palette.subInk)
          }
          .frame(maxWidth: .infinity)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel("\(Wording.weekday(day.studyDate))曜日 \(Int(day.focusMin.rounded()))分")
        }
      }
      .frame(height: 100, alignment: .bottom)
    }
  }

  private var isAnyPreset: Bool { BreakTimer.presets.contains { isPreset($0) } }

  private func isPreset(_ preset: BreakTimer) -> Bool {
    model.settings.breakTimer.studyMin == preset.studyMin && model.settings.breakTimer.breakMin == preset.breakMin
  }

  private func binding<V>(_ path: WritableKeyPath<StudySettings, V>) -> Binding<V> {
    Binding(
      get: { model.settings[keyPath: path] },
      set: { value in model.update { $0[keyPath: path] = value } }
    )
  }
}

/// 設定(S-15 の基本の項目)
struct SettingsSheet: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State private var exportURL: URL?
  @State private var exportFailed = false

  var body: some View {
    NavigationStack {
      Form {
        Section("置き方") {
          Picker("置き方", selection: binding(\.setup)) {
            Text("横向きに立てかける").tag(SetupStyle.landscape)
            Text("正面に立てる").tag(SetupStyle.stand)
          }
          .pickerStyle(.segmented)
          Toggle("置く前の説明を省く", isOn: binding(\.skipPlacementIntro)).tint(Palette.green)
        }
        Section {
          Stepper(value: binding(\.eyeDeskCm), in: 20...60, step: 1) {
            Text("目と教材の距離 \(Int(model.settings.eyeDeskCm)) cm")
          }
        } footer: {
          Text("ふだんの距離より近づいたときに、声で知らせます")
        }
        Section("学年") {
          Picker("学年", selection: binding(\.grade)) {
            Text("選ばない").tag(Grade?.none)
            ForEach(Grade.allCases) { Text($0.label).tag(Grade?.some($0)) }
          }
        }
        Section {
          if let url = exportURL {
            ShareLink(item: url) { Label("書き出した記録を送る", systemImage: "square.and.arrow.up") }
          } else {
            Button {
              exportURL = model.exportRecords()
              exportFailed = exportURL == nil
            } label: {
              Label("記録を書き出す", systemImage: "doc.text")
            }
          }
          Button {
            dismiss()
            model.startScenario()
          } label: {
            Label("検証モードを始める", systemImage: "checklist")
          }
        } header: {
          Text("記録と検証")
        } footer: {
          Text(
            exportFailed
              ? "記録を書き出せませんでした"
              : "書き出す記録は、学習の時間・回数・集中度だけです。映像・画像・顔の特徴点は含まれません。検証モードは、声の指示に合わせて 9 つの場面(約 5 分)を行い、判定が合っているかを確かめます。学習の記録には入りません"
          )
        }
      }
      .navigationTitle("設定")
      .toolbar { Button("閉じる") { dismiss() } }
    }
  }

  private func binding<V>(_ path: WritableKeyPath<StudySettings, V>) -> Binding<V> {
    Binding(
      get: { model.settings[keyPath: path] },
      set: { value in model.update { $0[keyPath: path] = value } }
    )
  }
}
