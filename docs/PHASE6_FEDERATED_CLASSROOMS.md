# Phase 6 design: one store app / independent classroom AWS

Phase 6は、App Store / Google Playでは「みんアプ」を1本だけ配布しながら、契約する教室・学校・塾ごとの実データ環境を別AWSアカウントへ完全分離するための設計です。

この文書では、中央の「教室ディレクトリ」、教室コード/QR、Flutterアプリの接続先切替、教室AWSの識別、導入支援、障害時の動作までを定義します。

Phase 6は設計段階です。既存Phase 4の単一AWS接続やPhase 5のruntime capability設計を壊さず、後方互換を維持して段階的に実装します。

## 1. 用語

### tenant

AWSアカウント分離の単位です。原則として1契約先/1教室拠点/1学校組織を1 tenant とします。

既存の `group` はtenant内部のクラス・講座・学年などに使います。

例:

```text
〇〇プログラミング教室 AWS account = tenant A
  ├─ group: 土曜午前クラス
  ├─ group: 土曜午後クラス
  └─ group: 中学生上級クラス
```

「groupごとにAWSアカウントを作る」ことは必須ではありません。データ管理責任や請求主体を分けたい境界をtenantにします。

### directory

みんアプ運営側が管理する小さな中央サービスです。

directoryが持つのは「この教室はこのtenant APIへ接続する」というrouting metadataだけです。生徒の作品、パスワード、Cognito token、runtime dataは保存しません。

## 2. 全体構成

```text
                 App Store / Google Play
                        │
                   「みんアプ」1本
                        │
              教室コード入力 / QR読取
                        │
                        ▼
             ┌──────────────────┐
             │ MinApp Directory │  運営AWS
             │ routing only     │
             └────────┬─────────┘
                      │
       code -> tenant descriptor
                      │
       ┌──────────────┼──────────────┐
       ▼              ▼              ▼
 教室A AWS account  教室B AWS account  学校C AWS account
       │              │              │
   Cognito A       Cognito B       Cognito C
   Lambda A        Lambda B        Lambda C
   DynamoDB A      DynamoDB B      DynamoDB C
   S3 A            S3 B            S3 C
```

ネイティブアプリは同じバイナリを使います。

教室コードから解決した `api_base_url` だけを切り替え、その後のlogin/catalog/launch/Data APIはすべてtenant AWSへ直接接続します。

## 3. 重要な設計判断

### 3.1 Cognito設定をdirectoryから返さない

現在のFlutterアプリはCognitoへ直接ログインせず、tenant APIの `/auth/login` を呼びます。Cognito User Pool ID / App Client IDはLambda側の環境変数です。

したがってmobile clientへ必要なのは基本的に `api_base_url` だけです。

directory responseへCognito情報を増やしません。

これにより:

- mobile clientのtenant設定を小さくできる
- Cognito構成変更をclientへ露出しない
- auth実装をtenant API内に閉じ込める
- iOS/Androidで同じdiscovery flowを使える

### 3.2 教室コードは認証情報ではない

教室コードを知っているだけではログインできません。

認証はこれまで通りtenant側のID/パスワードです。

教室コードの役割は:

```text
教室コード
  ↓
どのAWSへ接続するかを決める
```

だけです。

そのためコードは配布プリントやQRへ載せられます。

### 3.3 任意URLを入力させない

mobile appに「API URLを入力」という機能は作りません。

ユーザー入力やQRから得たURLへ直接接続すると、偽のlogin APIへ誘導してパスワードを盗む構成になり得ます。

採用:

```text
教室コード / 公式join link
      ↓
固定されたMinApp Directory
      ↓
Directoryが返したHTTPS tenant API
```

QRもURLそのものではなく、directoryへ渡すjoin codeだけを含めます。

## 4. tenant identity

各tenantへimmutableな `tenant_id` を1つ発行します。

例:

```text
tenant_id = 2d8860f2b45b4eaa9b8f97b935f55f50
```

要件:

- 32 hexまたはUUID形式の高entropy ID
- 作成後は変更しない
- AWS account IDをtenant IDとして使わない
- display nameをidentityとして使わない
- 全tenant Terraform resourceへ `TenantId` tagを付ける

AWS accountを作り直す場合でも、移行として扱うならtenant_idを維持できます。

## 5. tenant API identity endpoint

