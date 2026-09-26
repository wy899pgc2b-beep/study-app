import StudyCore
import SwiftUI

/// S-01 オンボーディング(設計書 3.20、MVP の設計 S-01):初回だけ、同意 → 学年 → カメラの許可の 3 枚。
/// 最初の計測までの操作を少なくするため、ここで聞くのはこの 3 つだけ(設計書 3.20 の要件 8)
struct OnboardingView: View {
  @Environment(AppModel.self) private var model
  @State private var page = 0
  @State private var grade: Grade?
  @State private var parentalConsent = false
  @State private var requesting = false

  var body: some View {
    ZStack {
      PaperBackground()
      VStack(spacing: 0) {
        dots.padding(.top, 16)
        ScrollView {
          Group {
            switch page {
            case 0: consentPage
            case 1: gradePage
            default: cameraPage
            }
          }
          .padding(.horizontal, 22)
          .padding(.vertical, 24)
        }
      }
    }
    .foregroundStyle(Palette.ink)
    .animation(.easeInOut(duration: 0.2), value: page)
    .onAppear { model.usage("onboarding_start") }
  }

  private var dots: some View {
    HStack(spacing: 8) {
      ForEach(0..<3, id: \.self) { i in
        Capsule().fill(i == page ? Palette.green : Palette.line).frame(width: i == page ? 22 : 8, height: 8)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(page + 1) / 3")
  }

  // MARK: - 1. 映像の扱いと同意

  private var consentPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("ようこそ、ツクエログへ").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text("カメラの映像は、あなただけのもの").font(AppFont.bold(26, relativeTo: .title)).fixedSize(horizontal: false, vertical: true)
      }
      PrivacyDiagram()
      VStack(alignment: .leading, spacing: 10) {
        bullet("iphone", "映像はこの iPhone の中で解析するだけで、保存しません。記録するのは、時間と集中度だけです")
        bullet("eye.slash", "保護者・学校・友だちを含め、あなた以外の人は映像を見られません")
        bullet("mic.slash", "マイクは使いません。声は録音しません")
        bullet("square.and.arrow.up", "記録を書き出すのは、あなたが操作したときだけです。書き出す記録にも映像は入りません")
      }
      .card()
      Button("わかった。同意して次へ") {
        model.update { $0.consentedAt = Date() }
        model.usage("consent_given")
        page = 1
      }
      .buttonStyle(PrimaryButtonStyle(height: 64, fontSize: 21))
    }
  }

  private func bullet(_ icon: String, _ text: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Image(systemName: icon).foregroundStyle(Palette.green).frame(width: 22).accessibilityHidden(true)
      Text(text).font(AppFont.regular(15)).fixedSize(horizontal: false, vertical: true)
    }
  }

  // MARK: - 2. 学年

  private var gradePage: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("あなたのことを少しだけ").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text("学年を教えてね").font(AppFont.bold(26, relativeTo: .title))
      }
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
        ForEach(Grade.allCases) { g in
          Button(g.label) {
            grade = g
            if !g.needsParentalConsent { parentalConsent = false }
            model.usage("grade_selected", ["grade": g.rawValue])
            if g.needsParentalConsent { model.usage("parental_consent_requested") }
          }
          .buttonStyle(OutlineButtonStyle(selected: grade == g, height: 52))
          .accessibilityAddTraits(grade == g ? .isSelected : [])
        }
      }
      if grade?.needsParentalConsent == true {
        VStack(alignment: .leading, spacing: 12) {
          Text("中学生の人は、使う前に保護者の人にこのアプリのことを話して、同意をもらってください。保護者の人も、映像を見ることはできません")
            .font(AppFont.regular(15)).fixedSize(horizontal: false, vertical: true)
          Toggle(isOn: $parentalConsent) {
            Text("保護者の同意をもらいました").font(AppFont.bold(16))
          }
          .tint(Palette.green)
        }
        .card()
      }
      Button("次へ") {
        guard let grade else { return }
        model.update {
          $0.grade = grade
          $0.parentalConsent = grade.needsParentalConsent && parentalConsent
        }
        if grade.needsParentalConsent { model.usage("parental_consent_granted") }
        page = 2
      }
      .buttonStyle(PrimaryButtonStyle(height: 64, fontSize: 21))
      .disabled(!canLeaveGrade)
      .opacity(canLeaveGrade ? 1 : 0.4)
      Text("学年は、集計を学年ごとに見るためだけに使います。あとから設定で変えられます")
        .font(AppFont.regular(13)).foregroundStyle(Palette.subInk).fixedSize(horizontal: false, vertical: true)
    }
  }

  private var canLeaveGrade: Bool {
    guard let grade else { return false }
    return !grade.needsParentalConsent || parentalConsent
  }

  // MARK: - 3. カメラの許可

  private var cameraPage: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 4) {
        Text("さいごに").font(AppFont.regular(14)).foregroundStyle(Palette.subInk)
        Text("カメラを使わせてね").font(AppFont.bold(26, relativeTo: .title))
      }
      HStack(spacing: 16) {
        Image(systemName: "camera.fill").font(.system(size: 34)).foregroundStyle(Palette.green).accessibilityHidden(true)
        Text("机に向かっているときの姿勢や目の様子から、集中できているかを判定します。映像はこの iPhone の中だけで解析します")
          .font(AppFont.regular(15)).fixedSize(horizontal: false, vertical: true)
      }
      .card()
      Button {
        requesting = true
        model.usage("camera_permission_shown")
        Task {
          let granted = await CameraSource.requestAccess()
          model.usage(granted ? "camera_permission_granted" : "camera_permission_denied")
          requesting = false
          model.completeOnboarding()
        }
      } label: {
        if requesting { ProgressView().tint(.white) } else { Text("カメラを許可する") }
      }
      .buttonStyle(PrimaryButtonStyle(height: 64, fontSize: 21))
      .disabled(requesting)
      Button("あとで") {
        model.usage("camera_permission_later")
        model.completeOnboarding()
      }
      .font(AppFont.regular(16))
      .foregroundStyle(Palette.green)
      .frame(maxWidth: .infinity, minHeight: 44)
    }
  }
}

