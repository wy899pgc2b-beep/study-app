# iPhone アプリ(MVP 1-A)

ここにはコードの置き方と、テストのしかたを書く。

## 置き方

| 場所 | 中身 | 状況 |
| --- | --- | --- |
| `StudyCore/` | 判定の中心。Apple の仕組みに頼らない Swift のパッケージ(Linux でもテストできる) | 試作品 poc-24 の判定を移した |
| `App/` | 画面・カメラ・MediaPipe・音声・DB(XcodeGen の project.yml から作る) | これから |

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
