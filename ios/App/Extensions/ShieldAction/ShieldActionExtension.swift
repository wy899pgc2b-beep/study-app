import Foundation
import ManagedSettings

/// 制限の画面のボタン。1 つめ(閉じる)はアプリを閉じる。2 つめは休憩する・あと 5 分使う・開く(厳しさと回数による)
final class ShieldActionExtension: ShieldActionDelegate {
  override func handle(action: ShieldAction, for application: ApplicationToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    completionHandler(respond(action, ShieldTarget(app: application)))
  }

  override func handle(action: ShieldAction, for webDomain: WebDomainToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    completionHandler(respond(action, ShieldTarget(web: webDomain)))
  }

  override func handle(action: ShieldAction, for category: ActivityCategoryToken, completionHandler: @escaping (ShieldActionResponse) -> Void) {
    completionHandler(respond(action, ShieldTarget(category: category)))
  }

  private func respond(_ action: ShieldAction, _ target: ShieldTarget) -> ShieldActionResponse {
    switch action {
    case .primaryButtonPressed:
      return .close
    case .secondaryButtonPressed:
      // 描き直す(.defer):制限を外したときはそのままアプリが開き、6 秒待つときは待つ案内に変わる
      return RestrictionEngine.secondaryPressed(for: target, now: Date()) == .redraw ? .defer : .close
    default:
      // 新しい OS で足されたボタン(使っていない)
      return .close
    }
  }
}
