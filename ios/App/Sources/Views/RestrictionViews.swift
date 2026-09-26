import FamilyControls
import RestrictionCore
import SwiftUI

/// スマホ制限(裏機能。決定事項 D-24、設計書 3.30)。ホームの下の小さな入口から開く
struct RestrictionView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    let r = model.restriction
    NavigationStack {
      Group {
        if !r.available {
          RestrictionUnavailableView()
        } else if !r.authorized {
          RestrictionAuthorizeView()
        } else {
          RestrictionForm()
        }
      }
      .navigationTitle("スマホ制限")
      .toolbar { Button("閉じる") { dismiss() } }
    }
    .tint(Palette.green)
    .onAppear { r.refresh() }
  }
}

/// できること(許可を得る前にも見せる)
private struct RestrictionFeatureList: View {
  static let items: [(icon: String, title: String, detail: String)] = [
    ("timer", "集中セッション", "決めた時間だけ、選んだアプリを開けなくする"),
    ("lamp.desk", "学習と連動", "机に向かっている間は、自動で制限する"),
    ("calendar", "時間割", "曜日と時刻を決めて、毎週くり返す"),
    ("hourglass", "1 日の時間制限", "使い切ったら、あしたまで開けない"),
    ("hand.tap", "開く回数の制限", "1 日に開ける回数を決める"),
    ("dial.medium", "3 段階の厳しさ", "ふつう・タイムアウト・ディープフォーカス"),
  ]

  var body: some View {
    ForEach(Self.items, id: \.title) { item in
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text(item.title).font(AppFont.bold(16))
          Text(item.detail).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
        }
      } icon: {
        Image(systemName: item.icon).foregroundStyle(Palette.green)
      }
    }
  }
}

private let privacyNote = "選んだアプリや使った時間は、Apple のスクリーンタイムの仕組みの中だけで扱われます。ツクエログにも、学校や家族などほかの人にもわかりません"

/// ホームのいちばん下の小さな入口。プリセット(はじめは 1時間半)をワンタップで始められる(D-25)
struct RestrictionHomeRow: View {
  @Environment(AppModel.self) private var model
  var open: () -> Void

  var body: some View {
    let r = model.restriction
    HStack(spacing: 10) {
      Button(action: open) {
        Label(r.homeStatus.map { "スマホ制限・\($0)" } ?? "スマホ制限", systemImage: "hourglass")
          .font(AppFont.regular(13, relativeTo: .footnote))
          .foregroundStyle(r.homeStatus == nil ? Palette.dimText : Palette.green)
          .frame(minHeight: 44)
      }
      if r.focus == nil, let preset = r.homePreset {
        Button {
          r.start(preset)
        } label: {
          Label(preset.label, systemImage: "play.fill")
            .font(AppFont.bold(13, relativeTo: .footnote))
            .padding(.horizontal, 12)
            .frame(minHeight: 32)
            .background(Palette.greenSoft, in: Capsule())
            .foregroundStyle(Palette.green)
        }
        .frame(minHeight: 44)
        .accessibilityLabel("\(preset.label)の集中セッションを始める")
      }
    }
    .frame(maxWidth: .infinity)
    .sensoryFeedback(trigger: r.focus != nil) { _, started in started ? .success : nil }
  }
}

/// Apple の許可(Family Controls)が下りるまで
struct RestrictionUnavailableView: View {
  var body: some View {
    Form {
      Section {
        Label("Apple の許可待ち", systemImage: "clock.badge.questionmark").font(AppFont.bold(18))
        Text("スマホ制限は、Apple のスクリーンタイムの仕組み(Family Controls)を使います。配布するアプリで使うには Apple の許可が必要なので、許可が下りたら、ここから使えるようになります。")
          .font(AppFont.regular(14))
      }
      Section("できるようになること") { RestrictionFeatureList() }
      Section { Text(privacyNote).font(AppFont.regular(13)).foregroundStyle(Palette.subInk) }
    }
  }
}

/// スクリーンタイムの利用の許可を求める
struct RestrictionAuthorizeView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let r = model.restriction
    Form {
      Section {
        Text("アプリを制限するために、スクリーンタイムの利用を許可してね。あとから設定アプリの「スクリーンタイム」で取り消せます。")
          .font(AppFont.regular(14))
        Button {
          Task { await r.requestAuthorization() }
        } label: {
          Label("スクリーンタイムの利用を許可する", systemImage: "checkmark.shield")
        }
        if let message = r.errorMessage {
          Text(message).font(AppFont.regular(13)).foregroundStyle(Palette.lampText)
        }
      }
      Section("できること") { RestrictionFeatureList() }
      Section { Text(privacyNote).font(AppFont.regular(13)).foregroundStyle(Palette.subInk) }
    }
  }
}