各tenant APIへpublic read-only endpointを追加します。

```text
GET /tenant-info
```

response例:

```json
{
  "service": "minapp-tenant-api",
  "tenant_id": "2d8860f2b45b4eaa9b8f97b935f55f50",
  "api_protocol_version": 1,
  "environment": "prod"
}
```

このendpointは:

- login不要
- 生徒/先生情報を返さない
- Cognito IDを返さない
- AWS account IDを返さない
- secretを返さない

mobile appはdirectoryからdescriptorを受け取った後、必ず `/tenant-info` を取得し、`tenant_id` が一致することを確認してからlogin画面を表示します。

これにより運用時に「教室Aのdirectory recordへ誤って教室BのAPI URLを登録した」という事故をfail fastできます。

## 6. Directory descriptor

Directoryの公開APIが返す最小descriptor:

```json
{
  "schema_version": 1,
  "tenant_id": "2d8860f2b45b4eaa9b8f97b935f55f50",
  "display_name": "〇〇プログラミング教室",
  "api_base_url": "https://example.execute-api.ap-northeast-1.amazonaws.com",
  "api_protocol_version": 1,
  "config_revision": 3,
  "valid_for_seconds": 86400
}
```

Directoryには以下を置きません:

- student ID
- teacher ID
- password
- Cognito token
- Cognito App Client secret
- AWS access key
- child app data
- ZIP
- Data API contents

`api_base_url` はsecretではありません。

## 7. URL validation

mobile appはdirectory responseをそのまま信用して文字列連結しません。

V1では `api_base_url` に次を要求します。

- schemeは `https`
- host必須
- userinfo禁止
- query禁止
- fragment禁止
- IP literal禁止
- localhost / `.local`禁止
- pathは空または `/`
- default HTTPS portを使用

将来custom domainを使う場合もこの形式を維持します。

Directory側でも同じvalidationを行い、二重に防御します。

## 8. classroom code

### 8.1 format

人間が手入力できるよう、紛らわしい文字を除いたBase32系alphabetを使います。

例:

```text
7K2M-4Q9P-W6TX
```

- 大文字/小文字を区別しない
- `-` は入力時に省略可
- normalization後12文字程度
- server側生成のみ
- user指定不可

コードはrouting用でありsecretではありませんが、十分なentropyを持たせて無差別enumerationを避けます。

### 8.2 server storage

Directory DBにはraw codeを恒久保存せず、normalized codeのSHA-256をindex keyとして保持します。

```text
PK = CODE#{sha256(normalized_code)}
SK = META
  tenant_id
  status
  created_at
```

新規発行時のraw codeは導入担当者へ表示します。

紛失時は再表示ではなくrotateできます。

### 8.3 rotation

コードをrotateしても既に設定済みの端末は壊しません。

設定済み端末は `tenant_id` を保存しているため、次回refreshはtenant_idで行います。

古いコードは新規登録だけ拒否します。

## 9. Directory public API

### 9.1 初回resolve

```text
POST /v1/classrooms/resolve
Content-Type: application/json
```

request:

```json
{
  "code": "7K2M-4Q9P-W6TX"
}
```

POSTにする理由は、手入力コードを通常のURL access logへ残しにくくするためです。

responseはtenant descriptorです。

### 9.2 configured tenant refresh

```text
GET /v1/tenants/{tenant_id}
```

既に設定済みの端末がendpoint変更やconfig revisionを取得するために使います。

`tenant_id` は認証credentialではありません。

### 9.3 error

曖昧なfallbackはしません。

例:

```text
400 invalid_classroom_code
404 classroom_not_found
410 classroom_inactive
409 incompatible_tenant_config
429 rate_limited
503 directory_unavailable
```

未知のschema field/versionはclient側でrejectします。

## 10. Directory data model

中央DynamoDB例:

### tenant record

```text
PK = TENANT#{tenant_id}
SK = META

entity = tenant
display_name
status = pending | active | inactive
api_base_url
api_protocol_version
config_revision
created_at
updated_at
```

### classroom code mapping

```text
PK = CODE#{sha256(code)}
SK = META

tenant_id
status = active | rotated
created_at
rotated_at?
```

Directory tableへtenant AWS credentialは保存しません。

## 11. Directory admin plane

MVPではpublicな管理mutation APIを作りません。

導入担当者用CLIを運営AWS credentialsで実行します。

