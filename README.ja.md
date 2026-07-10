# Ink Paper

[English](README.md) | [中文](README.zh-CN.md) | [日本語](README.ja.md)

> 軽量・ネイティブな macOS 静的壁紙ツール——システム壁紙を優先し、書けないときはデスクトップ下層ウィンドウで代替。

Ink Paper は Swift + AppKit で実装され、排他的な 2 つの動作モードを提供します。可能なときはシステムデスクトップ壁紙を設定し、システム壁紙が書き込めない／ロックされているときは、デスクトップアイコンの下に全画面ウィンドウを敷いて視覚的に壁紙として見せます。第 1 版はローカルの静的画像のみ対応、メニューバー常駐、ディスプレイごとに 1 ウィンドウです。

---

## なぜ作ったか

壁紙を変えるのは本来簡単なはずですが、macOS ではよくつまずきます。

- **システム壁紙を書けない** — 会社端末、構成プロファイル、権限やシステム状態の問題で、多くのツールはエラー表示か無言の失敗に終わります。
- **「偽壁紙」ウィンドウが操作を奪う** — 通常のウィンドウでデスクトップを覆うと、Dock・メニューバー・デスクトップアイコンのクリックを妨げやすいです。
- **マルチディスプレイで崩れる** — 外付けディスプレイの抜き差しや解像度変更のあと、ウィンドウがずれたりメイン画面だけになったりします。

Ink Paper はそのためにあります。

1. **書けるならシステムを使う**（モード A）。失敗・利用不可ならデスクトップ下層オーバーレイ（モード B）へ降格。モードは排他、切り替えはトランザクションでロールバック可能。
2. **オーバーレイは操作を奪わない** — Key Window にならない、クリック透過、デスクトップ層のスタックで Dock / メニューバー / デスクトップアイコンはそのまま使える。
3. **ディスプレイごとに 1 ウィンドウ**、接続・切断や解像度変化に合わせて再構築。
4. **ネイティブで性能優先** — 設定はローカルに永続化し起動時に復元。失敗時は操作可能なメッセージを出し、黙って失敗しない。

---

## できること

| 機能 | 説明 |
|------|------|
| **システム壁紙モード** | macOS のシステム静的壁紙を設定 / 読み取り |
| **オーバーレイ壁紙モード** | システムが書けないとき、デスクトップ下層の全画面画像ウィンドウで代替 |
| **自動 / 手動モード** | ヘルスチェックで推奨、または強制指定 |
| **マルチディスプレイ** | 全画面で同一画像、またはディスプレイごとに別画像 |
| **スケール** | fill / fit / stretch / center |
| **メニューバー** | 常駐メニューバーから画像選択とオン/オフ |
| **ログイン時起動** | ログイン時に起動し、前回の壁紙状態を復元（任意） |

> 今期の対象外：動画 / 動的 / Web 壁紙、Windows / Linux、オンラインギャラリー、複数画像のスケジュール切り替えなど。詳細は [技術要件ドキュメント](docs/technical-requirements.md) を参照。

---

## ダウンロードとインストール

[Releases](https://github.com/suilang/ink-paper/releases) から `.dmg` または `.zip` を入手し、`InkPaper.app` を「アプリケーション」へドラッグします。

現在の配布物は **Apple Developer 署名 / 公証なし** です。初回起動で Gatekeeper にブロックされた場合は、次のいずれかで開けます。

1. **右クリックで開く**：App を右クリック → **開く** → 確認（ダブルクリックしない）。
2. **システム設定**：「システム設定 → プライバシーとセキュリティ」→ **このまま開く**。
3. **隔離解除スクリプト**：

```bash
# 既定は /Applications/InkPaper.app
curl -fsSL https://raw.githubusercontent.com/suilang/ink-paper/main/scripts/unquarantine.sh | bash

# またはリポジトリ内で実行。App / DMG パスも可
./scripts/unquarantine.sh
./scripts/unquarantine.sh /Applications/InkPaper.app
./scripts/unquarantine.sh ~/Downloads/InkPaper-v0.2.0-macos.dmg
```

まだブロックされる場合は、手順 1 または 2 を併用してください。

---

## プロジェクトを開く

```bash
open InkPaper.xcodeproj
```

またはコマンドラインでビルド：

```bash
xcodebuild -scheme InkPaper -project InkPaper.xcodeproj \
  -configuration Debug \
  -derivedDataPath .derivedData build
```

- 最低 OS：macOS 13.0
- Bundle ID：`com.ink.InkPaper`

---

## ドキュメント

| ドキュメント | 説明 |
|--------------|------|
| [docs/technical-requirements.md](docs/technical-requirements.md) | 製品制約と実装ガイド（英語） |
| [docs/impl/README.md](docs/impl/README.md) | 実装済みコードの挙動（モジュール別・中国語） |

---

## ライセンス

本リポジトリは [MIT License](LICENSE) です。

著作権表示と許諾表示を残す限り、自由に使用・改変・再配布できます。ソフトウェアは「現状のまま」提供され、明示・黙示を問わずいかなる保証もありません。

---

## スポンサー

このプロジェクトが役に立ったら、作者にミルクティーをおごっていただけると嬉しいです。

<p align="center">
  <img src="docs/assets/wechat-pay.png" width="180" alt="WeChat 支払い QR" />
</p>

ご支援は本プロジェクトの維持・開発のみに使います。