/// 許可を得たあとの画面
struct RestrictionForm: View {
  @Environment(AppModel.self) private var model
  @State private var newSchedule: ScheduleRule?
  @State private var newLimit: LimitRule?
  @State private var newOpen: OpenRule?

  var body: some View {
    let r = model.restriction
    Form {
      Section {
        FocusSessionCard()
        if let s = r.study {
          Label(s.onBreak(at: Date()) ? "学習中の制限:休憩中" : "学習中の制限:学習を終えるまで", systemImage: "lamp.desk")
            .font(AppFont.regular(14))
        }
        ForEach(r.otherActive) { item in
          Label(item.title, systemImage: "lock").font(AppFont.regular(14))
        }
      } header: {
        Text("集中セッション")
      } footer: {
        Text("プリセットをワンタップで始まります。ホームのいちばん下の「▶ \(r.config.homePreset?.label ?? "プリセット")」や、ショートカット・Siri(「ツクエログで集中を始める」)からも始められます")
      }

      Section {
        BlockListRow(
          list: Binding(get: { r.config.focusApps }, set: { v in r.updateConfig { $0.focusApps = v } }),
          allowModeAvailable: true, locked: r.focusAppsLocked)
      } header: {
        Text("制限するアプリ")
      } footer: {
        Text(
          r.focusAppsLocked
            ? "ディープフォーカスの間は変えられません"
            : r.config.focusApps.allowMode
              ? "選んだもの以外をすべて制限します。学習中に使うので、ツクエログも選んでおいてね。電話など、制限できないアプリもあります"
              : "集中セッションと、学習中(連動するとき)に制限します")
      }

      Section {
        Toggle("机に向かっている間も制限する", isOn: Binding(get: { r.config.studyLink }, set: { v in r.updateConfig { $0.studyLink = v } }))
          .disabled(r.locked(RestrictionKeys.study))
        if r.config.studyLink {
          DifficultyPicker(
            selection: Binding(get: { r.config.studyDifficulty }, set: { v in r.updateConfig { $0.studyDifficulty = v } }),
            forStudy: true
          )
          .disabled(r.locked(RestrictionKeys.study))
        }
      } header: {
        Text("学習と連動")
      } footer: {
        Text("開始の儀式を終えてから、学習を終えるまで制限します。学習の休憩の間は、ふつうなら外し、タイムアウトなら間があいているときだけ外し、ディープフォーカスなら外しません。仮眠の間は外しません")
      }

      Section {
        ForEach(r.config.schedules) { rule in
          NavigationLink {
            ScheduleEditor(rule: rule, isNew: false)
          } label: {
            RuleRow(
              title: rule.schedule.name, detail: "\(rule.schedule.summary)・\(rule.schedule.difficulty.label)", enabled: rule.schedule.enabled,
              active: r.state.sessions[rule.key] != nil)
          }
        }
        if r.canAddSchedule {
          // ひな形を選ぶだけで作れる(曜日と時刻は、あとから変えられる)
          Menu {
            ForEach(ScheduleTemplate.all, id: \.name) { t in
              Button("\(t.name)(\(t.summary))") {
                newSchedule = ScheduleRule(schedule: t.make(), apps: r.config.focusApps)
              }
            }
            Button("自分で決める") {
              newSchedule = ScheduleRule(
                schedule: WeeklySchedule(name: "", weekdays: [2, 3, 4, 5, 6], startMinute: 21 * 60, endMinute: 23 * 60), apps: r.config.focusApps)
            }
          } label: {
            Label("時間割を足す", systemImage: "plus")
          }
        }
      } header: {
        Text("時間割")
      } footer: {
        Text("一度決めれば、アプリを開かなくても、決めた曜日と時刻に毎週そのまま制限します(\(RestrictionConfig.maxSchedules) つまで)")
      }

      Section {
        ForEach(r.config.limits) { rule in
          NavigationLink {
            LimitEditor(rule: rule, isNew: false)
          } label: {
            RuleRow(
              title: rule.limit.name, detail: "1 日 \(durationLabel(rule.limit.minutes))・\(rule.limit.difficulty.label)", enabled: rule.limit.enabled,
              active: r.state.sessions[rule.key] != nil)
          }
        }
        if r.canAddLimit {
          Button {
            newLimit = LimitRule(limit: DailyLimit(name: "", minutes: 30))
          } label: {
            Label("時間制限を足す", systemImage: "plus")
          }
        }
      } header: {
        Text("1 日の時間制限")
      } footer: {
        Text("選んだアプリを合わせて、1 日に使える時間を決めます。使い切ったら、あしたの 0 時まで開けません")
      }

      Section {
        ForEach(r.config.opens) { rule in
          NavigationLink {
            OpenLimitEditor(rule: rule, isNew: false)
          } label: {
            RuleRow(
              title: rule.limit.name, detail: "1 日 \(rule.limit.maxOpens) 回・1 回 \(rule.limit.minutesPerOpen) 分・今日あと \(r.remainingOpens(rule)) 回",
              enabled: rule.limit.enabled, active: false)
          }
        }
        if r.canAddOpen {
          Button {
            newOpen = OpenRule(limit: OpenLimit(name: "", maxOpens: 3))
          } label: {
            Label("開く回数の制限を足す", systemImage: "plus")
          }
        }
      } header: {
        Text("開く回数の制限")
      } footer: {
        Text("選んだアプリは、いつも制限の画面から開きます。1 日に開ける回数と、1 回に使える時間を決めます")
      }

      Section {
        DisclosureGroup("厳しさについて") {
          ForEach(Difficulty.allCases, id: \.self) { d in
            VStack(alignment: .leading, spacing: 2) {
              Text(d.label).font(AppFont.bold(15))
              Text(d.summary).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
            }
          }
        }
        Text(privacyNote).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      }
    }
    .sheet(item: $newSchedule) { rule in NavigationStack { ScheduleEditor(rule: rule, isNew: true) } }
    .sheet(item: $newLimit) { rule in NavigationStack { LimitEditor(rule: rule, isNew: true) } }
    .sheet(item: $newOpen) { rule in NavigationStack { OpenLimitEditor(rule: rule, isNew: true) } }
  }
}


