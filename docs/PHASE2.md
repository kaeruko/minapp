# Phase 2: 作品アップロードと公開承認

Phase 2では、生徒が静的WebアプリのZIPをアップロードし、先生へ公開申請し、先生が安全な短時間プレビューを確認して承認できるようにする。

## 生徒の流れ

1. 生徒IDでWebポータルへログインする
2. 所属グループを選ぶ
3. 作品名とZIPを選んでアップロードする
4. 自分の作品一覧でプレビューする
5. `公開申請` を押す
6. 状態が `先生の確認待ち` になる

## 先生の流れ

1. 先生IDでWebポータルへログインする
2. 公開申請を確認するグループを選ぶ
3. `プレビュー` で作品を確認する
4. 問題がなければ `承認して公開` を押す
5. 検証済みZIPがprivate published S3へコピーされ、状態が `approved` になる

承認済み作品をAndroid版のみんアプで一覧・起動する機能は次のPhaseで接続する。

## ZIP制約

MVPでは、アップロード可能なZIPを意図的に小さく限定する。

- ZIP本体: 2MB以下
- 展開後合計: 8MB以下
- 1ファイル: 4MB以下
- ファイル数: 100以下
- ZIP直下に `index.html` 必須
- 許可拡張子: HTML / CSS / JavaScript / JSON / TXT / PNG / JPEG / GIF / WebP / ICO
- path traversal、絶対パス、backslash pathを拒否
- symlinkを拒否
- 暗号化ZIPを拒否
- 重複ファイルパスを拒否
- CRC不整合を拒否

許可されないものを別形式として扱うfallbackはしない。

## プレビューの分離

作品ZIPを親WebアプリのDOMへ直接展開しない。

1. 認証済みユーザーがpreview APIを呼ぶ
2. Lambdaが作品所有者または担当先生であることを確認する
3. 32-byteの暗号学的乱数からpreview tokenを生成する
4. tokenは15分で論理的に期限切れになる
5. `/content/{token}/index.html` から必要なファイルだけLambdaがZIPから取り出す
6. Webポータルは返されたHTTPS URLを `sandbox="allow-scripts"` iframeで表示する

preview responseには次を含むCSPを付ける。

```text
connect-src 'none'
object-src 'none'
base-uri 'none'
form-action 'none'
frame-src 'none'
```

また `Referrer-Policy: no-referrer` を付ける。preview URLにCognito Access Tokenは含めない。

S3 bucketは引き続きpublic access blockを有効にしたまま使う。

## AWSへ反映

Phase 2をmainへ取り込んだ後、ローカルで:

```powershell
git pull
terraform -chdir=infra/terraform plan -out=tfplan
terraform -chdir=infra/terraform apply tfplan
```

`plan` でdestroyが出た場合はそのままapplyしない。

Phase 2で追加される主な変更:

- Lambdaコード更新
- Phase 2 protected API routes
- preview content route
- Lambdaからprivate S3 objectを読み書きする権限
- DynamoDB item update権限

## Webポータル

AWS反映後:

```powershell
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url
python tools\dev_server.py --api-base-url $apiBaseUrl
```

ブラウザ:

```text
http://127.0.0.1:4173
```

既存のPhase 1アカウントとグループをそのまま利用できる。