概念:

```text
minapp tenant create
minapp tenant activate
minapp tenant rotate-code
minapp tenant update-endpoint
minapp tenant deactivate
```

Directoryの公開Lambdaはresolve/readだけにします。

これにより「インターネット公開されたadmin endpoint」のattack surfaceを最初から増やしません。

## 12. tenant onboarding flow

導入支援では次の順序を標準にします。

```text
1. 顧客がAWS accountを用意
2. Directory側でtenant_idとclassroom codeを生成
3. tenant recordをpendingで作成
4. 顧客AWSへtenant_idを指定してTerraform apply
5. Terraform outputからapi_base_urlを取得
6. 導入CLIが /tenant-info を検証
7. tenant_id一致を確認
8. Directoryへapi_base_urlを登録
9. tenantをactiveへ変更
10. classroom code / QRを教室へ納品
11. teacher accountをbootstrap
12. 実機でlogin -> catalog -> launchをE2E確認
```

Directoryはtenant API確認に失敗した状態ではactiveにできません。

## 13. tenant Terraform

教室AWSのTerraformへrequired variableを追加します。

概念:

```hcl
variable "tenant_id" {
  type = string
}
```

各Lambdaへ:

```text
TENANT_ID
API_PROTOCOL_VERSION
```

を環境変数として渡します。

outputs:

```text
tenant_id
api_base_url
api_protocol_version
```

を明示します。

同じrepository / Terraform moduleを全tenantへ使い、値だけを変えます。教室ごとにコードforkしません。

## 14. Terraform state

各tenantのTerraform stateも原則として顧客側AWSへ置きます。

理由:

- resource ownershipとstate ownershipを一致させる
- 一顧客のstate事故が他tenantへ波及しない
- 解約時に顧客へ環境を引き渡しやすい

導入時にtenant用remote state backendをbootstrapし、`terraform init -backend-config=...` で明示的に接続します。

MVPでも「全教室を1つのlocal tfstateで管理」は禁止します。

## 15. AWS credential運用

導入支援で顧客AWSへ長期access keyを発行してもらう運用は採用しません。

MVP:

- 顧客側の一時的なAWS CLI/SSO sessionで導入
- apply終了後にsessionを破棄
- root credentialを受け取らない

将来、継続保守が必要な契約では専用cross-account support roleを別途設計します。

support roleを作る場合もtenant runtime/application roleとは分離します。

## 16. Flutter state machine

現在:

```text
起動
 -> Login
 -> Catalog
```

Phase 6:

```text
起動
  │
  ├─ verified tenantなし
  │      ↓
  │   教室設定
  │      ↓
  │   code resolve
  │      ↓
  │   /tenant-info verify
  │      ↓
  │   tenant descriptor保存
  │
  └─ verified tenantあり
         ↓
       Login
         ↓
       Catalog
```

### persisted data

端末へ保存してよいもの:

```text
tenant_id
display_name
api_base_url
api_protocol_version
config_revision
verified_at
expires_at
```

保存しないもの:

```text
password
Cognito access token
launch token
```

現在の「access tokenはmemory only」を維持します。

## 17. Login

Directory resolve後は既存API clientのbase URIをtenant `api_base_url` へ設定します。

```text
POST {tenant-api}/auth/login
GET  {tenant-api}/mobile/apps
POST {tenant-api}/mobile/apps/.../launch
```

Cognito tokenはtenant間で共有しません。

同じ `student-xxxx` というIDが別tenantに存在しても別identityです。

## 18. logout / classroom switch

### logout

通常のlogoutは選択中tenantを維持し、同じ教室のloginへ戻ります。

### 教室を変更

明示的な「教室を変更」操作では必ず:

```text
1. access token破棄
2. pending auth challenge破棄
3. WebView cookie削除
4. localStorage削除
5. WebView cache削除
6. selected tenant descriptor削除
7. 教室コード入力へ戻る
```

を行います。

tenant Aのtoken/stateをtenant Bへ持ち越しません。

## 19. QR / join link

手入力に加え、将来次のverified linkを使います。

```text
https://<official-join-domain>/c/7K2M-4Q9P-W6TX
```

Android App Links / iOS Universal Linksで「みんアプ」を開きます。

重要:

