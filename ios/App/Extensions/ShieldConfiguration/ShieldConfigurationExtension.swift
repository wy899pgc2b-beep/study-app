import ManagedSettings
import ManagedSettingsUI
import RestrictionCore
import UIKit

/// 制限しているアプリを開いたときの画面(シールド)。白地に、アイコンと同じエメラルドのボタン
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    make(ShieldTarget(app: application.token))
  }

  override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
    make(ShieldTarget(app: application.token, category: category.token))
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    make(ShieldTarget(web: webDomain.token))
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
    make(ShieldTarget(web: webDomain.token, category: category.token))
  }

  private static let ink = UIColor(red: 0x22 / 255, green: 0x30 / 255, blue: 0x3C / 255, alpha: 1)
  private static let subInk = UIColor(red: 0x4B / 255, green: 0x55 / 255, blue: 0x60 / 255, alpha: 1)
  private static let emerald = UIColor(red: 0x2F / 255, green: 0x6B / 255, blue: 0x5A / 255, alpha: 1)

  private func make(_ target: ShieldTarget) -> ShieldConfiguration {
    let copy = RestrictionEngine.copy(for: target, now: Date())
    return ShieldConfiguration(
      backgroundBlurStyle: nil,
      backgroundColor: .white,
      icon: UIImage(systemName: "lamp.desk.fill")?.withTintColor(Self.emerald, renderingMode: .alwaysOriginal),
      title: ShieldConfiguration.Label(text: copy.title, color: Self.ink),
      subtitle: ShieldConfiguration.Label(text: copy.subtitle, color: Self.subInk),
      primaryButtonLabel: ShieldConfiguration.Label(text: copy.primary, color: .white),
      primaryButtonBackgroundColor: Self.emerald,
      secondaryButtonLabel: copy.secondary.map { ShieldConfiguration.Label(text: $0, color: Self.emerald) })
  }
}
