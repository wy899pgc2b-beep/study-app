import StudyCore
import SwiftUI

/// S-02 ホーム(設計書 5.5):あいさつ、今日の集中時間、今日の一手(付箋)、休憩タイマー、「机に向かう」、この 1 週間
struct HomeView: View {
  @Environment(AppModel.self) private var model
  @State private var customTimer = false
  @State private var showSettings = false
  @State private var showSubjectPicker = false
  /// 学習項目を選んだら、そのまま始める(初めての学習のとき)
  @State private var startAfterPick = false

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
          if settings.scenarioInvited && !model.scenarioPending.isEmpty {
            scenarioNote
          }
          breakTimerCard(settings)
          SoundModeCard()
          subjectRow
          Button {
            // 初めての学習では、学習項目を 1 つ選んでから始める(設計書 3.20 の要件 5)
            if model.settings.subject == nil {
              startAfterPick = true
              showSubjectPicker = true
            } else {
              model.beginFromHome()
            }
          } label: {
            Label("机に向かう", systemImage: "lamp.desk.fill")
          }
          .buttonStyle(PrimaryButtonStyle())
          if let level = SessionRunner.batteryLevel(), level <= 0.3, !SessionRunner.isCharging {
            Label("電池が残り \(Int((level * 100).rounded()))%。充電しながら使うと安心だよ", systemImage: "battery.25")
              .font(AppFont.regular(14))
              .foregroundStyle(Palette.lampText)
              .frame(maxWidth: .infinity)
          }
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
    .sheet(
      isPresented: $showSubjectPicker,
      onDismiss: {
        if startAfterPick {
          startAfterPick = false
          if model.settings.subject != nil { model.beginFromHome() }
        }
      }
    ) {
      SubjectPicker { name in
        model.chooseSubject(name)
        showSubjectPicker = false
      }
    }
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

