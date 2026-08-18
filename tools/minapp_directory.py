from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY_SRC = ROOT / "directory" / "src"
if str(DIRECTORY_SRC) not in sys.path:
    sys.path.insert(0, str(DIRECTORY_SRC))

from directory_admin import DirectoryAdminService  # noqa: E402
from directory_store import DirectoryStore  # noqa: E402


def _client(profile: str | None, region: str | None) -> Any:
    import boto3

    session = boto3.Session(profile_name=profile)
    return session.client("dynamodb", region_name=region)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Operator-only MinApp Directory administration CLI."
    )
    parser.add_argument("--table-name", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--region")

    root = parser.add_subparsers(dest="resource", required=True)
    tenant = root.add_parser("tenant")
    commands = tenant.add_subparsers(dest="command", required=True)

    create = commands.add_parser("create")
    create.add_argument("--display-name", required=True)

    register_existing = commands.add_parser("register-existing")
    register_existing.add_argument("--tenant-id", required=True)
    register_existing.add_argument("--display-name", required=True)
    register_existing.add_argument("--api-base-url", required=True)

    activate = commands.add_parser("activate")
    activate.add_argument("--tenant-id", required=True)

    update = commands.add_parser("update-endpoint")
    update.add_argument("--tenant-id", required=True)
    update.add_argument("--api-base-url", required=True)

    rotate = commands.add_parser("rotate-code")
    rotate.add_argument("--tenant-id", required=True)

    deactivate = commands.add_parser("deactivate")
    deactivate.add_argument("--tenant-id", required=True)

    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    store = DirectoryStore(
        args.table_name,
        client=_client(args.profile, args.region),
    )
    service = DirectoryAdminService(store)

    if args.command == "create":
        result = service.create_tenant(args.display_name)
    elif args.command == "register-existing":
        result = service.register_existing_tenant(
            args.tenant_id,
            args.display_name,
            args.api_base_url,
        )
    elif args.command == "activate":
        result = service.activate(args.tenant_id)
    elif args.command == "update-endpoint":
        result = service.update_endpoint(args.tenant_id, args.api_base_url)
    elif args.command == "rotate-code":
        result = service.rotate_code(args.tenant_id)
    elif args.command == "deactivate":
        result = service.deactivate(args.tenant_id)
    else:
        raise RuntimeError("unsupported command")

    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
