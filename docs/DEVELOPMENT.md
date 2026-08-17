# 開発手順

Phase 0では、Flutter Android・Webポータル・Python Lambda・Terraformの土台を同じリポジトリで管理する。

## ディレクトリ

```text
apps/
  mobile/          Flutter Android
  web/             先生・生徒用Webポータル
backend/
  src/             Lambda本体
  tests/           backend tests
infra/
  terraform/       AWS IaC
tools/
  dev_server.py    Web + APIのローカル開発サーバ
scripts/
  bootstrap-mobile.ps1
  check.ps1
```

## 必要なコマンド

- Python 3.12+
- Flutter
- Terraform 1.6+
- AWS CLI（Terraformで実際にAWSへapplyするときのみ）

コマンドが不足している場合は、別コマンドへ自動で切り替えず停止する。

## Web + APIをローカルで起動

依存ライブラリなしで起動できる。

```powershell
python tools/dev_server.py
```

ブラウザで次を開く。

```text
http://127.0.0.1:4173
```

同じプロセスが `/api/health` をPhase 0 Lambda handlerへ渡すため、WebからAPI接続状態を確認できる。

## backend test

```powershell
python -m unittest discover -s backend/tests -v
```

Phase 0 APIで公開しているのは `GET /health` だけ。未知のルートは404、Lambda event自体が不正なら例外で停止する。

## Flutter

初回だけAndroidのプラットフォームファイルを、利用中のFlutter SDKから生成する。

```powershell
.\scripts\bootstrap-mobile.ps1
```

その後:

```powershell
cd apps\mobile
flutter pub get
flutter analyze
flutter test
flutter run
```

Play Consoleで確保したapplication idは `jp.cloxs.min`。

## Terraform

Phase 0でIaCはTerraformへ固定する。

最初に設定例をコピーし、値を確認してから実行する。

```powershell
Copy-Item infra\terraform\terraform.tfvars.example infra\terraform\terraform.tfvars
terraform -chdir=infra/terraform init
terraform -chdir=infra/terraform fmt -check
terraform -chdir=infra/terraform validate
terraform -chdir=infra/terraform plan
```

`apply` は自動では実行しない。`plan`を確認した後に明示的に実行する。

```powershell
terraform -chdir=infra/terraform apply
```

Phase 0で作るAWSリソース:

- Cognito User Pool（管理者作成のみ、メール必須なし）
- Cognito App Client
- DynamoDB
- private S3 upload bucket
- private S3 published bucket
- Lambda
- API Gateway HTTP API
- CloudWatch Logs

CloudFrontはPhase 0ではまだ作らない。公開コンテンツへの短寿命認可方式を実装する前に配信用URLを公開しないため。

## 一括チェック

PowerShell:

```powershell
.\scripts\check.ps1
```

Python、Flutter、Terraformのいずれかが失敗したらその場で終了する。異なる実装や設定への自動フォールバックはしない。