  /// 検証モードを「あとで」にしたときの付箋(残りの場面だけ行える)
  private var scenarioNote: some View {
    let est = scenarioEstimate(model.scenarioPending)
    return StickyNote(
      title: "検証モードがまだです", text: "残り \(est.count) 場面(約 \(est.minutes) 分)。声の指示に合わせて行うよ。周りに人がいるときはイヤホンをつけてね", angle: 1
    ) {
      Button {
        model.startScenario()
      } label: {
        Label("検証モードを始める", systemImage: "checklist")
          .font(AppFont.bold(15))
          .foregroundStyle(Color(hex: 0x6B4A0C))
          .padding(.horizontal, 16)
          .frame(minHeight: 44)
          .background(Palette.stickyButton, in: RoundedRectangle(cornerRadius: 14))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x9A6A12), lineWidth: 2))
      }
    }
  }

  /// 学習項目(前回のものを引き継ぐ。変えるときだけ選び直す。設計書 3.1 の要件 1)
  private var subjectRow: some View {
    Button {
      showSubjectPicker = true
    } label: {
      HStack(spacing: 10) {
        Image(systemName: "book.closed").foregroundStyle(Palette.green).accessibilityHidden(true)
        Text("学習項目").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text(model.settings.subject ?? "まだ選んでいないよ")
          .font(model.settings.subject == nil ? AppFont.regular(16) : AppFont.bold(17))
          .foregroundStyle(model.settings.subject == nil ? Palette.subInk : Palette.ink)
          .lineLimit(1)
        Spacer(minLength: 8)
        Text("変更").font(AppFont.regular(14)).foregroundStyle(Palette.green)
      }
      .frame(minHeight: 28)
      .card(padding: 14)
    }
    .buttonStyle(.plain)
    .accessibilityLabel("学習項目 \(model.settings.subject ?? "まだ選んでいない")。変更する")
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
  @State private var askScenarioRange = false

  // 設定画面は、よく使う「基本」の項目を先に出し、ほかは「詳細設定」にまとめる(設計書の付録 A)
  var body: some View {
    NavigationStack {
      Form {
        Section("置き方") {
          Picker("置き方", selection: model.settingBinding(\.setup)) {
            Text("横向きに立てかける").tag(SetupStyle.landscape)
            Text("正面に立てる").tag(SetupStyle.stand)
          }
          .pickerStyle(.segmented)
        }
        Section {
          Picker("案内のしかた", selection: model.settingBinding(\.soundMode)) {
            ForEach(SoundMode.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          HStack {
            Image(systemName: "speaker.wave.1").foregroundStyle(Palette.subInk).accessibilityHidden(true)
            Slider(value: model.settingBinding(\.volume), in: 0...1, step: 0.05)
              .tint(Palette.green)
              .accessibilityLabel("音量")
              .accessibilityValue("\(Int((model.settings.volume * 100).rounded()))")
            Text("\(Int((model.settings.volume * 100).rounded()))").monospacedDigit().frame(width: 36, alignment: .trailing)
          }
        } header: {
          Text("案内と音")
        } footer: {
          Text("居眠りのアラームは起こすための音なので、音量を下げても、ある程度の大きさで鳴ります")
        }
        Section {
          Picker("居眠りのとき", selection: model.settingBinding(\.sleepAlarm)) {
            Text("アラームで起こす").tag(true)
            Text("記録だけ").tag(false)
          }
          Toggle("眠気が続くときに、仮眠を勧める", isOn: model.settingBinding(\.napSuggest)).tint(Palette.green)
        } header: {
          Text("居眠り")
        } footer: {
          Text("うとうと・居眠りが 20 分のうちに 3 回あったら、20 分ほどの仮眠を勧めます。仮眠の終わりには起こします")
        }
        Section("学年") {
          Picker("学年", selection: model.settingBinding(\.grade)) {
            Text("選ばない").tag(Grade?.none)
            ForEach(Grade.allCases) { Text($0.label).tag(Grade?.some($0)) }
          }
        }
        Section {
          NavigationLink("詳細設定") { DetailSettingsView() }
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
            let pending = model.scenarioPending.count
            if pending > 0 && pending < Scenario.phases.count {
              askScenarioRange = true
            } else {
              dismiss()
              model.startScenario()
            }
          } label: {
            Label("検証モードを始める", systemImage: "checklist")
          }
          .confirmationDialog("どの場面を行う?", isPresented: $askScenarioRange, titleVisibility: .visible) {
            Button("残りの \(model.scenarioPending.count) 場面") {
              dismiss()
              model.startScenario(onlyPending: true)
            }
            Button("\(Scenario.phases.count) 場面すべて") {
              dismiss()
              model.startScenario(onlyPending: false)
            }
            Button("やめる", role: .cancel) {}
          }
        } header: {
          Text("記録と検証")
        } footer: {
          Text(
            exportFailed
              ? "記録を書き出せませんでした"
              : "書き出す記録は、学習の時間・回数・集中度だけです。映像・画像・顔の特徴点は含まれません。検証モードは、声の指示に合わせて 9 つの場面(約 5 分)を行い、判定が合っているかを確かめます。学習の記録には入りません。済んだ場面 \(Scenario.phases.count - model.scenarioPending.count) / \(Scenario.phases.count)"
          )
        }
      }
      .navigationTitle("設定")
      .toolbar { Button("閉じる") { dismiss() } }
    }
  }
}

/// 詳細設定(設計書の付録 A)。判定の細かい値は、既定では技術検証で決めた値のまま
struct DetailSettingsView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    Form {
      Section("置く前") {
        Toggle("置く前の説明を省く", isOn: model.settingBinding(\.skipPlacementIntro)).tint(Palette.green)
      }
      Section {
        Stepper(value: model.settingBinding(\.eyeDeskCm), in: 20...60, step: 1) {
          Text("目と教材の距離 \(Int(model.settings.eyeDeskCm)) cm")
        }
        Stepper(value: closePercent, in: 15...40, step: 5) {
          Text("「近すぎ」と判定する近づき方 \(closePercent.wrappedValue)%")
        }
      } header: {
        Text("姿勢")
      } footer: {
        Text("ふだんの距離より、この割合以上近づいた状態が 20 秒続くと、声で知らせます(既定は 25%)")
      }
      Section {
        Stepper(value: model.settingBinding(\.awaySec), in: 10...60, step: 5) {
          Text("離席と判定するまで \(Int(model.settings.awaySec)) 秒")
        }
      } header: {
        Text("離席")
      } footer: {
        Text("カメラに映らない時間がこの長さになったら、離席として記録します(既定は 20 秒)。検証モードでは、いつも既定の値で判定します")
      }
    }
    .navigationTitle("詳細設定")
  }

  /// 「近すぎ」の割合を、% の整数で扱う
  private var closePercent: Binding<Int> {
    Binding(
      get: { Int((model.settings.closeRatio * 100).rounded()) },
      set: { v in model.update { $0.closeRatio = Double(v) / 100 } }
    )
  }
}

extension AppModel {
  /// 設定の 1 項目を、画面の部品につなぐ
  func settingBinding<V>(_ path: WritableKeyPath<StudySettings, V>) -> Binding<V> {
    Binding(
      get: { self.settings[keyPath: path] },
      set: { value in self.update { $0[keyPath: path] = value } }
    )
  }
}
