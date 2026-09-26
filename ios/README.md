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
| `SelfRatingComment.swift` | − | 体感の 1 タップと判定を並べる一言 |
| `Records.swift` | − | 端末に保存する記録の形(学習・1 分ごと・出来事・一時停止と休憩の区間・利用状況)、学習日(04:00 区切り)と合計、強制終了からの回復、「記録を書き出す」の JSON |
| `Power.swift` | − | 熱と電池の決め方(解析の回数、電池の知らせと終了、1 時間あたりの電池の減り) |
| `Scenario.swift` | `scenario.js` | 検証シナリオの 9 場面と採点(`evaluatePhase`) |
| `ScenarioRun.swift` | `app.js` の scenarioStep、finish | 検証モードの進み方と、1 回の学習の書き出し(試作品の結果の JSON と同じ形。映像・画像・特徴点は含めない) |
| `Config.swift` | `DEFAULTS` | しきい値。`prototype/tools/gen-swift-config.mjs` で作る(手で書き換えない) |

### 試作品と同じ判定になっているかの確かめ方

1. 試作品のテスト(`prototype/test/analysis.test.js`)を動かし、Analyzer に入れた特徴量と判定の結果をすべて記録する。特徴量の計算・キャリブレーション・位置合わせ・1 分ごとの集計・髪と肌の面積・検証シナリオの採点の例も加える(例は、決まった種から作った乱数で作る。カメラの映像から取ったものではない)。
   `prototype/tools/export-parity-fixtures.mjs` が `StudyCore/Tests/StudyCoreTests/Fixtures/*.json` に書き出す。
2. Swift のテスト(`ParityTests.swift`、`VisionHelperTests.swift`、`ScenarioTests.swift`)が同じ入力を StudyCore に入れ、結果を比べる。数は有効数字 10 桁で保存しているので、相対 1e-7 の誤差を許す。

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
| `scripts/fetch-fonts.sh` | 画面の文字 Zen Maru Gothic(SIL Open Font License)を、ライセンスの文書と一緒に取ってくる |
| `Sources/Capture/` | カメラ(バックカメラ・4:3・毎秒 5 回)、傾き(Core Motion)、端末内 AI、フレームから特徴量まで |
| `Sources/Session/` | 学習の実行(StudySession を動かし、声と音で知らせる。うとうとの注意音、居眠りのアラーム、区切りのやさしい音。消音モードの振動。熱いときは解析の回数を下げ、電池が 15% で知らせ、5% で保存して終える) |
| `Sources/Store/` | 端末の DB(SQLite、GRDB)。1 分ごとに保存し、強制終了されても次の起動で締める。映像・画像・特徴点は保存しない |
| `Sources/Views/` | 画面(設計書 5.5 の見た目:方眼ノートの背景、付箋、ランプ)。オンボーディング(映像の扱いの図と同意、学年、カメラの許可)、ホーム、設定、置く前の説明、位置合わせと儀式、学習中(ランプの灯り。触れると一時停止)、一時停止(休憩に切り替えられる)、休憩(ヒント)、結果カード(集中の波、ホームに貼る、体感の 1 タップ)、検証モードの結果 |

検証モード(オンボーディングの後に勧める。「あとで」にするとホームに付箋を残す。設定からも始められる):声の指示に合わせて 9 つの場面を行い、場面ごとの合否を結果の画面に出す。学習の記録には入れない。画面に触れると止まり、今の場面をやり直すか、飛ばす(あとで残りの場面だけ行う)。結果の画面の「記録を書き出す」で、試作品と同じ形の JSON を共有シートから送れる。設定の「記録を書き出す」は、端末に保存した全部の記録(時刻・時間・回数・集中度と利用状況)を JSON にする。どちらも映像・画像・特徴点は含まない。

案内のしかた(ホームで選ぶ):「声と音」と「消音(振動だけ)」。消音では、区切りを振動の回数で知らせる(`Sources/Session/Vibrator.swift`)。声と音のときにイヤホンをつけていなければ、周りに人がいるときはイヤホンか消音を勧める。

まだ入れていないもの:カメラを許可しないときの、時間だけを記録する使い方(保留)。

### 版と署名

- `Config/App.xcconfig`:アプリの版(MARKETING_VERSION)、ビルド番号、Bundle ID。アプリの target だけに効く。
- `Resources/Assets.xcassets`:アプリのアイコン(決定事項 D-22。利用者の考えたデザイン)。正方形を上 7 割と下 3 割に分け、ベースは真っ白。上 7 割にエメラルドグリーンの横長の長方形と、平仮名の「つくえ」(白。いちばん太い字で、長方形の中にできる限り大きく)、下 3 割に黒い「Log」。文字はアプリの画面と同じ Zen Maru Gothic(SIL Open Font License。作るときに取ってくる)。`scripts/make_icon.py` で作る(`--text-color`(white・black・gray・indigo)と `--band`(inset・full)で、ほかの案も作れる)。
- `Resources/PrivacyInfo.xcprivacy`:プライバシーの申告(追跡しない。端末の外に送るデータはない)。
- `scripts/asc_signing.py`:TestFlight に送るときの署名を、App Store Connect の API で用意する。配布用の証明書の鍵は API キーから毎回同じものを作るので、鍵をどこにも保存せず、証明書を取り消さずに使い続けられる。`self-test` で作り方だけを確かめられる。

### TestFlight に送る

`.github/workflows/testflight.yml`(Mac)。tag `testflight-*` を push するか、Actions の画面で「Run workflow」を押すと、署名して App Store Connect に送る。ビルド番号は、この流れの実行番号。
Secrets(`ASC_KEY_ID`・`ASC_ISSUER_ID`・`ASC_PRIVATE_KEY`・`APPLE_TEAM_ID`)と変数 `BUNDLE_ID` がまだないときや、この流れの設定を変えたときは、送らずに Release のビルドまで確かめる(dry run)。

### ビルド

GitHub Actions の `ios-build`(Mac)が、`ios/` を変えたときに署名なしでビルドする。手元の Mac では次のとおり。

```sh
cd ios/App
scripts/fetch-models.sh
scripts/fetch-fonts.sh
xcodegen generate
pod install
open StudyApp.xcworkspace
```
