# Phase 5 design: runtime capabilities / Data API

Phase 5は、みんアプを初心者向けの静的Webアプリ共有だけでなく、レベルの高いプログラミング教室で「保存できるWebアプリ」「APIを使うWebアプリ」へ段階的に発展させるための設計です。

この文書は設計だけを定義します。Phase 5の最初の実装対象は `data` capability（DB保存）です。外部API、生成AI、ファイル保存は同じ権限モデルへ後から追加します。

## 1. 前提

- ネイティブの「みんアプ」は共通アプリとして配布する。
- 教室ごとの実データ環境は独立したAWS環境を前提とする。
- 子どもの作品は引き続き untrusted code として扱う。
- 子どものJavaScriptへAWS access key、DB credential、Cognito access tokenを渡さない。
- Basic作品では現在の `connect-src 'none'` を維持する。
- capabilityを許可した作品だけ、許可した経路へ通信できる。
- native JavaScript bridgeは導入しない。
- capabilityを使わない既存作品は移行不要で、そのまま動作する。

## 2. 目標

### Basic

HTML / CSS / JavaScriptだけを実行する現在のモード。

- 外部通信なし
- 永続データなし
- 端末機能なし
- 最も安全な既定値

### Data

みんアプが用意するData APIだけを利用できるモード。

例:

- 掲示板
- 投票
- ランキング
- ToDo
- 簡単な出欠
- ミニゲームのスコア保存

### 将来のcapability

同じ仕組みへ以下を追加できるようにする。

- `external_api`: 先生が許可した外部HTTP APIへのproxy
- `ai`: みんアプ経由の生成AI API
- `file_storage`: 作品専用ファイル保存

Phase 5ではこれらを実装しない。

## 3. capabilityは「レベル」ではなく権限の集合として持つ

UIでは「Basic」「Data」「AI」などのコース表示をしてよいが、保存形式は個別のcapabilityにする。

例:

```json
{
  "static_web": true,
  "data": true,
  "external_api": false,
  "ai": false,
  "file_storage": false
}
```

理由:

- 「DBは使うがAIは使わない」のような組み合わせが必要になる。
- 将来capabilityを増やしても既存データ形式を壊しにくい。
- 教室の授業方針に合わせて細かく制御できる。

## 4. 権限は3段階で絞る

実効権限は次の積集合にする。

```text
AWS環境で有効な機能
        ∩
グループで先生が許可した機能
        ∩
作品が申請し、先生が承認した機能
        ↓
      実効権限
```

### 4.1 AWS環境の上限

教室ごとのTerraform variableで機能そのものを有効/無効にする。

例:

```hcl
runtime_capabilities = {
  data         = true
  external_api = false
  ai           = false
}
```

この層がfalseなら、管理画面から有効化できない。

### 4.2 グループポリシー

先生がグループ単位で授業中に使える機能を選ぶ。

例:

```text
6年2組

[✓] HTML/CSS/JavaScript
[✓] データ保存
[ ] 外部API
[ ] 生成AI
[ ] ファイル保存
```

### 4.3 作品ごとのgrant

Dataを許可しているグループでも、全作品へ自動的にDB権限を渡さない。

作品がcapabilityを申請し、先生が公開承認時に確認する。

## 5. 作品manifest

ZIP直下に任意の `minapp.json` を置けるようにする。

Basic作品はmanifestなしでよい。

Dataを使う作品は明示的に申請する。

例:

```json
{
  "schema_version": 1,
  "capabilities": {
    "data": {
      "collections": {
        "messages": {
          "operations": ["list", "create"],
          "max_items": 200
        },
        "votes": {
          "operations": ["list", "create", "update"],
          "max_items": 100
        }
      }
    }
  }
}
```

### manifestのルール

- 未知のキーはrejectする。
- 未知のschema versionはrejectする。
- collection名は `[a-z][a-z0-9_-]{0,31}` のみ。
- operationは明示的allow list。
- manifestは申請であって権限そのものではない。
- 先生が申請より強い権限を追加することはできない。
- 先生は申請された権限を削ることはできる。

## 6. DBへ直接接続させない

禁止:

```text
子どものWebアプリ
   ↓ AWS credential / DB password
DynamoDB / RDS
```

理由:

- JavaScriptへ埋めたsecretは利用者から取得できる。
- 作品Aから作品Bのデータへアクセスされる危険がある。
- quota、監査、削除、授業単位の停止を制御できない。

採用:

```text
子どものWebアプリ
        │
        │ same-origin fetch
        ▼
  MinApp Runtime API
        │
        ├─ launch token検証
        ├─ app_id導出
        ├─ current grant確認
        ├─ collection / operation確認
        ├─ quota確認
        └─ payload検証
        │
        ▼
専用 DynamoDB runtime table
```

## 7. launch tokenをapp-scoped runtime credentialとして利用する

現在の10分launch tokenを拡張する。

launch tokenには最低限以下を保存する。

```text
app_id
version_id
group_id
issued_to_user_id
expires_at
```

Data APIではclientから `app_id` を受け取らない。

必ずlaunch tokenからapp_idを導出する。

