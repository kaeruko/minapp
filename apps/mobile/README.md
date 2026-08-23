# みんアプ Android

Flutter製のAndroidクライアント。

Phase 6では、最初に中央Directoryへ教室コードを送ってtenant APIを解決し、`/tenant-info` で同じimmutable `tenant_id` を返すことを確認してから、既存のID + パスワードLogin / Catalog / Launchへ進む。

## 初回だけ: Androidプラットフォームを生成

このリポジトリではFlutter SDKのバージョン差分を手書きで固定しないため、`android/` はローカルのFlutter SDKから生成する。

PowerShellでリポジトリ直下から:

```powershell
.\scripts\bootstrap-mobile.ps1
```

すでに `apps/mobile/android` がある場合は再生成せず、必要なINTERNET permissionだけ明示的に確認・追加する。

```powershell
.\scripts\configure-mobile-android.ps1
```

## 実行

中央Directoryをdeploy済みにして、その固定URLをbuild-time defineで渡す。

```powershell
$directoryApi = terraform -chdir=infra/directory output -raw directory_api_base_url
.\scripts\configure-mobile-android.ps1
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run --dart-define=MINAPP_DIRECTORY_BASE_URL=$directoryApi
```

`MINAPP_DIRECTORY_BASE_URL` が無い場合や、public HTTPS base URLとして不正な場合は起動時に停止する。ユーザーへ任意API URLを入力させず、別Directoryやtenant APIへ自動フォールバックしない。

初回起動では先生から配布された教室コードを入力する。Directory descriptor受信後にtenant `/tenant-info` を検証し、成功したdescriptorだけを端末へ保存する。

### 公式join link

公式join domainを用意した場合だけ、そのoriginをbuild時に固定できる。

```powershell
flutter run `
  --dart-define=MINAPP_DIRECTORY_BASE_URL=$directoryApi `
  --dart-define=MINAPP_JOIN_BASE_URL=https://<official-join-domain>
```

このdefineを設定したbuildでは、手入力コードに加えて次の形だけを受け付ける。

```text
https://<official-join-domain>/c/XXXX-XXXX-XXXX
```

join linkから使うのはclassroom codeだけで、URLをtenant APIとして扱わない。host、scheme、port、pathが固定originと完全一致しないURL、query/fragment付きURL、余分なpathを持つURLは拒否する。`MINAPP_JOIN_BASE_URL` を設定していないbuildではURL入力自体を拒否し、教室コードだけを受け付ける。

### 制作・提出ポータル

公式の制作・提出Webポータルを用意したbuildでは、そのoriginをbuild時に固定する。

```powershell
flutter run `
  --dart-define=MINAPP_DIRECTORY_BASE_URL=$directoryApi `
  --dart-define=MINAPP_CREATOR_PORTAL_BASE_URL=https://<creator-portal-domain>
```

このdefineを設定した場合だけ、Androidの右上メニューに「アプリを作る・提出する」を表示し、外部ブラウザで公式ポータルを開く。URLはユーザー入力やtenant responseから受け取らず、public HTTPS originとしてbuild時に固定する。不正なURLを設定したbuildは起動時に停止する。

端末へ保存するのは次だけ:

```text
tenant_id
display_name
api_base_url
api_protocol_version
config_revision
verified_at
expires_at
```

パスワード、Cognito access token、launch tokenは保存しない。access tokenはこれまで通りmemory only。

V1ではdescriptor TTLのclient許容上限を24時間とする。有効期限内のverified cacheはDirectory障害中でも利用できるが、期限切れ時はDirectory refreshと`/tenant-info`再検証が必須。失敗時にexpired cacheへsilent fallbackしない。

通常のログアウトでは選択中の教室を維持する。「教室を変更」ではaccess token/pending login stateを破棄し、WebView cookie/localStorage/cacheと保存済みtenant descriptorを削除して教室コード入力へ戻る。

## 安全境界

- production buildのDirectory base URLはbuild時に固定する
- classroom codeやjoin linkから任意tenant URLを受け取らない
- 公式join originを使う場合もbuild時に固定し、`/c/{code}` 以外を拒否する
- Directory responseのtenant URLをHTTPS/public DNS/default port/no pathとして再検証する
- Directory descriptorとtenant `/tenant-info` の`tenant_id` / protocolが一致しない場合はLoginを開始しない
- 未知のDirectory schema / tenant protocol / JSON fieldを推測して受理しない
- AndroidはCognito access tokenをメモリだけに保持し、作品WebViewへ渡さない
- 作品起動時にサーバーが短寿命URLを発行する
- published S3 bucketはprivateのまま
- WebViewにJavaScript channel/native bridgeを作らない
- WebViewは起動URLと同じhost・同じlaunch token配下へのnavigationだけ許可する
- 作品を開く前にWebViewのcookie・localStorage・cacheを消し、別作品との共有状態を残さない
- Android側からカメラ、位置情報、マイク等を作品へ公開しない

Google Play上のパッケージIDは `jp.cloxs.min` を使う。

## ビルトインアプリ

公式サンプルは `lib/builtin_apps.dart` の `builtInApps` にまとめて定義する。
カタログはこの一覧を検索・反復表示するため、アプリごとの専用分岐は追加しない。

各アプリは `assets/builtin/<asset_name>/index.html` の単一HTMLとして配置し、同じパスを
`pubspec.yaml` にも明示する。命名規則に合わないパスと外部サイトへの遷移は
`BuiltInWebViewPage` で拒否し、bundleに存在しないassetは別経路へフォールバックせず
読み込みエラーとして表示する。
