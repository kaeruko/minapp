from __future__ import annotations

import argparse
import copy
import json
import re
import secrets
from typing import Any

_LOGIN_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{2,31}$")
_TEMPORARY_PASSWORD_ALPHABET = "23456789"
_TEMPORARY_PASSWORD_LENGTH = 8
_MAX_TRANSACTION_ITEMS = 100


def _new_temporary_password() -> str:
    return "".join(
        secrets.choice(_TEMPORARY_PASSWORD_ALPHABET)
        for _ in range(_TEMPORARY_PASSWORD_LENGTH)
    )


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Replace a MinApp Cognito login ID while preserving the existing "
            "application user_id, role, memberships, display-name metadata, and app metadata."
        )
    )
    parser.add_argument("--user-pool-id", required=True)
    parser.add_argument("--table-name", required=True)
    parser.add_argument("--old-login-id", required=True)
    parser.add_argument("--new-login-id", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--region", required=True)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Perform the migration. Without this flag the command only validates and prints a plan.",
    )
    args = parser.parse_args()

    for field in ("old_login_id", "new_login_id"):
        value = getattr(args, field)
        if _LOGIN_ID_RE.fullmatch(value) is None:
            parser.error(
                f"--{field.replace('_', '-')} must be 3-32 lowercase ASCII letters, digits, or hyphens, "
                "and must start with a letter or digit"
            )
    if args.old_login_id == args.new_login_id:
        parser.error("--old-login-id and --new-login-id must be different")
    return args


def _s(value: str) -> dict[str, str]:
    if not isinstance(value, str) or not value:
        raise ValueError("DynamoDB strings must be non-empty strings")
    return {"S": value}


def _item_string(item: dict[str, Any], key: str) -> str:
    raw = item.get(key)
    if not isinstance(raw, dict):
        raise RuntimeError(f"DynamoDB item is missing string attribute {key!r}")
    value = raw.get("S")
    if not isinstance(value, str) or not value:
        raise RuntimeError(f"DynamoDB attribute {key!r} is not a non-empty string")
    return value


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


def _aws_error_code(exc: Exception) -> str | None:
    response = getattr(exc, "response", None)
    if not isinstance(response, dict):
        return None
    error = response.get("Error")
    if not isinstance(error, dict):
        return None
    code = error.get("Code")
    return code if isinstance(code, str) else None


def _scan_all(dynamodb: Any, table_name: str) -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    request: dict[str, Any] = {"TableName": table_name, "ConsistentRead": True}
    while True:
        response = dynamodb.scan(**request)
        page = response.get("Items")
        if not isinstance(page, list):
            raise RuntimeError("DynamoDB Scan response has no Items list")
        if any(not isinstance(item, dict) for item in page):
            raise RuntimeError("DynamoDB Scan returned a non-object item")
        items.extend(page)
        last_key = response.get("LastEvaluatedKey")
        if last_key is None:
            return items
        if not isinstance(last_key, dict) or not last_key:
            raise RuntimeError("DynamoDB Scan returned an invalid LastEvaluatedKey")
        request["ExclusiveStartKey"] = last_key


def _matching_user(items: list[dict[str, Any]], old_login_id: str) -> dict[str, Any]:
    matches = [
        item
        for item in items
        if item.get("entity") == _s("user") and item.get("login_id") == _s(old_login_id)
    ]
    if len(matches) != 1:
        raise RuntimeError(
            f"Expected exactly one user profile for login_id={old_login_id!r}, found {len(matches)}"
        )
    return matches[0]


def _replacement_items(
    items: list[dict[str, Any]],
    *,
    user_id: str,
    old_login_id: str,
    new_login_id: str,
    old_subject: str,
    new_subject: str,
) -> tuple[list[dict[str, Any]], dict[str, Any], dict[str, Any]]:
    old_auth_pk = f"AUTH#{old_subject}"
    old_auth_matches = [
        item
        for item in items
        if item.get("pk") == _s(old_auth_pk) and item.get("sk") == _s("PROFILE")
    ]
    if len(old_auth_matches) != 1:
        raise RuntimeError(
            f"Expected exactly one auth profile for subject={old_subject!r}, found {len(old_auth_matches)}"
        )
    old_auth_item = old_auth_matches[0]
    if _item_string(old_auth_item, "user_id") != user_id:
        raise RuntimeError("Auth profile user_id does not match user profile")

    changed: list[dict[str, Any]] = []
    for original in items:
        item = copy.deepcopy(original)
        touched = False

        if item.get("login_id") == _s(old_login_id):
            item["login_id"] = _s(new_login_id)
            touched = True
        if item.get("owner_login_id") == _s(old_login_id):
            item["owner_login_id"] = _s(new_login_id)
            touched = True
        if item.get("auth_subject") == _s(old_subject):
            item["auth_subject"] = _s(new_subject)
            touched = True

        if original is old_auth_item:
            item["pk"] = _s(f"AUTH#{new_subject}")
            item["auth_subject"] = _s(new_subject)
            item["login_id"] = _s(new_login_id)
            touched = True

        if touched:
            changed.append(item)

    new_auth_item = next(
        item for item in changed if item.get("pk") == _s(f"AUTH#{new_subject}") and item.get("sk") == _s("PROFILE")
    )
    return changed, old_auth_item, new_auth_item


