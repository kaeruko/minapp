# みんアプ MVP設計

## 1. 目的

AIやプログラミング学習で子どもが作った静的Webアプリを、Google Play Console・クレジットカード・クラウド契約なしで、学校や教室などの限定グループ内に配布できるようにする。

MVPの成功条件は「作品を作る」ではなく、**作った作品を先生の承認後に同じグループの人が実際に使える**ところまでを一続きにすること。

---

## 2. MVPのユーザー

### teacher

先生・教室運営者。

できること:

- グループ作成
- 生徒アカウント発行
- 初期パスワード再発行
- 生徒の所属解除
- 公開申請の確認
- 承認 / 却下
- 公開停止

### student

生徒。

できること:

- ID + パスワードでログイン
- ZIPアップロード
- 自分の作品一覧を見る
- 公開申請
- 承認済みアプリをAndroid版で使う

### operator

みんアプ運営者。

MVPでは一般画面を作り込まず、障害対応・不正コンテンツ停止などの最低限の運用権限だけ持つ。

---

## 3. 基本ユーザーフロー

```text
先生
  │
  ├─ グループ作成
  │
  ├─ 生徒アカウント発行
  │      ID: shiba-4821
  │      初期PW: ********
  │
  ▼
生徒
  │
  ├─ Webポータルへログイン
  ├─ app.zip をアップロード
  ├─ 公開申請
  │
  ▼
先生
  │
  ├─ プレビュー
  └─ 承認
         │
         ▼
   published
         │
         ▼
同じグループのAndroid版「みんアプ」
         │
         └─ アプリカードをタップして起動
```

---

## 4. 認証と所属

### 認証

MVPは **ID + パスワード**。

メールアドレスは必須にしない。

想定は Amazon Cognito User Pools を使い、先生がバックエンド経由で生徒を作成する方式。

- username: ランダム生成ID
- 初期パスワード: 一回限り
- 初回ログイン時に本人用パスワードへ変更
- パスワード忘れ: 先生が再発行
- 生徒本人によるメールリセットはMVPでは実装しない

### 所属

認証アカウントとグループ所属は分離する。

```text
User
  user_id
  auth_subject
  role

Group
  group_id
  name

Membership
  user_id
  group_id
  role
  status
```

クライアントが送ってきた `group_id` を信用しない。

すべてのグループ内APIで、サーバ側が `user_id -> Membership -> group_id` を確認する。

---

## 5. Webアプリの形式

MVPでは **静的Webアプリだけ**を受け付ける。

必須:

```text
app.zip
└─ index.html
```

許可候補:

- `.html`
- `.css`
- `.js`
- `.json`
- `.png`
- `.jpg` / `.jpeg`
- `.webp`
- `.svg`
- `.gif`
- `.woff2`

MVP初期値:

- ZIP最大: 10 MB
- 展開後最大: 30 MB
- 最大ファイル数: 300
- `index.html` 必須
- パストラバーサル禁止
- symlink禁止
- 許可拡張子以外は禁止

違反時は自動修正しない。アップロード全体を失敗にして、何が不正だったかを表示する。

---

## 6. 子どものWebアプリを信用しない

子どもに悪意がなくても、AIが危険なJavaScriptを生成する可能性を前提にする。

### 親アプリから絶対に渡さないもの

- CognitoのAccess Token / ID Token / Refresh Token
- APIキー
- ユーザー本名
- グループ内メンバー一覧
- Androidのファイルアクセス
- カメラ
- マイク
- GPS
- クリップボード連携
- JavaScript bridge

### WebView

MVPではJavaScriptはWebアプリ用途として許可するが、**ネイティブとのJavaScript bridgeは一切作らない**。

読み込めるのは、みんアプ管理下のHTTPSコンテンツだけ。

HTTP、file://、content://、任意の外部URLは読み込まない。

---

## 7. 外部通信を禁止する

MVPでは子どものWebアプリは外部APIへ通信できない。

配信時に強制するCSPのイメージ:

