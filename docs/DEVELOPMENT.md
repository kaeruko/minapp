# 開発手順

Phase 1では、Phase 0の土台に **ID + パスワード認証、先生 / 生徒、グループ、Membership、生徒ID発行** を追加する。

## ディレクトリ

```text
apps/
  mobile/              Flutter Android
  web/                 先生・生徒用Webポータル
backend/
  src/
    handler.py          API入力検証・routing
    aws_backend.py      Cognito / DynamoDB adapter
    errors.py           API error model
  tests/
infra/
  terraform/           AWS IaC
tools/
  dev_server.py        Web + APIのローカル開発サーバ
  bootstrap_teacher.py 最初の先生アカウント作成
scripts/
  bootstrap-mobile.ps1
  check.ps1
```

## 必要なコマンド

- Python 3.12+
- Flutter
- Terraform 1.6+
- AWS CLI（AWSへdeployするとき）
- boto3（最初の先生アカウント作成ツールを使うとき）

コマンドや設定が不足している場合は、別実装・別リージョン・別認証方式へ自動で切り替えず停止する。

## backend test

```powershell
python -m unittest discover -s backend/tests -v
```

Phase 1では、認証入力、API Gatewayから渡されるJWT subject、teacher/studentの認可、グループ所属、生徒発行、仮パスワード再発行、所属解除をテストする。

## Terraform

設定例をコピーし、値を確認してから実行する。

```powershell
Copy-Item infra\terraform\terraform.tfvars.example infra\terraform\terraform.tfvars

terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan
```

`apply` は自動実行しない。`plan`を確認した後に明示的に実行する。

```powershell
terraform -chdir=infra/terraform apply
```

Phase 1でAPI Gatewayに追加される公開route:

```text
GET  /health
POST /auth/login
POST /auth/change-password
```

次のrouteはCognito JWT authorizer必須:

```text
GET    /me
GET    /groups
POST   /groups
GET    /groups/{group_id}/members
POST   /groups/{group_id}/students
POST   /users/{user_id}/reset-password
DELETE /groups/{group_id}/members/{user_id}
```

JWTが正しいだけではグループ操作を許可しない。Lambda側でもDynamoDBのMembershipを毎回確認する。

## 最初の先生アカウントを1人だけ作る

一般ユーザーによる先生登録は作らない。最初の先生だけ運営者が明示的にbootstrapする。

まずツール用依存関係をインストールする。

```powershell
python -m pip install -r tools\requirements.txt
```

Terraformの出力を取得する。

```powershell
$userPoolId = terraform -chdir=infra/terraform output -raw cognito_user_pool_id
$tableName = terraform -chdir=infra/terraform output -raw data_table_name
```

Terraformで指定したAWSリージョンを明示して実行する。例として `ap-northeast-1` を使う場合:

```powershell
python tools\bootstrap_teacher.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --login-id teacher-admin `
  --region ap-northeast-1
```

成功時だけ、先生のIDと仮パスワードが表示される。仮パスワードはこの出力で一度だけ確認し、安全な方法で先生本人へ渡す。

Cognito作成後にDynamoDB登録が失敗した場合、ツールは作成したCognitoユーザーを削除して停止する。削除にも失敗した場合は、その事実を含む例外で停止する。

## Webポータルをtenant APIにつなぐ

### 単一tenantを明示して確認する

deploy後のAPI URLを取得する。

```powershell
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url
```

Web開発サーバを、接続先を**明示して**起動する。

```powershell
python tools\dev_server.py --api-base-url $apiBaseUrl
```

ブラウザ:

```text
http://127.0.0.1:4173
```

この固定tenantモードでは `/api/*` を指定したHTTPS APIへproxyする。特定tenantだけを切り分けたい開発・障害調査に使う。

### Directory経由で教室を選ぶ

Phase 6の複数tenant動作を確認するときは、tenant API URLではなく中央Directoryだけを明示する。

```powershell
$directoryApi = "https://directory.example.com"
python tools\dev_server.py --directory-api-base-url $directoryApi
```

このモードではWebポータルが最初に教室コードを求める。

```text
教室コード
  -> 中央Directoryでtenant descriptorを解決
  -> tenant_idを使ってWeb proxyの接続先を選択
  -> /tenant-infoでtenant_id / protocol一致を検証
  -> その教室のID + パスワードでログイン
```

ログイン画面とログイン後の画面には現在の教室名と「教室を変更」を表示する。教室変更時はAccess Token、初回パスワード変更challenge、ユーザー/グループ状態、tenantとのtoken紐付けを破棄してから別教室を選ばせる。旧tenantのAccess Tokenを新tenantへ持ち越さない。

ブラウザから任意のtenant API URLを指定する機能は作らない。`/api/*` の実際の転送先は、HttpOnlyなtenant routing cookieの `tenant_id` を中央Directoryで再解決して決める。Directory descriptorの `api_base_url` はserver側で既存Directory validationと同等に検証し、未知field・tenant不一致・不正URL・未対応protocolはfail closedする。

開発サーバは `--api-base-url` と `--directory-api-base-url` を同時指定できない。どちらも省略した場合だけローカルLambda handlerを使う。ローカルhandlerは `/health` の確認には使えるが、AWS環境変数・boto3を設定していない状態で認証APIを呼ぶと停止する。リモートAPIへ自動フォールバックはしない。

WebポータルのPhase 1機能:

1. 先生ID + 仮パスワードでログイン
2. 初回ログイン時に本人用パスワードへ変更
3. グループ作成
4. 生徒ID + 仮パスワード発行
5. 生徒一覧
6. 生徒の仮パスワード再発行
7. 生徒の所属解除
8. 生徒自身もID + パスワードでログインして所属グループを確認

Access Tokenと選択済みtenant descriptorは `sessionStorage` に保持する。Access Tokenは選択中tenant IDにも紐付け、tenantが一致しない状態では認証付きAPIを送らない。教室コードそのものは保存しない。ページ内に外部scriptを読み込まない。Refresh Tokenによる自動延長はPhase 1では実装せず、有効期限後は再ログインする。

## Flutter

Androidプラットフォームファイルがまだない場合だけ:

```powershell
.\scripts\bootstrap-mobile.ps1
```

チェック:

```powershell
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Phase 1の認証・グループ管理はまずWebポータルでend-to-end確認する。AndroidへのCognitoログイン接続は、承認済みアプリ一覧APIと一緒に次のクライアント統合で行う。

Play Consoleで確保したapplication idは `jp.cloxs.min`。

## 一括チェック

PowerShell:

```powershell
.\scripts\check.ps1
```

Python、Web JavaScript、Flutter、Terraformのいずれかが失敗したらその場で終了する。異なる実装や設定への自動フォールバックはしない。

## Phase 1のデータモデル

認証subjectとアプリ内user idは分離する。

```text
AUTH#{cognito_sub} / PROFILE
  -> user_id, login_id, role, status

USER#{user_id} / PROFILE
  -> auth_subject, login_id, role, status

USER#{user_id} / GROUP#{group_id}
  -> Membership

GROUP#{group_id} / META
  -> group

GROUP#{group_id} / MEMBER#{user_id}
  -> Membership
```

生徒作成時は、DynamoDB側の4 itemをtransactionで作る。途中まで作って成功扱いにはしない。