def _transaction_items(
    changed: list[dict[str, Any]],
    *,
    table_name: str,
    old_auth_item: dict[str, Any],
) -> list[dict[str, Any]]:
    operations: list[dict[str, Any]] = [
        {
            "Delete": {
                "TableName": table_name,
                "Key": {"pk": old_auth_item["pk"], "sk": old_auth_item["sk"]},
                "ConditionExpression": "attribute_exists(pk)",
            }
        }
    ]
    for item in changed:
        operations.append(
            {
                "Put": {
                    "TableName": table_name,
                    "Item": item,
                }
            }
        )
    if len(operations) > _MAX_TRANSACTION_ITEMS:
        raise RuntimeError(
            f"Migration requires {len(operations)} DynamoDB transaction operations; "
            f"the fail-fast limit is {_MAX_TRANSACTION_ITEMS}. No changes were made."
        )
    return operations


def _restore_transaction_items(
    originals: list[dict[str, Any]],
    *,
    table_name: str,
    new_auth_item: dict[str, Any],
) -> list[dict[str, Any]]:
    operations: list[dict[str, Any]] = [
        {
            "Delete": {
                "TableName": table_name,
                "Key": {"pk": new_auth_item["pk"], "sk": new_auth_item["sk"]},
            }
        }
    ]
    operations.extend(
        {"Put": {"TableName": table_name, "Item": item}}
        for item in originals
    )
    if len(operations) > _MAX_TRANSACTION_ITEMS:
        raise RuntimeError("Rollback transaction unexpectedly exceeds DynamoDB transaction limit")
    return operations


def _ensure_cognito_user_absent(cognito: Any, user_pool_id: str, login_id: str) -> None:
    try:
        cognito.admin_get_user(UserPoolId=user_pool_id, Username=login_id)
    except Exception as exc:
        if _aws_error_code(exc) == "UserNotFoundException":
            return
        raise
    raise RuntimeError(f"Cognito user {login_id!r} already exists; migration stopped")


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

    old_cognito = cognito.admin_get_user(
        UserPoolId=args.user_pool_id,
        Username=args.old_login_id,
    )
    old_subject = _subject_from_admin_get_user(old_cognito)
    _ensure_cognito_user_absent(cognito, args.user_pool_id, args.new_login_id)

    items = _scan_all(dynamodb, args.table_name)
    user = _matching_user(items, args.old_login_id)
    user_id = _item_string(user, "user_id")
    if _item_string(user, "auth_subject") != old_subject:
        raise RuntimeError("Cognito subject and DynamoDB user profile do not match")

    affected_originals = [
        copy.deepcopy(item)
        for item in items
        if (
            item.get("login_id") == _s(args.old_login_id)
            or item.get("owner_login_id") == _s(args.old_login_id)
            or item.get("auth_subject") == _s(old_subject)
            or (item.get("pk") == _s(f"AUTH#{old_subject}") and item.get("sk") == _s("PROFILE"))
        )
    ]
    if not affected_originals:
        raise RuntimeError("No DynamoDB records reference the requested login ID")

    plan = {
        "old_login_id": args.old_login_id,
        "new_login_id": args.new_login_id,
        "user_id": user_id,
        "role": _item_string(user, "role"),
        "affected_dynamodb_items": len(affected_originals),
        "will_require_new_temporary_password": True,
        "apply": args.apply,
    }
    print(json.dumps(plan, ensure_ascii=False, indent=2))
    if not args.apply:
        return

    temporary_password = _new_temporary_password()
    cognito.admin_create_user(
        UserPoolId=args.user_pool_id,
        Username=args.new_login_id,
        TemporaryPassword=temporary_password,
        MessageAction="SUPPRESS",
    )

    new_user_created = True
    dynamodb_changed = False
    new_subject: str | None = None
    new_auth_item: dict[str, Any] | None = None
    try:
        new_cognito = cognito.admin_get_user(
            UserPoolId=args.user_pool_id,
            Username=args.new_login_id,
        )
        new_subject = _subject_from_admin_get_user(new_cognito)
        if new_subject == old_subject:
            raise RuntimeError("New Cognito user unexpectedly reused the old subject")

        changed, old_auth_item, new_auth_item = _replacement_items(
            items,
            user_id=user_id,
            old_login_id=args.old_login_id,
            new_login_id=args.new_login_id,
            old_subject=old_subject,
            new_subject=new_subject,
        )
        operations = _transaction_items(
            changed,
            table_name=args.table_name,
            old_auth_item=old_auth_item,
        )
        dynamodb.transact_write_items(TransactItems=operations)
        dynamodb_changed = True

        cognito.admin_delete_user(
            UserPoolId=args.user_pool_id,
            Username=args.old_login_id,
        )
    except Exception as original_exc:
        rollback_errors: list[str] = []
        if dynamodb_changed:
            if new_auth_item is None:
                rollback_errors.append("new auth item was unavailable for DynamoDB rollback")
            else:
                try:
                    dynamodb.transact_write_items(
                        TransactItems=_restore_transaction_items(
                            affected_originals,
                            table_name=args.table_name,
                            new_auth_item=new_auth_item,
                        )
                    )
                except Exception as rollback_exc:
                    rollback_errors.append(f"DynamoDB rollback failed: {rollback_exc!r}")
        if new_user_created:
            try:
                cognito.admin_delete_user(
                    UserPoolId=args.user_pool_id,
                    Username=args.new_login_id,
                )
            except Exception as cleanup_exc:
                rollback_errors.append(f"new Cognito user cleanup failed: {cleanup_exc!r}")
        if rollback_errors:
            raise RuntimeError(
                "Login ID migration failed and rollback was incomplete: " + "; ".join(rollback_errors)
            ) from original_exc
        raise

    print(
        json.dumps(
            {
                "status": "migrated",
                "old_login_id": args.old_login_id,
                "new_login_id": args.new_login_id,
                "user_id": user_id,
                "temporary_password": temporary_password,
                "note": "The new Cognito account requires the normal first-login password change.",
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
