<!--
  @file        README.ja.md
  @description SpectaDockPin README (日本語). 英語版 README.md・韓国語版 README.ko.md と同じ内容。
  @author      Kennt Kim
  @company     Calida Lab
  @created     2026-10-19
  @lastUpdated 2026-10-19
-->

# SpectaDockPin

[English](README.md) · [한국어](README.ko.md) · **日本語**

[![Release](https://img.shields.io/github/v/release/kennss/SpectaDockPin?color=2b9348)](https://github.com/kennss/SpectaDockPin/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/kennss/SpectaDockPin/total?color=2b9348)](https://github.com/kennss/SpectaDockPin/releases)
[![License: MIT](https://img.shields.io/github/license/kennss/SpectaDockPin)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-111)

<p align="center"><img src="Docs/img/icon.png" width="160" alt="SpectaDockPin のアイコン"></p>

ディスプレイを複数つないだ Mac では、Dock がポインタについて回ります。別の画面の下端にポインタを少し置くだけで、
Dock がそちらへ移ってしまいます。**SpectaDockPin は Dock を選んだディスプレイに留めておきます。** Dock を呼び出す
ポインタイベントだけを止め、それでも Dock がほかの画面に移っていたら連れ戻します。Calida Lab の Specta
シリーズの小さなメニューバーアプリです。

## ダウンロード

**[⬇ 最新の DMG をダウンロード](https://github.com/kennss/SpectaDockPin/releases/latest)**。開いて
**SpectaDockPin** をアプリケーションフォルダにドラッグしてください。Developer ID で署名し、Apple の公証を受けて
います。アップデートはアプリ自身が行います(メニューの **Check for Updates…**)。

初回起動時に、必要な権限をひとつだけ求めます。アプリにポインタの操作を許可するプライバシー設定です
(**アクセシビリティ**。macOS 27 では **Device Control and Data Access**)。そこで SpectaDockPin をオンにすると、
すぐに Dock を守り始めます。

> **この権限をオフにする前に、SpectaDockPin を終了してください。** アプリのイベントタップが動いている間に権限を
> オフにすると、キーボードとマウスの入力がすべて止まり再起動が必要になったという報告があり(macOS 15〜27)、
> まだ解決されていません。

## なぜ SpectaDockPin か

私はディスプレイ 3 台で仕事をしていますが、Dock がさっき使った画面へ何度も移ってしまいました。横の画面の下端に
ポインタを置くだけで、あるはずの場所から Dock が消えます。「ディスプレイごとに個別の操作スペース」をオフにすれば
直りますが、そうするとほかの画面のメニューバーやフルスクリーンアプリまで失います。

試したオープンソースの固定アプリは、どれも何かが足りませんでした。いちばん良いものでも、ファイルをドラッグして
いるときは Dock を通してしまい、下端 10 ピクセルの帯をまるごと止めるので画面下端のホバーが効かなくなりました。
スリープから復帰するたびにカーソルを動かすのに、Dock が本当に戻ったかは確かめませんでした。別のものは座標系を
取り違え、上下に並べた画面で見当違いの場所を止めていました。もうひとつは、macOS がイベントタップを一度止めると
二度と再開しませんでした。

そこでまず、Dock が実際にどう移動を決めているのかを測りました。そのうえで、それを止める最小の仕組みを作りました。
測定結果はすべて [`Docs/DESIGN.md`](Docs/DESIGN.md)(韓国語)にあります。

## 仕組み

- **最下段の 1 行だけ。** Dock がほかの画面へ移るのは、その画面のいちばん下の 1 ポイントの行にポインタイベントが
  0.4 秒ほど続いたときだけです。SpectaDockPin はまさにそのイベント(移動とドラッグ)だけを捨て、ほかには手を
  触れません。クリック、1 ピクセル上でのホバー、ホットコーナー、ほかのすべての端はそのまま使えます。
- **確かめてから直す。** スリープからの復帰、ディスプレイ構成の変更、アプリが動いていなかった間などに、Dock が
  別の画面へ移っていることがあります。SpectaDockPin は Dock の実際の位置を読み取ります。画面がロックされておらず、
  ボタンが押されておらず、マウスを動かしていないときだけ、固定したディスプレイの下端へポインタを下ろして Dock を
  連れ戻します。そのあとポインタを元の位置に戻し、Dock が着いたことを確かめます。何度試しても動かないときは、
  メニューにそう表示します。
- **意図して動かすときは Option。** Option を押しながら下端を押すと Dock を通します。そうして移した Dock は、
  **Move Dock Back Now** を選ぶまでそのままにします。
- **それ以外は何もしません。** キーボードは読まず、何も収集しません。ネットワークはアップデートの確認にだけ
  使います。

## メニュー

<p align="center"><img src="Docs/img/menu.png" width="295" alt="SpectaDockPin のメニュー"></p>

- **Pin To**:メインディスプレイ(既定。メインが変われば追従します)または接続中の任意のディスプレイ。選んだ
  ディスプレイを外しても覚えておき、つなぎ直すまではメインディスプレイが代わりを務めます。
- **Move Dock Back Now**、**Pause**、**Launch at Login**(自分でオンにするまではオフ)、**Check for
  Updates…**。
- 休んでいるときは、状態行にその理由が出ます。ディスプレイが 1 台だけのとき、Dock が左か右にあるとき、
  「ディスプレイごとに個別の操作スペース」がオフのとき、権限がないときです。

## 動作環境と制限

- macOS 14 以降。開発と測定は macOS 27、Apple Silicon、ディスプレイ 3 台で行いました。
- Dock が画面の下にあり、「ディスプレイごとに個別の操作スペース」がオンであること(オフのときは macOS が自分で
  Dock をメインディスプレイに置きます)。
- Apple が文書化していない現在の Dock の挙動に頼っています。macOS をアップデートしたあとは `tools/DockProbe` で
  測定をやり直せます。Dock が見つからないときは、推測せずに休みます。

## ソースからビルド

```sh
brew install xcodegen
xcodegen generate                    # SpectaDockPin.xcodeproj を生成(リポジトリには含まれません)
xcodebuild -scheme SpectaDockPin -destination 'platform=macOS' test
open SpectaDockPin.xcodeproj
```

まず `project.yml` の `DEVELOPMENT_TEAM` を自分のチームに変えてください。開発ビルドは `/Applications` から起動し、
毎回同じ証明書で署名してください。そうしないと、ビルドし直すたびに
権限が外れます。`scripts/release.sh` は署名・公証済みの DMG と Sparkle の appcast を作ります。`tools/DockProbe`
(`xcrun swift build`)は設計書の測定に使ったコマンドラインツールで、`tools/AppIcon/make_icon.swift` が
アイコンを描きます。

## ライセンス

[MIT](LICENSE) © 2026 Kennt Kim (Calida Lab)