これにより、作品側がURLパラメータを書き換えて別作品のDBを読むIDORを防ぐ。

launch tokenはCognito tokenではない。仮に作品JavaScriptがtoken文字列を読めても、できることは「現在の作品へ許可された短時間のruntime操作」だけに限定する。

## 8. same-origin Data API

Data capability有効時だけ、launch contentのCSPを次へ変更する。

Basic:

```text
connect-src 'none'
```

Data:

```text
connect-src 'self'
```

外部hostは許可しない。

API route例:

```text
GET    /launch/{token}/__minapp/data/{collection}
POST   /launch/{token}/__minapp/data/{collection}
PUT    /launch/{token}/__minapp/data/{collection}/{item_id}
DELETE /launch/{token}/__minapp/data/{collection}/{item_id}
```

重要:

- `/launch/{token}` 配下だけなのでsame-originで利用できる。
- Cognito Authorization headerは不要。
- tokenからapp/group/userをserver側で決定する。
- `collection` とoperationは現在のgrantで毎回検証する。
- capability revokeを10分待たず反映するため、current grantも毎リクエスト確認する。

## 9. JavaScript SDK

授業ではREST APIを直接書かなくても使える小さなSDKを用意する。

作品側:

```html
<script src="./__minapp/sdk.js"></script>
```

`index.html` が `/launch/{token}/index.html` で開かれるため、相対URLは自動的に現在のtoken配下へ解決される。

例:

```js
await minapp.collection("messages").add({
  text: "おはよう！"
});

const page = await minapp.collection("messages").list();

await minapp.collection("messages").update(itemId, {
  text: "書き直したよ"
});

await minapp.collection("messages").remove(itemId);
```

SDKはcredentialを持たず、現在のlocationからsame-origin endpointを呼ぶだけにする。

上級授業ではSDKを使わず、同じREST APIを `fetch()` で直接呼べる。

## 10. runtime DynamoDBは管理データと別テーブルにする

現在のユーザー、グループ、作品メタデータを保存するtableと、生徒作品が自由に書くruntime data tableを分離する。

理由:

- untrusted workloadのblast radiusを小さくする。
- IAMを分離できる。
- runtime dataだけをquota/TTL/バックアップ方針変更できる。
- 教室解約時や作品削除時に掃除しやすい。

Terraform例の概念:

```text
minapp-dev-data          # control plane
minapp-dev-runtime-data  # child app data
```

### runtime item key

```text
PK = APP#{app_id}#COLL#{collection}
SK = ITEM#{item_id}
```

item内部:

```json
{
  "item_id": "...",
  "created_at": "...",
  "updated_at": "...",
  "created_by": "server-side user id",
  "data": {
    "text": "おはよう"
  },
  "item_bytes": 123
}
```

`created_by` はserver-side監査用で、通常のlistレスポンスでは返さない。

## 11. MVP Data APIのデータモデル

最初はNoSQLをそのまま自由操作させない。

許可する値:

- string
- number
- boolean
- null
- 上記からなるobject / array

禁止:

- binary
- Infinity / NaN
- 深すぎるnest
- 巨大array
- reserved metadata fieldの上書き

MVPでは任意field検索を提供しない。

```text
list → created_at順のpage取得
get  → item_id指定
create
update
remove
```

任意query/indexは次段階でschema宣言と一緒に設計する。

## 12. quota

最初からhard limitを入れる。

初期値案:

```text
1 appあたり collection数     5
1 collectionあたり item数    500
1 item                       4 KiB
1 app合計                    1 MiB
list 1回                     最大50件
JSON request                 最大16 KiB
```

値はTerraformまたは教室設定で引き下げ可能にする。

quota超過時はfail fastで `409 quota_exceeded` または `413 item_too_large` を返す。自動削除や古いデータのsilent evictionはしない。

### quota counter

collectionごとにserver-managed counter itemを置き、create/update/deleteとcounter更新をDynamoDB transactionで行う。

```text
PK = APP#{app_id}#COLL#{collection}
SK = META

item_count
bytes_used
```

これにより並行writeでもhard limitを超えにくくする。

## 13. teacher UI

### グループ設定

```text
高度な作品機能

データ保存        [ON]
外部API           [OFF]
生成AI            [OFF]
ファイル保存      [OFF]
```

AWS環境で無効な機能はtoggle自体をdisabledにする。

### レビュー画面

公開申請時に通常のプレビューだけでなく、requested capabilityを表示する。

```text
この作品が要求している機能

データ保存
  messages: 読み取り / 追加
  votes: 読み取り / 追加 / 更新

[権限を承認して公開]
```

先生が理解せず強い権限を付けることを避けるため、既定はgrantなし。

manifestに要求がある場合だけ選択可能にする。

## 14. capability保存

control tableへ次を追加する。

### Group policy

```text
PK GROUP#{group_id}
SK RUNTIME_POLICY
```

例:

```json
{
  "data_enabled": true,
  "external_api_enabled": false,
  "ai_enabled": false
}
```

### App grant

```text
PK APP#{app_id}
SK RUNTIME_GRANT
```