- QRのhostをtenant APIにしない
- QRから任意api_base_urlを受け取らない
- linkから取得するのはclassroom codeだけ
- 最終endpointは必ずDirectoryでresolveする

アプリ未インストール時はjoin pageから各storeへ案内できます。

## 20. cached descriptor policy

Directory障害が毎回の授業を止めないよう、verified descriptorを期限付きでcacheします。

V1 default:

```text
valid_for_seconds = 86400  # 24h
```

動作:

- cacheが有効期限内: 通常利用可能
- backgroundでDirectory refreshしてよい
- cache期限切れ: Directory refresh必須
- 期限切れ + Directory unreachable: loginを開始せず明示エラー
- expired cacheへsilent fallbackしない

初回登録/教室変更では必ずDirectoryが必要です。

`valid_for_seconds` のclient許容上限も設け、Directoryが誤って極端に長いTTLを返してもreject/clampではなくconfiguration errorとして扱います。

## 21. inactive / suspension semantics

Directoryの `inactive` は「新規resolve / endpoint refreshを止めるrouting state」です。

これはtenant認証のsecurity boundaryではありません。

理由:

- 有効期限内cacheを持つ端末はtenant endpointを知っている
- API URL自体はsecretではない

本当にtenant利用を止める必要がある場合はtenant AWS側でもdisableします。

Directoryだけを止めて「データアクセスが完全に止まった」と扱わないことをrunbookへ明記します。

## 22. protocol compatibility

Directory schemaとtenant API protocolを別versionとして管理します。

```text
directory schema_version = 1
api_protocol_version     = 1
```

mobile appが対応していない `api_protocol_version` のtenantへは接続しません。

エラー例:

```text
この教室の環境には新しいみんアプが必要です。アプリを更新してください。
```

Directory recordと `/tenant-info` のprotocol versionが一致しない場合もfail fastします。

## 23. config revision

endpoint変更などdirectory record更新のたびに `config_revision` を単調増加させます。

client cacheより新しいrevisionを取得したらdescriptorをatomicに置き換えます。

partial updateはしません。

## 24. security boundaries

### central Directoryが侵害された場合

最大の危険は偽tenant login endpointへのroutingです。

そのため:

- production appのDirectory base URLは固定
- HTTPS必須
- arbitrary endpoint入力なし
- Directory mutationはpublicにしない
- directory AWS IAMをtenant AWS IAMから分離
- endpoint変更をaudit logへ残す
- `/tenant-info` mismatchをreject

将来さらに必要ならdescriptor署名を追加できますが、V1はOS TLS trust + fixed Directory originを主境界とします。

### tenant Aが侵害された場合

tenant AのIAM/resourceだけに閉じます。

tenant A Lambdaからtenant B resourceへアクセスできるcross-account permissionを標準構成では作りません。

Directoryにもtenant AWS credentialを置かないため、tenant AからDirectory経由でBへ横移動するcredential pathを作りません。

### classroom code漏えい

routing情報が分かるだけです。

ID/password認証は別途必要です。

## 25. data isolation

production要件:

- tenantごとにAWS account分離
- tenantごとにCognito User Pool
- tenantごとにDynamoDB
- tenantごとにS3
- tenantごとにLambda / API Gateway
- tenant間IAM trustなし（support roleを除く）
- directoryにchild dataなし

Phase 5 runtime dataを導入した場合もruntime tableは各tenant AWS account内です。

## 26. billing / ownership

原則:

```text
教室AのAWS利用料 -> 教室A AWS account
教室BのAWS利用料 -> 教室B AWS account
```

導入支援パッケージでは、みんアプ運営がTerraform構築を支援してもAWS resourceのownerは顧客accountです。

Directory運営費だけはみんアプ運営側です。

## 27. observability

### Directory log

記録してよい:

- request ID
- tenant_id
- operation (`resolve`, `refresh`)
- result status
- config revision
- latency

記録しない:

- raw classroom code
- password
- token

resolve時はcode hashの短いfingerprintが必要なら利用できますが、raw codeをapplication logへ出しません。

### tenant log

既存のtenant Lambda logはtenant account内に残します。

中央へchild app request bodyを集約しません。

## 28. failure modes

### Directory unreachable / first setup

fail closed。教室設定できません。

### Directory unreachable / valid cacheあり

cache期限内は既定動作として利用できます。これはfallbackではなく仕様化したcacheです。

### Directory unreachable / cache expired

