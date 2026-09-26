import DeviceActivity
import Foundation

/// 時間の見張り。集中セッション・休憩・時間割の区間の始まりと終わり、1 日の時間を使い切ったときに呼ばれる
final class MonitorExtension: DeviceActivityMonitor {
  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    RestrictionEngine.intervalDidStart(activity.rawValue, now: Date())
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    RestrictionEngine.intervalDidEnd(activity.rawValue, now: Date())
  }

  override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
    super.eventDidReachThreshold(event, activity: activity)
    RestrictionEngine.thresholdReached(event.rawValue, activity: activity.rawValue, now: Date())
  }
}
