# study-app

学習中の様子を iPhone のカメラで捉え、端末の中の AI で学習態度(集中・居眠り・よそ見・離席・癖・姿勢)を判定する学習支援アプリのコード。

**カメラの画像や映像は、端末の中だけで処理する。** 保存も送信もせず、本人以外(学校や保護者を含む)が見られる形にはしない。このリポジトリにも、撮影した画像・映像や、そこから作ったデータは入れない。

## 中身

| 場所 | 中身 |
| --- | --- |
| [`prototype/`](prototype/README.md) | ブラウザで動く試作品(技術検証で判定の仕組みを固めたもの。版 `poc-24`)。公開中:https://wy899pgc2b-beep.github.io/study-poc/ |
| [`ios/`](ios/README.md) | iPhone アプリ。判定の中心 `ios/StudyCore` は、試作品の判定を Swift に移したもの |

## テスト

GitHub Actions の `core-tests` が、push のたびに次を確かめる。

- 試作品のテスト(`cd prototype && npm test`)
- Swift のしきい値(`Config.swift`)が試作品と同じか
- Swift の判定が試作品と同じ結果になるか(`cd ios/StudyCore && swift test`)

## 利用について

ライセンスは付けていない。コードは閲覧できるが、著作権者の許可なく複製・改変・配布・利用することはできない。
