# みんアプ工房：ストア掲載画像の生成

[GitHub Actions → Kobo Store Assets](../../.github/workflows/kobo-store-assets.yml) を開いて
`Run workflow`（mainブランチ）を実行する。

成功すると、Artifacts の **kobo-store-assets** に以下のPNG画像がまとめられる。

```text
feature-graphic.png     1024x500   Google Play (RGB PNG)
iphone/01-home.png      1206x2622  iPhone 16 Pro
iphone/02-code-editor.png
ipad/01-home.png        2064x2752  iPad Pro 13-inch (M4)
ipad/02-code-editor.png
```

- iPhone/iPadはGitHubのmacOS runner上にiOS 26 simulatorを起動し、Flutterの
  `integration_test` で撮影する。画像は自動的に定められた画素数を検証する。
- ホームは実際の `KoboHomePage`、コード編集は実際の
  `KoboSourceEditorPage` を使用する。後者にはローカルの固定ZIPレスポンスを
  返すテスト用HTTPクライアントを使う。画面用のアカウントや秘密情報は不要。
  **アプリ全体をログインして撮影した画像ではない**。
- 生成物に不正なサイズ・画像形式・不足ファイル・透過ピクセルがあれば失敗し、
  別デバイスや拡大縮小で代用しない。
- フィーチャーグラフィックは `apps/mobile/assets/kobo/` の既存アートを再利用。
  Linux上でNoto Sans CJKをインストールして生成する。
- これは画像をArtifactsに生成するワークフロー。Play Consoleや
  App Store Connectへの**自動アップロードはしない**。
- 審査提出前に表示内容と最新UIとの一致を目視で確認し、必要に応じて
  スクリーンショットの文言や構成を調整する。
