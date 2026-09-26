import Foundation

/// 制限しているアプリを開いたときに出す画面(シールド)の文言。
/// シールドは押したとき(と開いたとき)にしか描き直されないので、秒の数え下げは出さない
public struct ShieldCopy: Equatable, Sendable {
  public var title: String
  public var subtitle: String
  /// 閉じる(アプリを閉じて、ホームに戻る)
  public var primary: String
  /// 休憩する・あと 5 分使う・開く(できないときは nil)
  public var secondary: String?

  public init(title: String, subtitle: String, primary: String = "閉じる", secondary: String? = nil) {
    self.title = title
    self.subtitle = subtitle
    self.primary = primary
    self.secondary = secondary
  }
}

public enum ShieldCopyMaker {
  /// 集中セッション・学習中・時間割・使い切った時間制限のシールド
  public static func session(_ s: ActiveSession, name: String?, now: Date, calendar: Calendar = .current) -> ShieldCopy {
    let title: String
    let until: String
    switch s.kind {
    case .manual:
      title = "集中の時間です"
      until = s.endAt.map { "\(clock($0, calendar: calendar)) まで" } ?? "終えるまで"
    case .study:
      title = "学習中です"
      until = "学習を終えるまで"
    case .schedule:
      title = "「\(name ?? "時間割")」の時間です"
      until = s.endAt.map { "\(clock($0, calendar: calendar)) まで" } ?? ""
    case .limit:
      title = "「\(name ?? "時間制限")」は今日の時間を使い切りました"
      until = "あしたの 0 時まで"
    }
    let action = s.kind == .limit ? "あと \(RestrictionRules.breakMinutes) 分使う" : "\(RestrictionRules.breakMinutes) 分休憩する"
    switch s.difficulty {
    case .deep:
      let what = s.kind == .limit ? "延長" : "休憩も終了も"
      return ShieldCopy(title: title, subtitle: "\(until)。ディープフォーカスなので、\(what)できません")
    case .timeout:
      if !s.canBreak(at: now), let next = s.nextBreakAllowedAt {
        return ShieldCopy(title: title, subtitle: "\(until)。次は \(clock(next, calendar: calendar)) からできます")
      }
      let gap = RestrictionRules.timeoutWait(afterBreak: s.breaksTaken + 1)
      return ShieldCopy(title: title, subtitle: "\(until)。\(action)と、次まで \(gap) 分あきます", secondary: action)
    case .normal:
      if s.breakPending(at: now) {
        let wait = Int(s.confirmWait(for: s.breakRequestedAt, now: now).rounded(.up))
        let text = wait > 0 ? "\(wait) 秒待ってから、もう一度押してね" : "もう一度押すと、\(action)ことができます"
        return ShieldCopy(title: title, subtitle: text, secondary: "もう一度押す")
      }
      let wait = Int(RestrictionRules.confirmWaitSec)
      return ShieldCopy(title: title, subtitle: "\(until)。\(action)には、押してから \(wait) 秒待って、もう一度押します", secondary: action)
    }
  }

  /// 開く回数の制限のシールド
  public static func open(_ limit: OpenLimit, remaining: Int) -> ShieldCopy {
    let title = "「\(limit.name)」は開く回数を決めています"
    guard remaining > 0 else {
      return ShieldCopy(title: title, subtitle: "今日はもう開けません。あしたの 0 時にもどります")
    }
    return ShieldCopy(
      title: title, subtitle: "今日はあと \(remaining) 回開けます。1 回 \(limit.minutesPerOpen) 分使えます",
      secondary: "開く(あと \(remaining) 回)")
  }
}
