from __future__ import annotations

import argparse
import base64
import json
import sys
import time
from dataclasses import dataclass
from http.cookies import SimpleCookie
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import parse_qsl, urljoin, urlparse
from urllib.request import Request, urlopen

REPO_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = REPO_ROOT / "apps" / "web"
BACKEND_SRC = REPO_ROOT / "backend" / "src"
DIRECTORY_SRC = REPO_ROOT / "directory" / "src"
MAX_REQUEST_BODY_BYTES = 3 * 1024 * 1024
MAX_DESCRIPTOR_VALID_FOR_SECONDS = 86400
TENANT_COOKIE_NAME = "minapp_tenant_id"

if not WEB_ROOT.is_dir():
    raise RuntimeError(f"Web root does not exist: {WEB_ROOT}")
if not BACKEND_SRC.is_dir():
    raise RuntimeError(f"Backend source directory does not exist: {BACKEND_SRC}")
if not DIRECTORY_SRC.is_dir():
    raise RuntimeError(f"Directory source directory does not exist: {DIRECTORY_SRC}")

sys.path.insert(0, str(BACKEND_SRC))
sys.path.insert(0, str(DIRECTORY_SRC))
from directory_core import (  # noqa: E402
    API_PROTOCOL_VERSION,
    SCHEMA_VERSION,
    validate_api_base_url,
    validate_display_name,
    validate_tenant_id,
)
from handler import lambda_handler  # noqa: E402


@dataclass(frozen=True)
class FederationProxyProblem(Exception):
    status_code: int
    code: str
    message: str

    def __str__(self) -> str:
        return self.message


def validate_directory_descriptor(
    payload: object, *, expected_tenant_id: str
) -> dict[str, object]:
    tenant_id = validate_tenant_id(expected_tenant_id)
    expected_fields = {
        "schema_version",
        "tenant_id",
        "display_name",
        "api_base_url",
        "api_protocol_version",
        "config_revision",
        "valid_for_seconds",
    }
    if not isinstance(payload, dict) or set(payload) != expected_fields:
        raise ValueError("Directory descriptor schema is invalid")
    if payload.get("schema_version") != SCHEMA_VERSION:
        raise ValueError("Directory schema_version is unsupported")

    descriptor_tenant_id = validate_tenant_id(payload.get("tenant_id"))
    if descriptor_tenant_id != tenant_id:
        raise ValueError("Directory returned a different tenant_id")
    display_name = validate_display_name(payload.get("display_name"))
    api_base_url = validate_api_base_url(payload.get("api_base_url"))

    api_protocol_version = payload.get("api_protocol_version")
    if type(api_protocol_version) is not int or api_protocol_version != API_PROTOCOL_VERSION:
        raise ValueError("Directory api_protocol_version is unsupported")
    config_revision = payload.get("config_revision")
    if type(config_revision) is not int or config_revision < 1:
        raise ValueError("Directory config_revision is invalid")
    valid_for_seconds = payload.get("valid_for_seconds")
    if (
        type(valid_for_seconds) is not int
        or valid_for_seconds < 1
        or valid_for_seconds > MAX_DESCRIPTOR_VALID_FOR_SECONDS
    ):
        raise ValueError("Directory valid_for_seconds is invalid")

    return {
        "schema_version": SCHEMA_VERSION,
        "tenant_id": descriptor_tenant_id,
        "display_name": display_name,
        "api_base_url": api_base_url,
        "api_protocol_version": api_protocol_version,
        "config_revision": config_revision,
        "valid_for_seconds": valid_for_seconds,
    }


class MinAppDevServer(ThreadingHTTPServer):
    api_base_url: str | None
    directory_api_base_url: str | None
    tenant_cache: dict[str, tuple[float, dict[str, object]]]