例:

```json
{
  "status": "active",
  "manifest_version_id": "...",
  "data": {
    "messages": ["list", "create"],
    "votes": ["list", "create", "update"]
  },
  "approved_by": "...",
  "approved_at": "..."
}
```

grantはversionに紐付ける。

新versionでmanifestが変わった場合、以前のgrantを自動継承しない。先生が再度確認する。

## 15. revoke

先生がgroupのData機能をOFFにした場合、以後のData APIを即座に403にする。

作品をarchiveした場合も即座に403。

既に発行したlaunch tokenそのものは10分まで存在してよいが、runtime APIはcurrent group policy / app grant / app statusを毎回確認するため、書き込み権限は即時停止する。

## 16. 監査

runtime data本文を中央ログへ大量保存しない。

最低限の操作ログだけ残す。

例:

```text
request_id
app_id
group_id
operation
collection
status_code
item_bytes
```

ログに以下を出さない。

- Cognito token
- launch token全文
- password
- runtime data本文

必要ならtokenはhashの先頭数文字だけで相関する。

## 17. Data APIの認可順序

すべてのruntime requestで順序を固定する。

1. token形式検証
2. launch token存在 / expires_at確認
3. app active確認
4. versionが現在launch可能か確認
5. group membership / group policy確認
6. app grant確認
7. collection allow list確認
8. operation allow list確認
9. request payload検証
10. quota確認
11. DynamoDB operation

どこか一つでも不整合ならfallbackしない。

## 18. threat model

### 作品Aから作品Bを読む

対策: app_idはrequestから受け取らずlaunch tokenから導出。

### JavaScriptからAWS credentialを盗む

対策: credentialを作品へ一切渡さない。

### launch tokenを外部へ送る

対策:

- short TTL
- `connect-src 'self'`
- `img-src 'self' data: blob:`
- 外部navigationをnative WebViewで拒否
- tokenはCognito権限を持たずapp-scoped

### Data機能を許可していない作品がAPIを叩く

対策: current app grantをserverで毎回確認。

### 大量writeによるコスト増加

対策:

- hard quota
- request body limit
- API Gateway/Lambda throttle
- app/launch単位rate limitを後続で追加
- 教室ごとAWSなのでblast radiusと請求が教室環境内に閉じる

### 他の教室データへアクセス

前提として教室ごとAWS環境を分離する。中央ディレクトリを将来導入しても、ディレクトリには教室の実データやCognito credentialを保存しない。

## 19. 既存Phase 4との互換性

manifestがない作品:

```text
requested capabilities = none
```

として扱う。

そのため既存のPhase 4作品は:

- 同じZIP
- 同じ公開フロー
- 同じlaunch URL
- `connect-src 'none'`

のままで動く。

Data対応はopt-inで追加する。

## 20. 実装順序

### Phase 5A: capability control plane

まだDB保存は行わない。

- `minapp.json` parser / strict validation
- group runtime policy
- app requested capability
- review UIへの権限表示
- app runtime grant
- grant変更/revoke
- tests

ここまでで「誰に何を許したか」を安全に管理できる状態にする。

### Phase 5B: Data API

- runtime DynamoDB table
- same-origin runtime routes
- launch tokenからapp scope導出
- CRUD API
- SDK
- CSPをgrantに応じて切替
- quota counter
- tests

### Phase 5C: teacher data tools

- 作品データ件数/容量表示
- 作品データ全消去
- group単位Data OFF
- audit summary

### Phase 6以降

- allowlisted external API proxy
- AI gateway / budget limit
- file storage
- schema/index/query

## 21. MVPで意図的にやらないもの

- RDSへの直接接続
- DynamoDB credential配布
- Cognito tokenをWebViewへ渡す
- arbitrary outbound network
- arbitrary SQL
- arbitrary DynamoDB query
- cross-app shared database
- cross-school shared runtime table
- silent quota fallback
- 自動的なcapability grant

## 22. 受け入れ条件

Phase 5B完了時のE2E:

1. 教室環境でData capabilityを有効にする
2. 先生が対象groupのDataをONにする
3. 生徒が `minapp.json` で `messages` のlist/createを申請した作品をアップロード
4. 先生のレビュー画面に要求権限が表示される
5. 先生が権限を承認して公開
6. Android/iOSの共通みんアプから作品を起動
7. `minapp.collection("messages").add()` で保存できる
8. 再起動後もlistでデータが残る
9. 未許可collectionへのアクセスは403
10. update未許可時のupdateは403
11. group DataをOFFにすると既存launchからも即403
12. Basic作品は引き続き外部通信不可
13. 別app_idのruntime dataへアクセスできない
14. quota超過時に明示的エラーとなり、既存データを勝手に削除しない

## 23. 設計判断

Phase 5の重要な境界は次の一文です。

> 子どもの作品にDBを渡すのではなく、作品専用・短時間・最小権限のData APIを渡す。

これにより、初心者向けBasicの安全性を維持しながら、上級教室ではCRUD、HTTP、JSON、認証、権限、永続化まで段階的に学べるようにします。
