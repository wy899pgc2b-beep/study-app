# iPhone アプリ(MVP 1-A)

ここにはコードの置き方と、テストのしかたを書く。

## 置き方

| 場所 | 中身 | 状況 |
| --- | --- | --- |
| `StudyCore/` | 判定の中心。Apple の仕組みに頼らない Swift のパッケージ(Linux でもテストできる) | 試作品 poc-24 の判定を移した |
| `App/` | 画面・カメラ・MediaPipe・音声(XcodeGen の project.yml から作る) | 骨組みを作った(下記) |

## StudyCore

試作品の `prototype/js/analysis.js` を、名前も計算の順番もそのままで Swift に移したもの。

| ファイル | 試作品での名前 | 中身 |
| --- | --- | --- |
| `Types.swift` | − | 検出結果(Frame)と特徴量(Features)の型 |
| `FeatureExtractor.swift` | `extractFeatures` | 顔・手・上半身の特徴点から特徴量を計算する(設計書 4.3) |
| `Geometry.swift` | `focalLengthPx` ほか | 焦点距離、カメラの傾き、目と机の距離(設計書 4.9) |
| `Framing.swift` | `checkFraming` | 設置位置ガイドの判定(設計書 3.4) |
| `Calibration.swift` | `computeCalibration` ほか | キャリブレーション、目を閉じたときの基準、閉眼の判定(設計書 4.8、4.12) |
| `HandMotion.swift` | `HandMotion` | 手の動きの速さ |
| `Analyzer.swift` | `Analyzer` | フレームごとの状態と出来事(設計書 4.4〜4.11) |
| `SessionRecorder.swift` | `SessionRecorder` ほか | 1 分ごとの集中度と学習スタイル(設計書 4.5、4.6) |
| `Segmentation.swift` | `segmentStats`(vision.js) | 髪・顔の肌・人の面積 |
| `StudySession.swift` | `app.js` の流れ | 1 回の学習の流れ(設置位置ガイド → 開始の儀式 → 学習中 → 一時停止・休憩 → 終了)。儀式の順番は設計書 4.12(目を閉じる → 姿勢)。休憩の後は位置を確かめ、姿勢だけを記録し直す |
| `PlacementGuide.swift` | `app.js` の guideStep | 設置位置ガイド(顔の位置と大きさ、明るさ、肩、横向きのときは傾き 10〜20° とペンを持った手)。足りないものを声で知らせる |
| `ResultCard.swift` | − | 結果カードの文(褒め言葉と明日の一手の規則。言い回しを複数用意し、前回と同じ文を続けない) |
| `Config.swift` | `DEFAULTS` | しきい値。`prototype/tools/gen-swift-config.mjs` で作る(手で書き換えない) |

### 試作品と同じ判定になっているかの確かめ方

1. 試作品のテスト(`prototype/test/analysis.test.js`)を動かし、Analyzer に入れた特徴量と判定の結果をすべて記録する。特徴量の計算・キャリブレーション・位置合わせ・1 分ごとの集計の例も加える。
   `prototype/tools/export-parity-fixtures.mjs` が `StudyCore/Tests/StudyCoreTests/Fixtures/*.json` に書き出す。
2. Swift のテスト(`ParityTests.swift`)が同じ入力を StudyCore に入れ、結果を比べる。数は有効数字 10 桁で保存しているので、相対 1e-7 の誤差を許す。

JavaScript の値の扱いも合わせている。取れなかった値(undefined)は比べると常に偽、`&&` や `||` の判定では 0 と NaN も偽、中央値は数でない値を除き、四捨五入は Math.round と同じ(0.5 は切り上げ)。

### 試作品のしきい値や判定を変えたとき

```sh
cd prototype
npm test                                # 試作品のテスト
node tools/gen-swift-config.mjs         # Config.swift を作り直す
node tools/export-parity-fixtures.mjs   # 突き合わせ用のデータを作り直す
```

そのあと、Swift 側の判定を同じように直す。GitHub Actions の `core-tests` が、push のたびに次を確かめる。

- 試作品のテストが通る
- `Config.swift` が試作品のしきい値と同じ
- `swift test`(StudyCore が試作品と同じ判定になる)

手元に Swift があれば、`cd ios/StudyCore && swift test` でも確かめられる。

## App(iPhone アプリ「ツクエログ」(仮の名前)の骨組み)

| ファイル | 中身 |
| --- | --- |
| `project.yml` | Xcode のプロジェクトの設定(XcodeGen)。Bundle ID は仮(`com.example.studyapp`) |
| `Podfile` | MediaPipe(`MediaPipeTasksVision`) |
| `scripts/fetch-models.sh` | MediaPipe のモデルを取ってくる(試作品と同じ 4 つ。リポジトリには入れない) |
| `Sources/Capture/` | カメラ(バックカメラ・4:3・毎秒 5 回)、傾き(Core Motion)、端末内 AI、フレームから特徴量まで |
| `Sources/Session/` | 学習の実行(StudySession を動かし、声と音で知らせる。うとうとの注意音、居眠りのアラーム、区切りのやさしい音) |
| `Sources/Views/` | ホーム(休憩タイマーのスイッチ)、位置合わせ、学習中(画面は黒。触れると一時停止)、結果カード |

まだ入れていないもの:端末の DB(記録の保存、過去 7 日との比べ)、オンボーディング、設定画面、検証モード、利用状況の記録。

### ビルド

GitHub Actions の `ios-build`(Mac)が、`ios/` を変えたときに署名なしでビルドする。手元の Mac では次のとおり。

```sh
cd ios/App
scripts/fetch-models.sh
xcodegen generate
pod install
open StudyApp.xcworkspace
```
