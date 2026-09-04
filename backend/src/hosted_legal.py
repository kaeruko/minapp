from __future__ import annotations

from typing import Any

from errors import ApiProblem

TERMS_VERSION = "hosted-terms-2026-08-28"
PRIVACY_VERSION = "hosted-privacy-2026-09-04"
TERMS_EFFECTIVE_DATE = "2026-08-28"
PRIVACY_EFFECTIVE_DATE = "2026-09-04"
LEGAL_EFFECTIVE_DATE = PRIVACY_EFFECTIVE_DATE
SUPPORT_EMAIL = "mail@cloxs.jp"

TERMS_TITLE = "みんアプ Hosted 利用規約 / Terms of Use"
TERMS_BODY = f"""{TERMS_TITLE}

発効日: {TERMS_EFFECTIVE_DATE}

1. サービスについて
みんアプ Hosted は、招待された利用者どうしが非公開グループ内で小さなWebアプリや創作物を共有するためのサービスです。グループや招待コードは、意図した相手だけに共有してください。

2. 不適切なコンテンツ・迷惑行為の禁止
みんアプでは、わいせつ、暴力、差別、脅迫、いじめ、嫌がらせ、個人情報の侵害、違法行為を助長する内容、その他他者に危害を与えるコンテンツや abusive behavior を一切許容しません（zero tolerance）。

3. ユーザーコンテンツ
利用者は、自分が作成・保存・共有する文章、画像、アプリ、設定データその他のコンテンツについて必要な権利を有し、第三者の権利を侵害しないことを確認してください。

4. 安全上の報告と運営対応
安全上の問題や規約違反は {SUPPORT_EMAIL} へ連絡できます。運営は報告された内容を確認し、必要に応じてコンテンツの削除・公開停止、グループからの除外、アカウントの利用停止その他の措置を行います。

5. アカウントとグループ管理
アカウントの認証情報、リカバリーコード、招待コードを第三者へ不用意に開示しないでください。グループのオーナーはメンバー管理と共有範囲について責任を持ちます。

6. サービスの変更・停止
安全性、法令対応、保守その他必要な理由により、機能の変更、制限または停止を行うことがあります。

7. 未成年の利用
適用される法令や家庭・学校のルールにより保護者等の同意が必要な場合は、必要な同意を得たうえで利用してください。

8. 規約の変更
本規約を変更する場合は新しいversionを公開します。新しいversionへの同意が必要な場合は、サービス上で改めて同意を求めます。

9. 連絡先
規約・安全上のお問い合わせ: {SUPPORT_EMAIL}
"""

PRIVACY_TITLE = "みんアプ Hosted プライバシーポリシー / Privacy Policy"
PRIVACY_BODY = f"""{PRIVACY_TITLE}

発効日: {PRIVACY_EFFECTIVE_DATE}

1. 取得・処理する情報
みんアプ Hosted では、サービス提供に必要な範囲で、ログインID、内部ユーザーID、認証システム上の識別子、リカバリーコードのハッシュ、利用者が任意で紐づけたメールアドレスと確認状態、グループ所属情報、アプリのメタデータ、Runtime state、利用者がアップロード・公開したコンテンツ、規約同意versionと同意時刻を処理します。

不正利用対策では、IPアドレス等のネットワーク情報とログインIDをレート制限判定に使用します。レート制限用DynamoDBキーにはIPアドレスやログインIDの平文を保存せず、テナント固有の名前空間を含めてSHA-256でハッシュ化した値を保存します。

2. Hosted登録で必須としない情報
現在のHosted登録では、メールアドレス、電話番号、実名、生年月日を必須情報として要求しません。メールアドレスは利用者が設定から任意で紐づけた場合に限り、確認コードによる本人確認を行って保存します。現在の実装ではメールアドレスをログインIDとして使用しません。

3. 利用目的
取得・処理した情報は、本人認証、アカウント復旧、利用者が指定したメールアドレスの確認とアカウントへの紐づけ、グループ共有、アプリ実行と状態保存、コンテンツ提供、不正利用・迷惑行為の防止、セキュリティ対応、障害調査、サービス運用のために利用します。

4. 外部サービス・クラウド基盤
サービス基盤としてAmazon Web Services (AWS) の認証、データベース、ストレージ、API、ログ等のサービスを利用します。これらの事業者はサービス提供に必要な範囲でデータを処理する場合があります。

5. 保存期間と削除
アカウント情報はサービス利用中に保存し、アカウント削除処理ではCognitoアカウントおよびHostedユーザープロファイル等を削除します。グループやアプリに属するデータは、所有関係や削除操作に応じて削除されます。レート制限カウンターはTTLによる自動削除対象です。運用ログやバックアップ等は、セキュリティ・障害対応に必要な限定期間、基盤の設定に従って残る場合があります。

6. 安全管理
認証情報やAWS credentialsを子アプリのJavaScriptへ直接渡さず、短命でスコープされたRuntime tokenを使用します。また、保存データの暗号化、アクセス制御、レート制限等を用いて不正アクセスのリスク低減に努めます。

7. 未成年の利用
適用される法令により保護者等の同意が必要な利用者は、必要な同意を得たうえで利用してください。現在のHosted登録では年齢や生年月日そのものを収集しません。

8. ポリシーの変更
本ポリシーを変更する場合は新しいversionを公開します。重要な変更で再同意が必要な場合は、サービス上で改めて同意を求めます。

9. お問い合わせ
プライバシーに関するお問い合わせ: {SUPPORT_EMAIL}
"""


def legal_payload() -> dict[str, Any]:
    return {
        "effective_date": LEGAL_EFFECTIVE_DATE,
        "support_email": SUPPORT_EMAIL,
        "terms": {
            "version": TERMS_VERSION,
            "title": TERMS_TITLE,
            "body": TERMS_BODY,
        },
        "privacy": {
            "version": PRIVACY_VERSION,
            "title": PRIVACY_TITLE,
            "body": PRIVACY_BODY,
        },
    }


def validate_legal_versions(terms_version: str, privacy_version: str) -> None:
    if terms_version != TERMS_VERSION:
        raise ApiProblem(
            409,
            "terms_version_outdated",
            "利用規約が更新されています。最新の利用規約を確認してもう一度同意してください。",
        )
    if privacy_version != PRIVACY_VERSION:
        raise ApiProblem(
            409,
            "privacy_version_outdated",
            "プライバシーポリシーが更新されています。最新の内容を確認してもう一度同意してください。",
        )
