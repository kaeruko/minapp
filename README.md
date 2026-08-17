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

## Phase 0

実装の土台を次の構成で置いている。

```text
apps/mobile/       Flutter Android
apps/web/          Webポータル
backend/           Python Lambda API
infra/terraform/   AWS IaC
tools/             ローカル開発ツール
scripts/           開発スクリプト
```

開発手順は [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) を参照。

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
- ファイル: S3
- 配信: CloudFront（起動認可を実装するPhaseで追加）
- IaC: Terraform

Phase 0ではCloudFrontを作らない。公開コンテンツへの短寿命認可を実装する前に、配信用URLを外部公開しないため。

## MVPではやらないこと

- iOS版
- 一般公開・SNS共有
- コメント・チャット・評価
- 子どものアプリから任意の外部APIを呼ぶ機能
- 子どものアプリ用バックエンド
- カメラ・位置情報・マイク等のネイティブ連携
- アプリ内AI生成機能
- 課金
