# みんアプ Android

Flutter製のAndroidクライアント。

Phase 3では、ID + パスワードでログインし、参加グループの承認済みWebアプリを一覧表示して、安全な短寿命URLをWebViewで起動する。

## 初回だけ: Androidプラットフォームを生成

このリポジトリではFlutter SDKのバージョン差分を手書きで固定しないため、`android/` はローカルのFlutter SDKから生成する。

PowerShellでリポジトリ直下から:

```powershell
.\scripts\bootstrap-mobile.ps1
```

すでに `apps/mobile/android` がある場合は再生成せず、Phase 3で必要なINTERNET permissionだけ明示的に確認・追加する。

```powershell
.\scripts\configure-mobile-android.ps1
```

## 実行

AWSへPhase 3を反映したあと、リポジトリ直下でAPI URLを取得する。

```powershell
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url
.\scripts\configure-mobile-android.ps1
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=MINAPP_API_BASE_URL=$apiBaseUrl
```

`MINAPP_API_BASE_URL` が無い場合やHTTPSでない場合は起動時に停止する。別のAPIへ自動フォールバックしない。

## Phase 3の安全境界

- AndroidはCognito access tokenをメモリだけに保持し、作品WebViewへ渡さない
- 作品起動時にサーバーが10分だけ有効な高エントロピーURLを発行する
- published S3 bucketはprivateのまま
- WebViewにJavaScript channel/native bridgeを作らない
- WebViewは起動URLと同じhost・同じlaunch token配下へのnavigationだけ許可する
- 作品を開く前にWebViewのcookie・localStorage・cacheを消し、別作品との共有状態を残さない
- レスポンスCSPで外部通信、form送信、object埋め込みを拒否する
- Android側からカメラ、位置情報、マイク等を作品へ公開しない

MVPでは作品間の状態分離を優先するため、Android WebViewを閉じて別作品を開くとlocalStorage/cookieは保持されない。

Google Play上のパッケージIDは `jp.cloxs.min` を使う。
