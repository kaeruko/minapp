from __future__ import annotations

import argparse
import base64
import json
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.error import HTTPError
from urllib.parse import parse_qsl, urljoin, urlparse
from urllib.request import Request, urlopen

REPO_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = REPO_ROOT / "apps" / "web"
BACKEND_SRC = REPO_ROOT / "backend" / "src"
MAX_REQUEST_BODY_BYTES = 3 * 1024 * 1024

if not WEB_ROOT.is_dir():
    raise RuntimeError(f"Web root does not exist: {WEB_ROOT}")
if not BACKEND_SRC.is_dir():
    raise RuntimeError(f"Backend source directory does not exist: {BACKEND_SRC}")

sys.path.insert(0, str(BACKEND_SRC))
from handler import lambda_handler  # noqa: E402


class MinAppDevServer(ThreadingHTTPServer):
    api_base_url: str | None


class MinAppDevHandler(SimpleHTTPRequestHandler):
    server: MinAppDevServer

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self) -> None:  # noqa: N802
        if self._handle_api_if_needed("GET"):
            return
        super().do_GET()

    def do_POST(self) -> None:  # noqa: N802
        if not self._handle_api_if_needed("POST"):
            self.send_error(405, "POST is only supported below /api/")

    def do_DELETE(self) -> None:  # noqa: N802
        if not self._handle_api_if_needed("DELETE"):
            self.send_error(405, "DELETE is only supported below /api/")

    def _handle_api_if_needed(self, method: str) -> bool:
        parsed = urlparse(self.path)
        if not parsed.path.startswith("/api/"):
            return False

        api_path = parsed.path.removeprefix("/api")
        if not api_path.startswith("/"):
            raise RuntimeError(f"Invalid API path after prefix removal: {api_path!r}")

        body = self._request_body()
        if self.server.api_base_url is not None:
            self._proxy_remote_api(method, api_path, parsed.query, body)
        else:
            self._invoke_local_api(method, api_path, parsed.query, body)
        return True

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
        method: str,
        path: str,
        query: str,
        body: bytes | None,
    ) -> None:
        if self.server.api_base_url is None:
            raise RuntimeError("Remote API base URL is not configured")

        target = urljoin(self.server.api_base_url.rstrip("/") + "/", path.lstrip("/"))
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

        self.send_response(status)
        content_type = response_headers.get("content-type")
        if content_type is not None:
            self.send_header("content-type", content_type)
        self.send_header("cache-control", "no-store")
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
    parser.add_argument(
        "--api-base-url",
        help=(
            "Explicitly proxy /api requests to a deployed MinApp API. "
            "When omitted, the local Lambda handler is used."
        ),
    )
    args = parser.parse_args()

    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")

    if args.api_base_url is not None:
        parsed = urlparse(args.api_base_url)
        if parsed.scheme != "https" or not parsed.netloc:
            parser.error("--api-base-url must be an absolute HTTPS URL")
        if parsed.query or parsed.fragment:
            parser.error("--api-base-url must not contain a query or fragment")

    return args


def main() -> None:
    args = _parse_args()
    server = MinAppDevServer((args.host, args.port), MinAppDevHandler)
    server.api_base_url = args.api_base_url

    address = json.dumps(
        {"host": args.host, "port": args.port, "api_base_url": args.api_base_url},
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
