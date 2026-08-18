from __future__ import annotations

import argparse
import json
import re
import secrets
import string
import uuid
from typing import Any

_LOGIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,31}$")


def _new_temporary_password() -> str:
    alphabet = string.ascii_letters + string.digits
    random_tail = "".join(secrets.choice(alphabet) for _ in range(13))
    return f"Ma1{random_tail}"


def _s(value: str) -> dict[str, str]:
    if not value:
        raise ValueError("DynamoDB strings must not be empty")
    return {"S": value}


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Create the first MinApp teacher in Cognito and DynamoDB."
    )
    parser.add_argument("--user-pool-id", required=True)
    parser.add_argument("--table-name", required=True)
    parser.add_argument("--login-id", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--region", required=True)
    args = parser.parse_args()

    if _LOGIN_ID_RE.fullmatch(args.login_id) is None:
        parser.error(
            "--login-id must be 3-32 lowercase ASCII letters, digits, or hyphens, "
            "and must start with a letter or digit"
        )
    return args


def _subject_from_admin_get_user(response: dict[str, Any]) -> str:
    attributes = response.get("UserAttributes")
    if not isinstance(attributes, list):
        raise RuntimeError("AdminGetUser response has no UserAttributes list")

    subjects = [
        attribute.get("Value")
        for attribute in attributes
        if isinstance(attribute, dict) and attribute.get("Name") == "sub"
    ]
    if len(subjects) != 1 or not isinstance(subjects[0], str) or not subjects[0]:
        raise RuntimeError("Expected exactly one non-empty Cognito sub attribute")
    return subjects[0]


def main() -> None:
    args = _parse_args()

    try:
        import boto3
    except ImportError as exc:
        raise RuntimeError(
            "boto3 is required. Install it explicitly with "
            "`python -m pip install -r tools/requirements.txt`."
        ) from exc

    session = boto3.session.Session(profile_name=args.profile)
    cognito = session.client("cognito-idp", region_name=args.region)
    dynamodb = session.client("dynamodb", region_name=args.region)

    temporary_password = _new_temporary_password()
    user_id = uuid.uuid4().hex

    cognito.admin_create_user(
        UserPoolId=args.user_pool_id,
        Username=args.login_id,
        TemporaryPassword=temporary_password,
        MessageAction="SUPPRESS",
    )

    try:
        user_response = cognito.admin_get_user(
            UserPoolId=args.user_pool_id,
            Username=args.login_id,
        )
        auth_subject = _subject_from_admin_get_user(user_response)

        common = {
            "user_id": _s(user_id),
            "auth_subject": _s(auth_subject),
            "login_id": _s(args.login_id),
            "role": _s("teacher"),
            "status": _s("active"),
        }
        dynamodb.transact_write_items(
            TransactItems=[
                {
                    "Put": {
                        "TableName": args.table_name,
                        "Item": {
                            "pk": _s(f"AUTH#{auth_subject}"),
                            "sk": _s("PROFILE"),
                            "entity": _s("auth_user"),
                            **common,
                        },
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
                {
                    "Put": {
                        "TableName": args.table_name,
                        "Item": {
                            "pk": _s(f"USER#{user_id}"),
                            "sk": _s("PROFILE"),
                            "entity": _s("user"),
                            **common,
                        },
                        "ConditionExpression": "attribute_not_exists(pk)",
                    }
                },
            ]
        )
    except Exception as original_exc:
        try:
            cognito.admin_delete_user(
                UserPoolId=args.user_pool_id,
                Username=args.login_id,
            )
        except Exception as cleanup_exc:
            raise RuntimeError(
                "Teacher bootstrap failed after Cognito user creation, "
                "and Cognito cleanup also failed."
            ) from cleanup_exc
        raise original_exc

    print(
        json.dumps(
            {
                "user_id": user_id,
                "login_id": args.login_id,
                "temporary_password": temporary_password,
                "note": "The temporary password is shown only in this command output.",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
