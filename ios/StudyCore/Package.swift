// swift-tools-version:5.9
// 判定の中心(特徴量・判定・1 分ごとの集計)と、スマホ制限の決まり。Apple の仕組みに頼らないので、Linux でもテストできる。
import PackageDescription

let package = Package(
  name: "StudyCore",
  platforms: [.iOS(.v17), .macOS(.v13)],
  products: [
    .library(name: "StudyCore", targets: ["StudyCore"]),
    // スマホ制限(決定事項 D-24)。アプリと拡張(制限の画面・ボタン・時間の見張り)が使う
    .library(name: "RestrictionCore", targets: ["RestrictionCore"]),
  ],
  targets: [
    .target(name: "StudyCore"),
    .target(name: "RestrictionCore"),
    .testTarget(
      name: "StudyCoreTests",
      dependencies: ["StudyCore"],
      // 突き合わせ用のデータ(試作品から書き出したもの)は、テストのソースの場所から直接読む
      exclude: ["Fixtures"]
    ),
    .testTarget(name: "RestrictionCoreTests", dependencies: ["RestrictionCore"]),
  ]
)