/// 映像を使うのは本人とこの iPhone の中だけで、ほかの人には届かないことを示す図(設計書 3.20 の要件 1)
struct PrivacyDiagram: View {
  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 14) {
        Image(systemName: "person.fill").font(.system(size: 30))
        Image(systemName: "arrow.left.and.right").font(.system(size: 16)).foregroundStyle(Palette.subInk)
        ZStack(alignment: .bottomTrailing) {
          Image(systemName: "iphone").font(.system(size: 38))
          Image(systemName: "lock.fill").font(.system(size: 14)).foregroundStyle(.white)
            .padding(5).background(Palette.green, in: Circle()).offset(x: 8, y: 4)
        }
      }
      .foregroundStyle(Palette.greenDark)
      .padding(.vertical, 16)
      .frame(maxWidth: .infinity)
      .background(Palette.greenSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
      Text("あなたと、この iPhone の中だけ").font(AppFont.bold(14)).foregroundStyle(Palette.greenDark).padding(.top, 6)
      // 壁:ここから先には映像が届かない
      HStack(spacing: 8) {
        Rectangle().fill(Palette.line).frame(height: 2)
        Image(systemName: "xmark.circle.fill").font(.system(size: 22)).foregroundStyle(Palette.lampText)
        Rectangle().fill(Palette.line).frame(height: 2)
      }
      .padding(.vertical, 10)
      HStack(spacing: 0) {
        other("figure.2.and.child.holdinghands", "保護者")
        other("building.columns", "学校")
        other("person.3", "友だち")
      }
      Text("映像は見られません").font(AppFont.bold(14)).foregroundStyle(Palette.subInk).padding(.top, 6)
    }
    .padding(16)
    .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("映像を使うのは、あなたとこの iPhone の中だけです。保護者、学校、友だちは映像を見られません")
  }

  private func other(_ icon: String, _ label: String) -> some View {
    VStack(spacing: 6) {
      ZStack(alignment: .bottomTrailing) {
        Image(systemName: icon).font(.system(size: 26)).foregroundStyle(Palette.dimText)
        Image(systemName: "eye.slash.fill").font(.system(size: 12)).foregroundStyle(Palette.lampText)
          .padding(4).background(Color.white, in: Circle()).offset(x: 8, y: 4)
      }
      .frame(height: 36)
      Text(label).font(AppFont.regular(13)).foregroundStyle(Palette.subInk)
    }
    .frame(maxWidth: .infinity)
  }
}
