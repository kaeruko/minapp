# みんアプ Android

Flutter製のAndroidクライアント。

Phase 0では、承認済みアプリ一覧のUIだけを置いている。ログイン、API接続、WebView起動はまだ有効にしない。

## 初回だけ: Androidプラットフォームを生成

このリポジトリではFlutter SDKのバージョン差分を手書きで固定しないため、`android/` はローカルのFlutter SDKから生成する。

PowerShellでリポジトリ直下から:

```powershell
.\scripts\bootstrap-mobile.ps1
```

スクリプトは次の条件で停止する。

- `flutter` コマンドが見つからない
- `apps/mobile/android` がすでに存在する
- `flutter create` が失敗する
- 生成物のapplication idが `jp.cloxs.min` になっていない

既存ファイルを別形式へ暗黙に置き換えたり、自動フォールバックしたりはしない。

## 実行

```powershell
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Google Play上のパッケージIDは `jp.cloxs.min` を使う。
