import SwiftUI

@main
struct StudyApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(model)
    }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var model
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      switch model.screen {
      case .home: HomeView()
      case .placement: PlacementView()
      case .session: SessionView()
      case .result: ResultView()
      case .onboarding: OnboardingView()
      case .scenarioInvite: ScenarioInviteView()
      }
    }
    // アプリを離れたら一時停止する(設計書 3.11)
    .onChange(of: scenePhase) { _, newPhase in
      if newPhase != .active { model.runner.pause(.leftApp) }
      // スマホ制限:戻ってきたら、見張りと制限を設定に合わせる
      if newPhase == .active { model.restriction.refresh() }
    }
  }
}