```text
default-src 'none';
script-src 'self' 'unsafe-inline';
style-src 'self' 'unsafe-inline';
img-src 'self' data: blob:;
font-src 'self' data:;
connect-src 'none';
media-src 'self' data: blob:;
frame-src 'none';
object-src 'none';
worker-src 'none';
form-action 'none';
base-uri 'none';
frame-ancestors 'none';
```

`unsafe-inline` はMVPでAI生成HTMLをそのまま動かしやすくするための妥協点。将来はアップロード時にHTMLを書き換えてnonce方式へ移行できる。

CSPだけを検査の代わりにはしない。明らかな外部URLや禁止要素はアップロード検査でも警告・拒否し、最終的な強制は配信ヘッダで行う。

---

## 8. 公開コンテンツへのアクセス制御

公開済みWebアプリも、URLを知っているだけでは閲覧できないようにする。

### 起動フロー

```text
Flutter
  │
  │ 1. GET /apps/{app_id}/launch
  │    Authorization: Bearer <token>
  ▼
API
  │
  │ 2. userがapp所属groupのmemberか確認
  │
  │ 3. 短時間だけ有効なlaunch情報を発行
  ▼
WebView
  │
  │ 4. CloudFront配下の対象app versionだけ閲覧
  ▼
静的コンテンツ
```

重要なのは、WebView側へAPI認証Tokenを渡さないこと。

コンテンツ配信用の認可情報は短寿命かつ対象アプリ/バージョンだけに限定する。

---

## 9. 公開ワークフロー

作品はアップロード直後に公開しない。

状態:

```text
draft
  ↓
submitted
  ├─→ rejected
  │      ↓
  │    draft
  │
  └─→ approved
         ↓
      published
         ↓
      unpublished
```

### versionを不変にする

一度承認されたファイルを上書きしない。

変更したい場合は新しいversionをアップロードし、もう一度承認する。

```text
App
  app_id
  owner_user_id
  group_id
  title

AppVersion
  version_id
  app_id
  status
  storage_prefix
  created_at
  reviewed_by
  reviewed_at
```

これにより「先生が確認した後に中身だけ差し替える」を防ぐ。

---

## 10. 画面

### Webポータル / 共通

- ログイン
- 初回パスワード変更
- ログアウト

### Webポータル / student

- 自分の作品一覧
- 新しい作品
- ZIP選択
- バリデーション結果
- プレビュー
- 公開申請
- 審査結果

### Webポータル / teacher

- グループ情報
- 生徒一覧
- 生徒追加
- パスワード再発行
- 所属解除
- 公開申請一覧
- プレビュー
- 承認
- 却下
- 公開停止

### Android / student + teacher

- ログイン
- 参加グループ
- 承認済みアプリ一覧
- アプリ詳細
- Webアプリ起動
- ログアウト

管理操作はMVPではPCのWebポータルを優先する。

---

## 11. API案

```text
GET    /me
GET    /groups
POST   /groups                         teacher
GET    /groups/{group_id}/members      teacher
POST   /groups/{group_id}/students     teacher
POST   /users/{user_id}/reset-password teacher
DELETE /groups/{group_id}/members/{user_id} teacher

GET    /apps
POST   /apps
POST   /apps/{app_id}/versions
POST   /app-versions/{version_id}/upload-url
POST   /app-versions/{version_id}/submit

GET    /reviews                        teacher
POST   /app-versions/{version_id}/approve teacher
POST   /app-versions/{version_id}/reject  teacher
POST   /app-versions/{version_id}/unpublish teacher

GET    /apps/{app_id}/launch
```

全APIは認証だけでなく、対象resourceへの権限を毎回サーバ側で確認する。

---

## 12. AWS構成案

```text
                  ┌─────────────────┐
Flutter Android ─▶│ API Gateway      │
Web Portal      ─▶│                 │
                  └────────┬────────┘
                           ▼
                       Lambda
                    ┌──────┼──────┐
                    ▼      ▼      ▼
                 Cognito DynamoDB S3(private)
                                  │
                                  │ validation/publish
                                  ▼
                              S3(published)
                                  │
                                  ▼
                              CloudFront
                                  │
                                  ▼
                               WebView
```

### Upload

