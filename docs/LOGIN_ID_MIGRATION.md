# ログインIDの変更

みんアプの権限はログインIDの文字列ではなく、DynamoDBに保存された `role` (`teacher` / `student`) で判定する。

そのため、次のIDはすべてログインIDの形式として利用できる。

- `admin`
- `yamada`
- `suzuki`

既存の `teacher-admin` や `student-xxxxxxxx` を変更する場合は、Cognitoのusernameを直接renameできないため、`tools/rename_login_id.py` を使う。

このツールは同じアプリ内 `user_id` と `role` を維持したまま、新しいCognitoユーザーを作成し、DynamoDB内の `auth_subject` / `login_id` / `owner_login_id` を更新する。既存のグループ所属や作品の所有者IDは `user_id` ベースなので維持される。

## 事前確認

```powershell
python -m pip install -r tools\requirements.txt

$userPoolId = terraform -chdir=infra/terraform output -raw cognito_user_pool_id
$tableName = terraform -chdir=infra/terraform output -raw data_table_name
```

まず `--apply` なしで計画だけ確認する。

```powershell
python tools\rename_login_id.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --old-login-id teacher-admin `
  --new-login-id admin `
  --region us-west-2
```

出力された `user_id` / `role` / `affected_dynamodb_items` を確認する。

## adminへ変更

```powershell
python tools\rename_login_id.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --old-login-id teacher-admin `
  --new-login-id admin `
  --region us-west-2 `
  --apply
```

成功時に新しい仮パスワードが一度だけ表示される。`admin` で初回ログインし、通常の初回パスワード変更を行う。

## 生徒IDを変更

実際の現在IDを `--old-login-id` に指定する。

```powershell
python tools\rename_login_id.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --old-login-id student-12345678 `
  --new-login-id yamada `
  --region us-west-2 `
  --apply

python tools\rename_login_id.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --old-login-id student-87654321 `
  --new-login-id suzuki `
  --region us-west-2 `
  --apply
```

各ユーザーごとに新しい仮パスワードが発行される。

## fail-fastの動作

次の場合は処理を停止する。

- 旧Cognitoユーザーが存在しない
- 新しいログインIDがすでにCognitoに存在する
- Cognito subjectとDynamoDBのユーザー情報が一致しない
- 同じ旧ログインIDに対応するDynamoDBユーザーが0件または複数件ある
- 1回のDynamoDB transaction (100操作) に収まらない

Cognito新規作成後にDynamoDB更新が失敗した場合は、新規Cognitoユーザーを削除して停止する。DynamoDB更新後に旧Cognitoユーザー削除が失敗した場合は、DynamoDBを元の状態へ戻し、新規Cognitoユーザーを削除して停止する。ロールや入力形式を暗黙に変更して処理を継続しない。