明示的に停止。expired endpointをsilent利用しません。

### tenant API unreachable

「教室サーバーへ接続できません」を表示し、別tenantへ自動切替しません。

### tenant-info mismatch

重大な設定不整合としてlogin画面へ進みません。

### unknown protocol

アプリ更新を要求し、古いprotocolへfallbackしません。

### classroom code unknown

404相当。似た教室を候補表示しません。

## 29. migration from current single-tenant app

Phase 6移行時、既存dev環境を最初のtenantとしてdirectoryへ登録します。

mobile appは最初のPhase 6 buildでtenant未設定になります。

開発中は `MINAPP_DIRECTORY_BASE_URL` を明示指定できますが、production store buildは公式Directory originへ固定します。

既存の `MINAPP_API_BASE_URL` direct modeは開発/E2E用途として残してもよいですが、production buildでは無効化し、両方が指定された場合はfail fastします。

## 30. Store appとの関係

ストア上のbundle/packageは1つだけです。

```text
Android: jp.cloxs.min
Apple:   1つのBundle ID
```

教室追加で新しいnative appを作りません。

tenant追加はDirectory record + tenant AWS deploymentだけで完結します。

これによりnative release cadenceと教室導入 cadenceを分離できます。

## 31. implementation split

### Phase 6A: Directory service

- central Directory Terraform
- tenant/code DynamoDB model
- resolve / refresh read API
- strict schema/url validation
- throttling
- operator CLI
- code create/rotate
- audit

### Phase 6B: tenant identity / deploy

- required `tenant_id` Terraform variable
- TenantId resource tags
- `/tenant-info`
- protocol version
- outputs
- customer-owned remote Terraform state bootstrap/runbook
- onboarding verification command

### Phase 6C: mobile enrollment

- tenant selection screen
- Directory client
- strict descriptor parser
- `/tenant-info` verification
- cached descriptor TTL
- selected tenant persistence
- logout vs classroom switch
- WebView/session wipe on switch
- official join link parser
- Android/iOS common abstraction

### Phase 6D: onboarding and multi-tenant E2E

- two isolated test tenants
- code/QR provisioning
- tenant A/B login isolation tests
- endpoint rotation test
- classroom code rotation test
- Directory outage/cache-expiry tests
- handover checklist

## 32. required security tests

1. QRに任意HTTPS URLを入れてもtenant endpointとして採用されない。
2. DirectoryがHTTP URLを返したらrejectする。
3. Directory tenant_idと `/tenant-info` tenant_id不一致でloginへ進まない。
4. tenant Aのaccess tokenをtenant B APIへ送らない。
5. classroom switchでtoken/WebView storageが消える。
6. tenant A accountにtenant B resourceへのIAM permissionがない。
7. Directory DBにpassword/token/ZIPが存在しない。
8. rotated classroom codeで新規enrollmentできない。
9. rotated後も既に設定済み端末はtenant_id refreshで継続できる。
10. expired descriptor + Directory failureでsilent fallbackしない。
11. unsupported api protocolへfallbackしない。
12. Directory admin mutationがpublic routeに存在しない。

## 33. E2E acceptance scenario

```text
Directory
  TENANT A -> API A
  TENANT B -> API B

Device 1
  code A
  -> Aをresolve
  -> tenant-info A一致
  -> student-a login
  -> Aのcatalogだけ表示

「教室を変更」
  -> token/storage wipe
  -> code B
  -> Bをresolve
  -> tenant-info B一致
  -> student-b login
  -> Bのcatalogだけ表示
```

同名のlogin IDや同名の作品がA/Bにあっても混ざらないことを確認します。

## 34. non-goals

Phase 6では以下をしません。

- tenant間SSO
- central user database
- central child analytics
- central app ZIP storage
- AWS Organizationsによる顧客account強制管理
- tenant間データ検索
- tenant間作品共有
- arbitrary API URL入力
- classroom codeだけでの認証

## 35. 結論

Phase 6の境界は次です。

```text
みんアプ運営AWS
  -> 教室の所在だけ知る

教室AWS
  -> その教室のidentity / apps / dataを持つ

Store app
  -> Directoryで接続先を選び、そのtenantへ直接接続する
```

この構成により「native appは1本」「教室データはAWS accountごとに独立」「教室追加のたびにstore審査をしない」を同時に成立させます。