private struct RuleRow: View {
  var title: String
  var detail: String
  var enabled: Bool
  var active: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(spacing: 6) {
        Text(title.isEmpty ? "名前なし" : title).font(AppFont.bold(16))
        if active {
          Text("制限中").font(AppFont.bold(11)).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Palette.green, in: Capsule())
        }
      }
      Text(enabled ? detail : "お休み中").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
    }
  }
}

/// 集中セッション:プリセットをワンタップして始める/いまの様子と、休憩・終了
struct FocusSessionCard: View {
  @Environment(AppModel.self) private var model
  @State private var notice: String?

  var body: some View {
    let r = model.restriction
    TimelineView(.periodic(from: Date(), by: 1)) { ctx in
      if let s = r.focus, !s.isOver(at: ctx.date) {
        running(s, now: ctx.date)
      } else {
        starter
      }
    }
    // 集中セッションや休憩の終わりを、開いたままの画面にも映す
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(5))
        r.tick()
      }
    }
  }

  @ViewBuilder
  private var starter: some View {
    let r = model.restriction
    VStack(alignment: .leading, spacing: 12) {
      LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
        ForEach(r.config.presets) { preset in
          Button {
            r.start(preset)
          } label: {
            VStack(spacing: 2) {
              Label(preset.label, systemImage: "play.fill").font(AppFont.bold(17))
              Text(preset.difficulty.label).font(AppFont.regular(12)).opacity(0.85)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
          }
          .buttonStyle(.borderedProminent)
          .disabled(r.config.focusApps.isEmpty)
        }
      }
      if r.config.focusApps.isEmpty {
        Text("先に、下の「制限するアプリ」を選んでね").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      }
      NavigationLink("プリセットを変える") { PresetListView() }
        .font(AppFont.regular(14))
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func running(_ s: ActiveSession, now: Date) -> some View {
    let r = model.restriction
    let remaining = Int(s.remainingSec(at: now) ?? 0)
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(s.onBreak(at: now) ? "休憩中" : "集中しています").font(AppFont.bold(18))
        Spacer()
        Text(s.difficulty.label).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      }
      Text("のこり \(remaining / 3600 > 0 ? "\(remaining / 3600):" : "")\(pad(remaining % 3600 / 60)):\(pad(remaining % 60))")
        .font(AppFont.bold(30).monospacedDigit())
      if let until = s.breakUntil, s.onBreak(at: now) {
        let left = Int(until.timeIntervalSince(now))
        Text("休憩はあと \(left / 60):\(pad(left % 60))。終わったら、また制限するよ").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
        Button("休憩を終えて集中に戻る") { r.endFocusBreak() }
      } else {
        actions(s, now: now)
      }
      if let notice {
        Text(notice).font(AppFont.regular(13)).foregroundStyle(Palette.lampText)
      }
    }
    .padding(.vertical, 4)
  }

  @ViewBuilder
  private func actions(_ s: ActiveSession, now: Date) -> some View {
    let r = model.restriction
    switch s.difficulty {
    case .deep:
      Text("ディープフォーカスなので、終わりの時刻まで休憩も終了もできません").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
    case .timeout:
      if !s.canBreak(at: now), let next = s.nextBreakAllowedAt {
        Text("次の休憩は \(clock(next)) から。それまでは終了もできません").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      } else {
        HStack {
          Button("\(RestrictionRules.breakMinutes) 分休憩する") { show(r.requestFocusBreak()) }
          Spacer()
          Button("終える", role: .destructive) { show(r.requestFocusEnd()) }
        }
        .buttonStyle(.bordered)
      }
    case .normal:
      let breakWait = s.breakPending(at: now) ? s.confirmWait(for: s.breakRequestedAt, now: now) : nil
      let endWait = s.endPending(at: now) ? s.confirmWait(for: s.endRequestedAt, now: now) : nil
      HStack {
        Button(confirmLabel(breakWait, first: "\(RestrictionRules.breakMinutes) 分休憩する")) { show(r.requestFocusBreak()) }
          .disabled((breakWait ?? 0) > 0)
        Spacer()
        Button(confirmLabel(endWait, first: "終える"), role: .destructive) { show(r.requestFocusEnd()) }
          .disabled((endWait ?? 0) > 0)
      }
      .buttonStyle(.bordered)
      if breakWait != nil || endWait != nil {
        Text("すぐに流されないよう、\(Int(RestrictionRules.confirmWaitSec)) 秒待ってから、もう一度押します").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
      }
    }
  }

  private func confirmLabel(_ wait: Double?, first: String) -> String {
    guard let wait else { return first }
    return wait > 0 ? "\(Int(wait.rounded(.up))) 秒待って" : "もう一度押す"
  }

  private func show(_ d: BreakDecision) {
    switch d {
    case .notUntil(let t): notice = "次の休憩は \(clock(t)) から"
    case .notAllowed: notice = "ディープフォーカスなので休憩できません"
    default: notice = nil
    }
  }

  private func show(_ d: EndDecision) {
    switch d {
    case .notUntil(let t): notice = "\(clock(t)) までは終えられません"
    case .notAllowed: notice = "ディープフォーカスなので終えられません"
    default: notice = nil
    }
  }

  private func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }
}

