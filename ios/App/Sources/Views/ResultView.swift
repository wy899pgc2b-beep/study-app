import StudyCore
import SwiftUI

/// S-08 学習結果(設計書 3.14、5.5 の 9):ノートに付箋を貼ったような結果カード。
/// 褒め言葉 → 集中時間 → 集中の波 → 明日の一手(ホームに貼れる)→ 体感の 1 タップと、体感と判定を並べる一言
struct ResultView: View {
  @Environment(AppModel.self) private var model

  var body: some View {
    let runner = model.runner
    ZStack {
      PaperBackground()
      ScrollView {
        VStack(alignment: .leading, spacing: 18) {
          Text("\(Wording.day(runner.record?.startedAt ?? Date()))の記録").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
          if let results = runner.scenarioResults {
            scenarioCard(results)
          } else if let s = runner.summary, let card = runner.card {
            mainCard(card)
            waveCard(s)
            chips(s)
            nextStepNote(card.nextStep)
            selfRating(card)
          } else {
            Text("計測を始める前に終わったので、記録はないよ")
              .font(AppFont.regular(17))
              .card()
          }
          Button("ホームに戻る") { model.backHome() }
            .buttonStyle(PrimaryButtonStyle(height: 64, fontSize: 21))
          if let url = runner.exportURL {
            // 判定を確かめるための書き出し(映像・画像・特徴点は含まない)。本人が選んだ相手にだけ送られる
            ShareLink(item: url) {
              Label(runner.mode == .scenario ? "検証の記録を書き出す" : "この回の記録を書き出す", systemImage: "square.and.arrow.up")
                .font(AppFont.regular(15))
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .foregroundStyle(Palette.green)
          }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 24)
      }
    }
    .foregroundStyle(Palette.ink)
    .onAppear { runner.resultCardViewed() }
  }

  private func mainCard(_ card: ResultCard) -> some View {
    let ratio = card.studyMin > 0 ? card.focusMin / card.studyMin : 0
    return VStack(alignment: .leading, spacing: 18) {
      Text(card.praise).font(AppFont.bold(25, relativeTo: .title)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 18) {
        RingView(progress: ratio, lineWidth: 14).frame(width: 104, height: 104)
          .accessibilityLabel("机に向かった\(Wording.minutes(card.studyMin * 60))のうち、集中\(Wording.minutes(card.focusMin * 60))")
        VStack(alignment: .leading, spacing: 4) {
          Text("集中時間").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
          Text(Wording.minutes(card.focusMin * 60)).font(AppFont.bold(36, relativeTo: .largeTitle))
          Text("机に向かった \(Wording.minutes(card.studyMin * 60))\(card.avgFocus.map { "・平均の集中度 \($0)%" } ?? "")")
            .font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        }
      }
    }
    .padding(.horizontal, 22)
    .padding(.top, 28)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 8))
    .shadow(color: Color(hex: 0x50401E).opacity(0.12), radius: 9, x: 0, y: 8)
    .overlay(alignment: .top) {
      // マスキングテープ
      Rectangle().fill(Palette.tape.opacity(0.9)).frame(width: 90, height: 22).rotationEffect(.degrees(-2)).offset(y: -10)
    }
  }

  private func waveCard(_ s: SessionSummary) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("集中の波").font(AppFont.bold(15))
      WaveChart(scores: s.scores).frame(height: 110)
      if let rec = model.runner.record, let end = rec.endedAt {
        HStack {
          Text(Wording.clock(rec.startedAt))
          Spacer()
          Text(Wording.clock(end))
        }
        .font(AppFont.regular(12))
        .foregroundStyle(Palette.subInk)
      }
    }
    .card()
  }

  private func chips(_ s: SessionSummary) -> some View {
    let rec = model.runner.record
    let items = [
      "離席 \(Wording.minutes(s.awaySec))",
      "スマホに触れた \(rec?.deviceUseCount ?? 0)回",
      "休憩 \(Wording.minutes(rec?.breakSec ?? 0))",
    ]
    return HStack(spacing: 8) {
      ForEach(items, id: \.self) { item in
        Text(item)
          .font(AppFont.regular(14))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color.white, in: Capsule())
      }
    }
  }

  private func nextStepNote(_ text: String) -> some View {
    let pinned = model.pinnedNextStep == text
    return StickyNote(title: "明日の一手", text: text, angle: 0.8) {
      Button {
        model.pin(text)
      } label: {
        Label(pinned ? "ホームに貼ったよ" : "ホームに貼っておく", systemImage: pinned ? "checkmark" : "pin")
          .font(AppFont.bold(15))
          .foregroundStyle(Color(hex: 0x6B4A0C))
          .padding(.horizontal, 16)
          .frame(minHeight: 44)
          .background(Palette.stickyButton, in: RoundedRectangle(cornerRadius: 14))
          .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(hex: 0x9A6A12), lineWidth: 2))
      }
      .disabled(pinned)
    }
  }

  private func selfRating(_ card: ResultCard) -> some View {
    let chosen = model.runner.record?.selfRating
    return VStack(alignment: .leading, spacing: 10) {
      Text("自分の感覚では、どうだった?").font(AppFont.bold(15))
      HStack(spacing: 10) {
        ForEach(SelfRating.allCases, id: \.self) { rating in
          Button {
            model.runner.setSelfRating(rating)
          } label: {
            VStack(spacing: 6) {
              FaceIcon(rating: rating, color: chosen == rating ? Palette.greenDark : Palette.ink).frame(width: 34, height: 34)
              Text(label(rating)).font(chosen == rating ? AppFont.bold(14) : AppFont.regular(14))
            }
            .foregroundStyle(chosen == rating ? Palette.greenDark : Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(chosen == rating ? Palette.greenSoft : Color.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(chosen == rating ? Palette.green : Palette.line, lineWidth: 2))
          }
          .accessibilityLabel(label(rating))
        }
      }
      if let chosen {
        Text(selfRatingComment(chosen, avgFocus: card.avgFocus, focusMin: card.focusMin))
          .font(AppFont.regular(14))
          .foregroundStyle(Palette.subInk)
          .card(padding: 14)
      }
    }
  }

  /// 検証モードの結果:場面ごとの合否(MVP の完了の条件 2:9 場面のうち 8 場面以上)
  private func scenarioCard(_ results: [PhaseResult]) -> some View {
    let judged = results.filter { $0.pass != nil }
    let passed = judged.filter { $0.pass == true }.count
    let later: [String] = model.runner.scenarioRemaining.compactMap { id in Scenario.phases.first(where: { $0.id == id })?.label }
    return VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("検証モードの結果").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text(results.isEmpty ? "最後まで行った場面はないよ" : "\(judged.count) 場面のうち \(passed) 場面が合格").font(AppFont.bold(24, relativeTo: .title))
        Text("目安は 9 場面のうち 8 場面以上です。この結果は学習の記録には入りません")
          .font(AppFont.regular(13)).foregroundStyle(Palette.subInk).fixedSize(horizontal: false, vertical: true)
      }
      VStack(spacing: 0) {
        ForEach(Array(results.enumerated()), id: \.offset) { i, r in
          scenarioRow(i, r)
          if i < results.count - 1 { Divider().overlay(Palette.line) }
        }
      }
      if !later.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Label("あとで行う場面", systemImage: "clock.arrow.circlepath").font(AppFont.bold(15))
          Text(later.joined(separator: "・")).font(AppFont.regular(15))
          Text("ホームの付箋から、残りの場面だけ行えるよ").font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.sticky, in: RoundedRectangle(cornerRadius: 8))
      }
    }
    .card()
  }

  private func scenarioRow(_ index: Int, _ r: PhaseResult) -> some View {
    let text: String
    let icon: String
    let color: Color
    if r.pass == true {
      (text, icon, color) = ("合格", "checkmark.circle.fill", Palette.green)
    } else if r.pass == false {
      (text, icon, color) = ("不合格", "xmark.circle", Palette.lampText)
    } else {
      (text, icon, color) = ("対象外", "minus.circle", Palette.dimText)
    }
    // 期待した状態(または検出)の割合と、試作品と同じ注記
    var parts: [String] = []
    if let score = r.score { parts.append("\(r.flagLabel ?? "期待した状態") \(Int((score * 100).rounded()))%") }
    parts += r.notes
    let detail = parts.joined(separator: "・")
    return HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text("\(index + 1)").font(AppFont.bold(15)).foregroundStyle(Palette.subInk).frame(width: 18)
      VStack(alignment: .leading, spacing: 2) {
        Text(r.label).font(AppFont.medium(16))
        if !detail.isEmpty {
          Text(detail).font(AppFont.regular(12)).foregroundStyle(Palette.subInk).fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer()
      Label(text, systemImage: icon).font(AppFont.bold(14)).foregroundStyle(color)
    }
    .padding(.vertical, 10)
    .accessibilityElement(children: .combine)
  }

  private func label(_ r: SelfRating) -> String {
    switch r {
    case .good: return "集中できた"
    case .normal: return "ふつう"
    case .poor: return "いまいち"
    }
  }
}
