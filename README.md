# みんアプ

学校・教室で作ったWebアプリを、安全にみんなで共有するためのプラットフォーム。

子どもごとにGoogle Play Consoleやクラウドの契約を持たなくても、HTML/CSS/JavaScriptで作った作品を先生の承認後にグループ内で使えるようにする。

## MVP

MVPでは次の体験だけを完成させる。

1. 先生がグループを作る
2. 先生が生徒IDと初期パスワードを発行する
3. 生徒がPCのWebポータルから静的WebアプリのZIPをアップロードする
4. 生徒が公開申請する
5. 先生が内容を確認して承認する
6. 同じグループの生徒がAndroid版「みんアプ」で承認済みアプリを開く

詳細は [docs/MVP.md](docs/MVP.md) を参照。

## 実装状況

### Phase 0: skeleton

完了。

```text
apps/mobile/       Flutter Android
apps/web/          Webポータル
backend/           Python Lambda API
infra/terraform/   AWS IaC
tools/             ローカル開発ツール
scripts/           開発スクリプト
```

### Phase 1: identity / group

完了。

- Cognito ID + パスワード認証
- 初回仮パスワード変更
- API Gateway JWT authorizer
- `teacher` / `student`
- グループ作成
- Membership
- 先生による生徒ID・仮パスワード発行
- 生徒の仮パスワード再発行
- 生徒の所属解除
- Cognito subjectとアプリ内user idの分離
- teacher権限とgroup所属のサーバ側再確認

### Phase 2: upload / review

完了。

- 生徒による静的WebアプリZIPアップロード
- ZIP安全検査と `index.html` 必須チェック
- 自分の作品一覧
- 公開申請
- 先生のグループ別レビューキュー
- 15分の短寿命プレビューURL
- CSP + sandbox iframeによる作品確認
- 先生による承認
- private published S3へのimmutable publish

### Phase 3: Android catalog / launch

実装済み。

- AndroidからID + パスワードでログイン
- 初回仮パスワード変更
- activeな所属グループの承認済み作品だけを一覧表示
- 作品起動時に10分の短寿命launch URLを発行
- Cognito access tokenを作品WebViewへ渡さない
- published S3 bucketはprivateのまま
- WebViewにnative JavaScript bridgeを作らない
- 同一launch token配下以外へのWebView navigationを拒否
- 外部通信・フォーム送信・カメラ・マイク・位置情報を作品へ公開しない

Phase 2の詳細は [docs/PHASE2.md](docs/PHASE2.md)、Phase 3のAWS反映・Android実行手順は [docs/PHASE3.md](docs/PHASE3.md) を参照。
Hosted BtoCのfork source / edit / immutable publishは [docs/HOSTED_SOURCE_PUBLISH.md](docs/HOSTED_SOURCE_PUBLISH.md) を参照。
開発・認証・最初の先生アカウント作成手順は [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) を参照。

## MVPの大原則

- メールアドレス・電話番号・本名は必須にしない
- 認可は必ずサーバ側で確認する
- 子どもが作ったHTML/JavaScriptを信用しない
- 子どものWebアプリへ親アプリの認証情報やネイティブ機能を渡さない
- 子どものWebアプリから外部ネットワークへ通信させない
- 先生や生徒にクラウドやセキュリティ設定をさせない
- 許可されていない入力・機能は暗黙に補正せず、明示的に拒否する

## 想定構成

- Android: Flutter
- 管理・アップロード画面: Web
- 認証: Amazon Cognito User Pools
- API: API Gateway + Lambda
- DB: DynamoDB
- ファイル: private S3
- IaC: Terraform

MVPのAndroid配信は、API Gateway + 専用Lambdaがprivate published S3の検証済みZIPから必要なファイルだけを短寿命launch URL経由で返す。CloudFrontは必須構成にせず、配信量や性能要件が出た段階の最適化候補とする。

## MVPではやらないこと

- iOS版
- 一般公開・SNS共有
- コメント・チャット・評価
- 子どものアプリから任意の外部APIを呼ぶ機能
- 子どものアプリ用バックエンド
- カメラ・位置情報・マイク等のネイティブ連携
- アプリ内AI生成機能
- 課金