ZIP本体はAPI Gateway経由で送らない。

1. APIが短時間有効なS3アップロードURLを発行
2. ブラウザからprivate upload bucketへ直接PUT
3. バックエンドがZIPを検査
4. 正常なら展開済みファイルをstagingへ保存
5. teacher承認後にimmutableなpublished versionとして公開

---

## 13. セキュリティ上のMVP必須項目

- deny by default
- APIリクエストごとに認可
- IDOR対策
- 生徒のメール/電話/本名を必須にしない
- ログへパスワード・Tokenを書かない
- HTTPSのみ
- WebViewへのJavaScript bridge禁止
- WebViewへ認証Tokenを渡さない
- 外部ネットワーク通信禁止
- ZIP Slip対策
- ZIP bomb対策
- symlink禁止
- MIME / 拡張子allowlist
- private S3 bucket
- published versionはimmutable
- teacher承認前には他ユーザーへ表示しない
- teacherは自分のgroupだけ操作可能
- rate limit / login試行制限
- 操作監査ログ

---

## 14. MVPで保存する情報

可能な限り少なくする。

### User

- internal user id
- login id
- role
- account status
- created_at

### Group

- group id
- display name
- created_by

### Membership

- user id
- group id
- role
- status

### App

- app id
- group id
- owner user id
- title
- description

### AppVersion

- version id
- app id
- status
- storage location
- created_at
- reviewed_at
- reviewed_by

本名、住所、生年月日、学校名、学年などはMVPの機能に不要なので保存しない。

---

## 15. MVPでやらないこと

スコープを広げない。

- iOS
- 公開ストア
- 検索エンジン向け一般公開
- SNS共有
- コメント
- チャット
- いいね
- ランキング
- 課金
- 広告
- 任意外部API
- Firebase等への子アプリからの直接接続
- 子アプリ専用DB
- WebSocket
- Service Worker
- PWAインストール
- カメラ
- GPS
- マイク
- ファイルシステム
- ネイティブbridge
- AIによるアプリ自動生成

---

## 16. 実装順

### Phase 0: skeleton

- Flutter Androidプロジェクト
- Webポータル
- backend
- IaC
- dev環境

### Phase 1: identity / group

- Cognito
- ID + passwordログイン
- teacher / student
- group
- membership
- teacherによる生徒作成

### Phase 2: upload / review

- app作成
- ZIP upload
- ZIP validation
- preview
- submit
- approve / reject
- immutable version

### Phase 3: Android viewer

- app一覧
- launch API
- WebView
- HTTPS限定
- bridgeなし
- 外部navigation拒否
- CSP

### Phase 4: hardening

- rate limit
- audit log
- permission tests
- malicious ZIP tests
- malicious HTML/JS tests
- group越境テスト
- release build

---

## 17. MVP完成条件

次を自動テストまたは手動受入テストで確認できたらMVP完成。

1. teacherが生徒IDを発行できる
2. 生徒がメールアドレスなしでログインできる
3. 生徒が静的WebアプリZIPをアップロードできる
4. 不正ZIPは理由を表示して拒否される
5. 未承認アプリは他の生徒に見えない
6. teacherが承認すると同じgroupのアプリ一覧に出る
7. 別groupのユーザーからは一覧・launch・直接URLのすべてでアクセスできない
8. Webアプリから親アプリのTokenを取得できない
9. Webアプリから外部HTTP/HTTPS通信できない
10. Webアプリからカメラ・GPS・マイク・ファイルへアクセスできない
11. 承認済みversionの中身を後から差し替えられない
12. teacherが別groupの生徒・作品を操作できない

---

## 18. 最初のデモシナリオ

最初は「時間割アプリ」だけで一連の流れを通す。

```text
student A
  ↓
timetable.zip をupload
  ↓
teacherがpreview
  ↓
approve
  ↓
student BがAndroid版みんアプを開く
  ↓
「時間割」カードが表示
  ↓
タップ
  ↓
WebViewで時間割アプリが動く
```

この一本道が安全に通ってから、文化祭マップ・クイズ・図鑑などへ広げる。
