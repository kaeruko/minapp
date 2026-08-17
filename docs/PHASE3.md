# Phase 3: Android catalog / launch

Phase 3では、Phase 2で先生が承認したWebアプリをAndroid版「みんアプ」に表示し、タップして起動できるようにする。

## 体験

1. Android版みんアプで先生または生徒IDを使ってログインする
2. activeな所属グループで承認済みの作品だけが一覧に出る
3. 作品をタップすると、サーバーがそのユーザーのMembershipと作品の承認状態を再確認する
4. 成功時だけ10分有効の高エントロピーlaunch URLを発行する
5. Androidはlaunch URLだけをWebViewへ渡し、Cognito access tokenは渡さない
6. WebViewは同一host・同一launch token配下だけを開ける

## API

既存のWebポータル用Lambdaとは分離し、Android配信用に最小権限のLambdaを追加する。

JWT必須:

```text
GET  /mobile/apps
POST /mobile/apps/{app_id}/versions/{version_id}/launch
```

launch content:

```text
GET /launch/{token}/{proxy+}
```

`/launch/*` はJWTを要求しない。代わりにサーバー側DynamoDBへ保存した高エントロピーtokenをbearer credentialとして使い、10分経過後は同期的に404で拒否する。Cognito tokenをWebViewやURLへ埋め込まないための構成。

## 認可

`GET /mobile/apps` は認証ユーザーのactive Membershipを読み、そのグループのうち `approved` のversionだけを返す。

launch作成時は次を毎回再確認する。

- 認証アカウントがみんアプ上でactive
- versionが存在する
- versionが `approved`
- 認証ユーザーが対象groupへactive Membershipを持つ
- 承認時に確定した `published_key` が存在する

JWTが正しいだけでは別グループの作品を起動できない。

## 配信

Phase 2で承認したZIPはprivate published S3 bucketにimmutableなキーで保存している。

Phase 3の専用Lambdaはlaunch tokenが有効な場合だけpublished ZIPを読み、要求されたファイルをZIPから取り出して返す。取得時にも次を確認する。

- ZIPは設定上限以下
- SHA-256が承認時のmetadataと一致
- ZIP safety validationを再実行
- requested pathがZIP内の許可済みファイルに存在
- 1ファイル上限以下

レスポンスでは `Cache-Control: no-store` とCSPを付け、`connect-src 'none'`, `form-action 'none'`, `object-src 'none'` を強制する。Permissions Policyでもcamera / microphone / geolocationを無効化する。

## Android WebView

Android側ではchild appを信用しない。

- JavaScriptは作品のため有効
- JavaScript channel/native bridgeは作らない
- Cognito access tokenをWebViewへ渡さない
- launch前にcookie / localStorage / cacheを削除
- HTTPS以外を拒否
- launch URLと同じhost・port以外を拒否
- 同じ `/launch/{token}/` prefix以外を拒否

このMVPでは作品間の状態分離を優先し、WebViewを閉じたあとのlocalStorage/cookie永続化を提供しない。

## AWSへ反映

まず最新コードを取得する。

```powershell
git pull
```

planを保存する。

```powershell
terraform -chdir=infra/terraform plan -out=tfplan
```

`destroy` が0であることと、Phase 3用mobile Lambda / IAM / API Gateway routesの追加、およびbackend ZIP更新に伴う既存Lambdaのin-place更新だけであることを確認する。

問題なければ、保存した同じplanをapplyする。

```powershell
terraform -chdir=infra/terraform apply tfplan
```

古いplanファイルをapplyしない。stateが変化した場合はplanを作り直す。

## Androidを実行

すでに `apps/mobile/android` がある場合、INTERNET permissionを明示的に設定する。

```powershell
.\scripts\configure-mobile-android.ps1
```

Android platformをまだ生成していない場合だけ:

```powershell
.\scripts\bootstrap-mobile.ps1
```

API URLをTerraform stateから取得する。

```powershell
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url
```

実行する。

```powershell
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=MINAPP_API_BASE_URL=$apiBaseUrl
```

`MINAPP_API_BASE_URL` はHTTPSのabsolute URLを明示する。指定がなければアプリは起動時に停止し、localhostや別APIへ自動フォールバックしない。

## E2E確認

Phase 2で承認済み作品があるユーザーでAndroidへログインする。

期待結果:

```text
ログイン
  ↓
承認済み作品一覧
  ↓
作品カードをタップ
  ↓
10分launch URLを発行
  ↓
WebViewでindex.htmlを表示
```

作品内のボタンなどJavaScriptは動作してよい。一方で外部URLへ移動しようとしてもWebView navigation policyで拒否され、`fetch()` 等の外部通信はCSPで拒否される。

## Phase 3でまだやらないこと

- Refresh Tokenの端末永続化
- オフライン起動
- launch URLの更新をWebView内で自動化
- child appのlocalStorage永続化
- CloudFrontによる配信最適化
- child appからの任意外部API
- native bridge