/// 厳しさを選ぶ(3 段階。それぞれの決まりを添える)
struct DifficultyPicker: View {
  @Binding var selection: Difficulty
  var forStudy: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Picker("厳しさ", selection: $selection) {
        ForEach(Difficulty.allCases, id: \.self) { Text($0.label).tag($0) }
      }
      .pickerStyle(.segmented)
      Text(forStudy ? studySummary : selection.summary).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
    }
  }

  private var studySummary: String {
    switch selection {
    case .normal: "学習の休憩の間は、制限を外す"
    case .timeout: "学習の休憩で外したら、次に外せるまで 15 分 → 30 分 → 60 分あく"
    case .deep: "学習を終えるまで、休憩の間も外さない。アプリの削除もできない"
    }
  }
}

/// 制限する(または許可する)アプリを選ぶ
struct BlockListRow: View {
  @Binding var list: BlockList
  var allowModeAvailable: Bool
  var locked: Bool
  @State private var picking = false

  var body: some View {
    Button {
      picking = true
    } label: {
      HStack(spacing: 8) {
        Text(list.allowMode ? "許可するアプリ" : "アプリを選ぶ").foregroundStyle(Palette.ink)
        Spacer()
        ForEach(Array(list.selection.applicationTokens.prefix(4)), id: \.self) { token in
          Label(token).labelStyle(.iconOnly)
        }
        Text(countText).font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Palette.dimText)
      }
    }
    .disabled(locked)
    .familyActivityPicker(
      headerText: list.allowMode ? "制限しないアプリを選んでね" : "制限するアプリを選んでね", isPresented: $picking, selection: $list.selection)
    if allowModeAvailable {
      Toggle("選んだもの以外をすべて制限する", isOn: $list.allowMode)
        .tint(Palette.green)
        .disabled(locked)
    }
  }

  private var countText: String {
    let s = list.selection
    var parts: [String] = []
    if !s.applicationTokens.isEmpty { parts.append("アプリ \(s.applicationTokens.count)") }
    if !s.categoryTokens.isEmpty { parts.append("種類 \(s.categoryTokens.count)") }
    if !s.webDomainTokens.isEmpty { parts.append("サイト \(s.webDomainTokens.count)") }
    return parts.isEmpty ? "なし" : parts.joined(separator: "・")
  }
}

