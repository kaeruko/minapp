# Phase 4: app lifecycle / catalog polish

Phase 4は、MVPの公開後運用を最低限使いやすくする仕上げです。

## できること

- 公開済み作品に対して「更新版ZIP」を追加する
- 更新版は同じ `app_id` の新しい `version_id` として保存する
- 下書きまたは先生の確認待ちが残っている間は、さらに次の版を作れない
- 先生が新しい版を承認すると、Android版では同じ作品の最新承認版だけを表示する
- 生徒は自分の作品を削除できる
- 削除はsoft deleteで、Android/Webの通常一覧から即座に消える
- 確認待ちの版がある作品は、レビュー途中の取り違えを防ぐため削除できない
- Android一覧はグループ、作者、更新日を見やすく表示する

## 削除の意味

MVPの「作品を削除」は物理削除ではなく `archived` への変更です。

理由:

- すでに先生が承認したimmutableな公開物を、その場で破壊しない
- 発行済みの10分launch tokenと競合しない
- 操作ミスからの復旧余地を残す

archivedになった作品は新しいlaunch tokenを発行できず、mobile catalogにも表示されません。S3オブジェクトの期限付き掃除はMVP後の運用機能とします。

## 既存データ互換

Phase 2で作った `APP#{app_id}/META` にはapp statusがありません。Phase 4ではstatusが無い既存作品を `active` として扱います。移行スクリプトは不要です。

過去に同じタイトルを別々にアップロードして別 `app_id` になった作品は自動マージしません。別作品を誤って統合する危険があるためです。不要な方をWebポータルの「作品を削除」で整理します。

## AWS反映

リポジトリ直下で:

```powershell
git pull
terraform -chdir=infra/terraform plan -out=tfplan-phase4
```

必ずplanを確認し、意図しないdestroyが無いことを確認してから:

```powershell
terraform -chdir=infra/terraform apply tfplan-phase4
```

Phase 4では lifecycle Lambda と3つのJWT保護ルートを追加し、mobile LambdaのhandlerをPhase 4 backendへ切り替えます。

## Android実行

```powershell
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url
cd apps\mobile
flutter pub get
flutter run --dart-define=MINAPP_API_BASE_URL=$apiBaseUrl
```

## E2E確認

1. 生徒でWebポータルにログイン
2. 公開済み作品の「更新版をアップロード」を押す
3. 新しいZIPを選ぶ
4. 新しい版をプレビューして公開申請
5. 先生でログインして承認
6. Android版を下へ引っ張って更新
7. 同じ作品が1件だけ表示され、新しい内容で起動することを確認
8. Webで「作品を削除」してAndroidを更新し、一覧から消えることを確認

## セキュリティ境界

Phase 3の境界は維持します。

- private S3
- Cognito tokenを作品WebViewへ渡さない
- 10分のlaunch token
- server-side membership確認
- 外部通信禁止CSP
- native bridgeなし

Versioningや削除によって、子どもの作品へ新しい権限は追加しません。