class MinAppDevHandler(SimpleHTTPRequestHandler):
    server: MinAppDevServer

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self) -> None:  # noqa: N802
        if self._handle_web_config():
            return
        if self._handle_directory_if_needed("GET"):
            return
        if self._handle_api_if_needed("GET"):
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if self._handle_federation_if_needed():
            return
        if self._handle_directory_if_needed("POST"):
            return
        if self._handle_api_if_needed("POST"):
            return
        self.send_error(405, "POST is only supported by MinApp API routes")

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._handle_api_if_needed("DELETE"):
            self.send_error(405, "DELETE is only supported below /api/")

    def _handle_web_config(self) -> bool:
        parsed = urlparse(self.path)
        if parsed.path != "/web-config":
            return False
        if parsed.query:
            self._write_json_response(
                400,
                {"error": "invalid_request", "message": "Query parameters are not accepted."},
            )
            return True

        if self.server.directory_api_base_url is not None:
            mode = "federated"
        elif self.server.api_base_url is not None:
            mode = "fixed"
        else:
            mode = "local"
        self._write_json_response(200, {"mode": mode})
        return True

    def _handle_federation_if_needed(self) -> bool:
        parsed = urlparse(self.path)
        if parsed.path not in {"/federation/select", "/federation/clear"}:
            return False
        if self.server.directory_api_base_url is None:
            self._write_json_response(
                404,
                {
                    "error": "federation_not_configured",
                    "message": "Federated classroom routing is not configured.",
                },
            )
            return True
        if parsed.query:
            self._write_json_response(
                400,
                {"error": "invalid_request", "message": "Query parameters are not accepted."},
            )
            return True

        try:
            body = self._request_body()
            if parsed.path == "/federation/clear":
                self._strict_json_body(body, expected_fields=set())
                self._write_json_response(
                    200,
                    {"cleared": True},
                    extra_headers={"Set-Cookie": self._clear_tenant_cookie()},
                )
                return True

            payload = self._strict_json_body(body, expected_fields={"tenant_id"})
            tenant_id = validate_tenant_id(payload.get("tenant_id"))
            descriptor = self._directory_descriptor_for_tenant(tenant_id, force_refresh=True)
            self._write_json_response(
                200,
                descriptor,
                extra_headers={"Set-Cookie": self._tenant_cookie(tenant_id)},
            )
        except FederationProxyProblem as problem:
            self._write_json_response(
                problem.status_code,
                {"error": problem.code, "message": problem.message},
            )
        except (UnicodeError, ValueError, json.JSONDecodeError):
            self._write_json_response(
                400,
                {"error": "invalid_request", "message": "The federation request is invalid."},
            )
        return True

    def _handle_directory_if_needed(self, method: str) -> bool:
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/directory/"):
            return False
        if self.server.directory_api_base_url is None:
            self._write_json_response(
                404,
                {
                    "error": "federation_not_configured",
                    "message": "Federated classroom routing is not configured.",
                },
            )
            return True

        directory_path = parsed.path.removeprefix("/directory")
        allowed = method == "POST" and directory_path == "/v1/classrooms/resolve"
        if not allowed and method == "GET" and directory_path.startswith("/v1/tenants/"):
            tenant_id = directory_path.removeprefix("/v1/tenants/")
            try:
                validate_tenant_id(tenant_id)
                allowed = True
            except ValueError:
                allowed = False
        if not allowed:
            self._write_json_response(
                404,
                {"error": "not_found", "message": "The Directory route is not available."},
            )
            return True

        body = self._request_body()
        self._proxy_remote_api(
            self.server.directory_api_base_url,
            method,
            directory_path,
            parsed.query,
            body,
        )
        return True

    def _handle_api_if_needed(self, method: str) -> bool:
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            return False

        api_path = parsed.path.removeprefix("/api")
        if not api_path.startswith("/"):
            raise RuntimeError(f"Invalid API path after prefix removal: {api_path!r}")

        body = self._request_body()
        if self.server.directory_api_base_url is not None:
            try:
                tenant_id = self._selected_tenant_id()
                descriptor = self._directory_descriptor_for_tenant(tenant_id)
                api_base_url = descriptor.get("api_base_url")
                if not isinstance(api_base_url, str):
                    raise RuntimeError("Validated Directory descriptor has no api_base_url")
                self._proxy_remote_api(api_base_url, method, api_path, parsed.query, body)
            except FederationProxyProblem as problem:
                self._write_json_response(
                    problem.status_code,
                    {"error": problem.code, "message": problem.message},
                )
            return True

        if self.server.api_base_url is not None:
            self._proxy_remote_api(
                self.server.api_base_url,
                method,
                api_path,
                parsed.query,
                body,
            )
        else:
            self._invoke_local_api(method, api_path, parsed.query, body)
        return True

    def _selected_tenant_id(self) -> str:
        raw_cookie = self.headers.get("cookie")
        if raw_cookie is None:
            raise FederationProxyProblem(
                409,
                "classroom_not_selected",
                "Select a classroom before using the tenant API.",
            )
        cookie = SimpleCookie()
        try:
            cookie.load(raw_cookie)
        except Exception as exc:
            raise FederationProxyProblem(
                400,
                "invalid_request",
                "The classroom routing cookie is invalid.",
            ) from exc
        morsel = cookie.get(TENANT_COOKIE_NAME)
        if morsel is None:
            raise FederationProxyProblem(
                409,
                "classroom_not_selected",
                "Select a classroom before using the tenant API.",
            )
        try:
            return validate_tenant_id(morsel.value)
        except ValueError as exc:
            raise FederationProxyProblem(
                400,
                "invalid_request",
                "The classroom routing cookie is invalid.",
            ) from exc

    def _directory_descriptor_for_tenant(
        self, tenant_id: str, *, force_refresh: bool = False
    ) -> dict[str, object]:
        tenant_id = validate_tenant_id(tenant_id)
        now = time.monotonic()
        cached = self.server.tenant_cache.get(tenant_id)
        if not force_refresh and cached is not None and cached[0] > now:
            return cached[1]

        if self.server.directory_api_base_url is None:
            raise RuntimeError("Directory API base URL is not configured")
        target = urljoin(
            self.server.directory_api_base_url.rstrip("/") + "/",
            f"v1/tenants/{tenant_id}",
        )
        request = Request(target, headers={"accept": "application/json"}, method="GET")
        try:
            with urlopen(request, timeout=15) as remote:
                status = remote.status
                content_type = remote.headers.get("content-type")
                encoded = remote.read()
        except HTTPError as exc:
            status = exc.code
            content_type = exc.headers.get("content-type")
            encoded = exc.read()
        except (TimeoutError, URLError, OSError) as exc:
            raise FederationProxyProblem(
                503,
                "directory_unavailable",
                "The Directory is temporarily unavailable.",
            ) from exc

        payload: object | None = None
        if content_type is not None and content_type.lower().startswith("application/json"):
            try:
                payload = json.loads(encoded.decode("utf-8"))
            except (UnicodeError, json.JSONDecodeError):
                payload = None

        if status < 200 or status >= 300:
            if isinstance(payload, dict):
                code = payload.get("error")
                message = payload.get("message")
                if isinstance(code, str) and isinstance(message, str):
                    raise FederationProxyProblem(status, code, message)
            raise FederationProxyProblem(
                503,
                "directory_unavailable",
                "The Directory returned an invalid error response.",
            )

        try:
            descriptor = validate_directory_descriptor(
                payload,
                expected_tenant_id=tenant_id,
            )
        except ValueError as exc:
            raise FederationProxyProblem(
                502,
                "invalid_directory_response",
                "The Directory returned an invalid tenant descriptor.",
            ) from exc

        valid_for_seconds = descriptor.get("valid_for_seconds")
        if type(valid_for_seconds) is not int:
            raise RuntimeError("Validated Directory descriptor has invalid TTL")
        self.server.tenant_cache[tenant_id] = (now + valid_for_seconds, descriptor)
        return descriptor

    @staticmethod
    def _tenant_cookie(tenant_id: str) -> str:
        tenant_id = validate_tenant_id(tenant_id)
        return f"{TENANT_COOKIE_NAME}={tenant_id}; Path=/; HttpOnly; SameSite=Strict"

    @staticmethod
    def _clear_tenant_cookie() -> str:
        return f"{TENANT_COOKIE_NAME}=; Path=/; Max-Age=0; HttpOnly; SameSite=Strict"

    def _request_body(self) -> bytes | None:
        raw_length = self.headers.get("content-length")
        if raw_length is None:
            return None

        try:
            length = int(raw_length)
        except ValueError as exc:
            raise ValueError("content-length must be an integer") from exc
        if length < 0 or length > MAX_REQUEST_BODY_BYTES:
            raise ValueError(
                f"Request body must be between 0 and {MAX_REQUEST_BODY_BYTES} bytes"
            )
        return self.rfile.read(length)

    @staticmethod
    def _strict_json_body(
        body: bytes | None, *, expected_fields: set[str]
    ) -> dict[str, Any]:
        if body is None or len(body) > 4096:
            raise ValueError("Request body is missing or too large")
        payload = json.loads(body.decode("utf-8"))
        if not isinstance(payload, dict) or set(payload) != expected_fields:
            raise ValueError("Request body schema is invalid")
        return payload

    @staticmethod
    def _query_parameters(query: str) -> dict[str, str] | None:
        if not query:
            return None
        pairs = parse_qsl(query, keep_blank_values=True, strict_parsing=True)
        result: dict[str, str] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate query parameter is not supported: {key}")
            result[key] = value
        return result

    def _invoke_local_api(
        self,
        method: str,
        path: str,
        query: str,
        body: bytes | None,
    ) -> None:
        event: dict[str, Any] = {
            "rawPath": path,
            "requestContext": {
                "http": {"method": method},
                "domainName": f"{self.server.server_address[0]}:{self.server.server_address[1]}",
            },
        }

        params = self._query_parameters(query)
        if params is not None:
            event["queryStringParameters"] = params

        content_type = self.headers.get("content-type")
        authorization = self.headers.get("authorization")
        headers: dict[str, str] = {}
        if content_type is not None:
            headers["content-type"] = content_type
        if authorization is not None:
            headers["authorization"] = authorization
        if headers:
            event["headers"] = headers

        if body is not None:
            if content_type is not None and content_type.split(";", 1)[0].strip().lower() in {
                "application/zip",
                "application/x-zip-compressed",
            }:
                event["body"] = base64.b64encode(body).decode("ascii")
                event["isBase64Encoded"] = True
            else:
                event["body"] = body.decode("utf-8")

        response = lambda_handler(event, None)
        self._write_lambda_response(response)

    def _proxy_remote_api(
        self,
        base_url: str,
        method: str,
        path: str,
        query: str,
        body: bytes | None,
    ) -> None:
        target = urljoin(base_url.rstrip("/") + "/", path.lstrip("/"))
        if query:
            target = f"{target}?{query}"

        headers: dict[str, str] = {"accept": "application/json"}
        for header_name in ("authorization", "content-type"):
            value = self.headers.get(header_name)
            if value is not None:
                headers[header_name] = value

        request = Request(target, data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=30) as remote:
                status = remote.status
                response_headers = remote.headers
                encoded = remote.read()
        except HTTPError as exc:
            status = exc.code
            response_headers = exc.headers
            encoded = exc.read()
        except (TimeoutError, URLError, OSError):
            self._write_json_response(
                502,
                {"error": "upstream_unavailable", "message": "The upstream API is unavailable."},
            )
            return

        self.send_response(status)
        content_type = response_headers.get("content-type")
        if content_type is not None:
            self.send_header("content-type", content_type)
        self.send_header("cache-control", "no-store")
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _write_json_response(
        self,
        status_code: int,
        payload: dict[str, object],
        *,
        extra_headers: dict[str, str] | None = None,
    ) -> None:
        encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status_code)
        self.send_header("content-type", "application/json; charset=utf-8")
        self.send_header("cache-control", "no-store")
        self.send_header("x-content-type-options", "nosniff")
        if extra_headers is not None:
            for name, value in extra_headers.items():
                self.send_header(name, value)
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _write_lambda_response(self, response: dict[str, Any]) -> None:
        status_code = response.get("statusCode")
        headers = response.get("headers")
        body = response.get("body")

        if not isinstance(status_code, int):
            raise TypeError("Lambda response statusCode must be an integer")
        if not isinstance(headers, dict):
            raise TypeError("Lambda response headers must be an object")
        if not isinstance(body, str):
            raise TypeError("Lambda response body must be a string")

        if response.get("isBase64Encoded") is True:
            encoded = base64.b64decode(body, validate=True)
        else:
            encoded = body.encode("utf-8")

        self.send_response(status_code)
        for name, value in headers.items():
            if not isinstance(name, str) or not isinstance(value, str):
                raise TypeError("Lambda response headers must contain string keys and values")
            self.send_header(name, value)
        self.send_header("content-length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the みんアプ local web server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4173)
    remote = parser.add_mutually_exclusive_group()
    remote.add_argument(
        "--api-base-url",
        help="Explicitly proxy /api requests to one deployed MinApp tenant API.",
    )
    remote.add_argument(
        "--directory-api-base-url",
        help=(
            "Enable federated classroom selection through the central MinApp Directory. "
            "Tenant API targets are resolved by tenant_id and never accepted from browser input."
        ),
    )
    args = parser.parse_args()

    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")

    for argument_name in ("api_base_url", "directory_api_base_url"):
        value = getattr(args, argument_name)
        if value is None:
            continue
        try:
            setattr(args, argument_name, validate_api_base_url(value))
        except ValueError as exc:
            parser.error(f"--{argument_name.replace('_', '-')} is invalid: {exc}")

    return args


def main() -> None:
    args = _parse_args()
    server = MinAppDevServer((args.host, args.port), MinAppDevHandler)
    server.api_base_url = args.api_base_url
    server.directory_api_base_url = args.directory_api_base_url
    server.tenant_cache = {}

    mode = (
        "federated"
        if args.directory_api_base_url is not None
        else "fixed"
        if args.api_base_url is not None
        else "local"
    )
    address = json.dumps(
        {
            "host": args.host,
            "port": args.port,
            "mode": mode,
            "api_base_url": args.api_base_url,
            "directory_api_base_url": args.directory_api_base_url,
        },
        ensure_ascii=False,
    )
    print(f"minapp dev server started: {address}")
    print(f"open http://{args.host}:{args.port}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