/// 時間割の編集
struct ScheduleEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var rule: ScheduleRule
  var isNew: Bool

  var body: some View {
    let r = model.restriction
    let locked = r.locked(rule.key)
    Form {
      Section {
        TextField("名前(例:寝る前)", text: $rule.schedule.name)
        Toggle("使う", isOn: $rule.schedule.enabled).tint(Palette.green)
      }
      Section("曜日") {
        HStack(spacing: 6) {
          ForEach(Weekdays.order, id: \.self) { d in
            let on = rule.schedule.weekdays.contains(d)
            Button(Weekdays.name(d)) {
              if on { rule.schedule.weekdays.remove(d) } else { rule.schedule.weekdays.insert(d) }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(on ? Palette.green : Palette.greenSoft, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(on ? .white : Palette.ink)
            .accessibilityAddTraits(on ? .isSelected : [])
          }
        }
      }
      Section {
        DatePicker("始まり", selection: minuteBinding($rule.schedule.startMinute), displayedComponents: .hourAndMinute)
        DatePicker("終わり", selection: minuteBinding($rule.schedule.endMinute), displayedComponents: .hourAndMinute)
      } header: {
        Text("時刻")
      } footer: {
        Text(rule.schedule.problem ?? (rule.schedule.overnight ? "次の日の \(clock(rule.schedule.endMinute)) まで" : ""))
      }
      Section("厳しさ") {
        DifficultyPicker(selection: $rule.schedule.difficulty, forStudy: false)
      }
      Section("制限するアプリ") {
        BlockListRow(list: $rule.apps, allowModeAvailable: true, locked: false)
      }
      if !isNew {
        Section {
          Button("この時間割を消す", role: .destructive) {
            r.deleteSchedule(rule.id)
            dismiss()
          }
        }
      }
    }
    .disabled(locked)
    .navigationTitle(isNew ? "時間割を足す" : "時間割")
    .toolbar {
      if isNew {
        ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          r.save(rule)
          dismiss()
        }
        .disabled(locked || !rule.schedule.isValid || rule.apps.isEmpty)
      }
    }
    .overlay(alignment: .bottom) { if locked { LockedBanner() } }
  }
}

/// 1 日の時間制限の編集
struct LimitEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var rule: LimitRule
  var isNew: Bool

  var body: some View {
    let r = model.restriction
    let locked = r.locked(rule.key)
    Form {
      Section {
        TextField("名前(例:SNS)", text: $rule.limit.name)
        Toggle("使う", isOn: $rule.limit.enabled).tint(Palette.green)
      }
      Section("1 日に使える時間") {
        Picker("時間", selection: $rule.limit.minutes) {
          ForEach(DailyLimit.choices, id: \.self) { Text(durationLabel($0)).tag($0) }
        }
      }
      Section {
        DifficultyPicker(selection: $rule.limit.difficulty, forStudy: false)
      } header: {
        Text("使い切ったあと")
      } footer: {
        Text("ふつう:6 秒待てば、あと 5 分使える。タイムアウト:あと 5 分のたびに、次まで 15 分 → 30 分 → 60 分あく。ディープフォーカス:あしたまで使えない")
      }
      Section {
        BlockListRow(list: $rule.apps, allowModeAvailable: false, locked: false)
      } header: {
        Text("制限するアプリ")
      } footer: {
        Text("選んだアプリの時間を合わせて数えます")
      }
      if !isNew {
        Section {
          Button("この時間制限を消す", role: .destructive) {
            r.deleteLimit(rule.id)
            dismiss()
          }
        }
      }
    }
    .disabled(locked)
    .navigationTitle(isNew ? "時間制限を足す" : "時間制限")
    .toolbar {
      if isNew {
        ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          r.save(rule)
          dismiss()
        }
        .disabled(locked || rule.apps.isEmpty)
      }
    }
    .overlay(alignment: .bottom) { if locked { LockedBanner() } }
  }
}

