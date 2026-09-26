import Foundation

/// 熱と電池の扱い(MVP の設計 5 章「端末の制御」)。端末の値を読むのはアプリの側で、ここでは決め方だけを持つ
public enum ThermalLevel: Int, Codable, Comparable, Sendable {
  case nominal, fair, serious, critical

  public static func < (a: ThermalLevel, b: ThermalLevel) -> Bool { a.rawValue < b.rawValue }

  public var name: String {
    switch self {
    case .nominal: "nominal"
    case .fair: "fair"
    case .serious: "serious"
    case .critical: "critical"
    }
  }
}

public enum BatteryAction: Equatable, Sendable {
  case none
  /// 残りが少ないことを 1 回だけ知らせる(15% 以下)
  case warn
  /// 記録を保存して終える(5% 以下)
  case finish
}

public enum PowerPolicy {
  public static let warnLevel = 0.15
  public static let finishLevel = 0.05

  /// 温度に応じた解析の回数(毎秒)。熱いときは回数を下げる。判定は時間で数えているので、回数を下げても同じ手順で動く
  public static func analysisFps(base: Double, thermal: ThermalLevel) -> Double {
    switch thermal {
    case .nominal, .fair: base
    case .serious: Swift.min(base, 3)
    case .critical: Swift.min(base, 2)
    }
  }

  /// 熱いことを声で知らせるか(回数を下げても、いちばん熱い段階になったとき)
  public static func shouldWarnHeat(_ thermal: ThermalLevel) -> Bool { thermal == .critical }

  /// 電池の残り(0〜1。分からなければ負の値)と充電中かから、することを決める
  public static func batteryAction(level: Double, charging: Bool, warned: Bool) -> BatteryAction {
    guard level >= 0, !charging else { return .none }
    if level <= finishLevel { return .finish }
    if level <= warnLevel && !warned { return .warn }
    return .none
  }

  /// 1 時間あたりの電池の減り(%)。短すぎる計測や、充電して増えたときは nil(MVP の完了の条件 6:20% 以下)
  public static func batteryPerHour(start: Double?, end: Double?, hours: Double) -> Double? {
    guard let start, let end, start >= 0, end >= 0, hours >= 0.1, end <= start else { return nil }
    return (start - end) * 100 / hours
  }
}