/// 開く回数の制限の編集
struct OpenLimitEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var rule: OpenRule
  var isNew: Bool

  var body: some View {
    let r = model.restriction
    Form {
      Section {
        TextField("名前(例:動画)", text: $rule.limit.name)
        Toggle("使う", isOn: $rule.limit.enabled).tint(Palette.green)
      }
      Section("1 日に開ける回数") {
        Picker("回数", selection: $rule.limit.maxOpens) {
          ForEach(OpenLimit.openChoices, id: \.self) { Text("\($0) 回").tag($0) }
        }
        .pickerStyle(.segmented)
      }
      Section("1 回に使える時間") {
        Picker("時間", selection: $rule.limit.minutesPerOpen) {
          ForEach(OpenLimit.minuteChoices, id: \.self) { Text("\($0) 分").tag($0) }
        }
        .pickerStyle(.segmented)
      }
      Section {
        BlockListRow(list: $rule.apps, allowModeAvailable: false, locked: false)
      } header: {
        Text("制限するアプリ")
      }
      if !isNew {
        Section {
          Button("この制限を消す", role: .destructive) {
            r.deleteOpen(rule.id)
            dismiss()
          }
        }
      }
    }
    .navigationTitle(isNew ? "開く回数の制限を足す" : "開く回数の制限")
    .toolbar {
      if isNew {
        ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
      }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          r.save(rule)
          dismiss()
        }
        .disabled(rule.apps.isEmpty)
      }
    }
  }
}

private struct LockedBanner: View {
  var body: some View {
    Label("ディープフォーカスで制限している間は、変えられません", systemImage: "lock.fill")
      .font(AppFont.regular(13))
      .padding(12)
      .frame(maxWidth: .infinity)
      .background(.thinMaterial)
  }
}

/// 0 時からの分を、時刻を選ぶ部品につなぐ
private func minuteBinding(_ minutes: Binding<Int>) -> Binding<Date> {
  Binding(
    get: {
      Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date()
    },
    set: { date in
      let c = Calendar.current.dateComponents([.hour, .minute], from: date)
      minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
  )
}

/// 集中セッションのプリセット(4 つまで)と、ホームのワンタップに出すもの
struct PresetListView: View {
  @Environment(AppModel.self) private var model
  @State private var editing: FocusPreset?

  var body: some View {
    let r = model.restriction
    Form {
      Section {
        ForEach(r.config.presets) { preset in
          Button {
            editing = preset
          } label: {
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(preset.label).font(AppFont.bold(16)).foregroundStyle(Palette.ink)
                Text(preset.difficulty.label).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
              }
              Spacer()
              if r.config.homePresetID == preset.id {
                Label("ホーム", systemImage: "house.fill").font(AppFont.regular(12)).foregroundStyle(Palette.green)
              }
            }
          }
          .swipeActions {
            Button("消す", role: .destructive) { r.deletePreset(preset.id) }
          }
        }
        if r.canAddPreset {
          Button {
            editing = FocusPreset(minutes: 45)
          } label: {
            Label("プリセットを足す", systemImage: "plus")
          }
        }
      } footer: {
        Text("ワンタップで、選んだアプリをこの長さだけ制限します(\(FocusPreset.maxCount) つまで)")
      }
      Section {
        Picker("ホームに出す", selection: Binding(get: { r.config.homePresetID }, set: { r.setHomePreset($0) })) {
          Text("出さない").tag("")
          ForEach(r.config.presets) { Text($0.label).tag($0.id) }
        }
      } footer: {
        Text("ホームのいちばん下に、ワンタップで始めるボタンを出します")
      }
    }
    .navigationTitle("プリセット")
    .sheet(item: $editing) { preset in NavigationStack { PresetEditor(preset: preset) } }
  }
}

private struct PresetEditor: View {
  @Environment(AppModel.self) private var model
  @Environment(\.dismiss) private var dismiss
  @State var preset: FocusPreset

  var body: some View {
    let r = model.restriction
    Form {
      Section("長さ") {
        Picker("長さ", selection: $preset.minutes) {
          ForEach(FocusPreset.choices, id: \.self) { Text(durationLabel($0)).tag($0) }
        }
        .pickerStyle(.wheel)
      }
      Section("厳しさ") {
        DifficultyPicker(selection: $preset.difficulty, forStudy: false)
      }
    }
    .navigationTitle(preset.label)
    .toolbar {
      ToolbarItem(placement: .cancellationAction) { Button("やめる") { dismiss() } }
      ToolbarItem(placement: .confirmationAction) {
        Button("保存") {
          r.save(preset)
          dismiss()
        }
      }
    }
  }
}
