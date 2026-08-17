from __future__ import annotations

import argparse
import json
import sys
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

REPO_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = REPO_ROOT / "apps" / "web"
BACKEND_SRC = REPO_ROOT / "backend" / "src"

if not WEB_ROOT.is_dir():
    raise RuntimeError(f"Web root does not exist: {WEB_ROOT}")
if not BACKEND_SRC.is_dir():
    raise RuntimeError(f"Backend source directory does not exist: {BACKEND_SRC}")

sys.path.insert(0, str(BACKEND_SRC))
from handler import lambda_handler  # noqa: E402


class MinAppDevHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, directory=str(WEB_ROOT), **kwargs)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path.startswith("/api/"):
            self._handle_api_get(parsed.path)
            return
        super().do_GET()

    def _handle_api_get(self, path: str) -> None:
        api_path = path.removeprefix("/api")
        if not api_path.startswith("/"):
            raise RuntimeError(f"Invalid API path after prefix removal: {api_path!r}")

        response = lambda_handler(
            {
                "rawPath": api_path,
                "requestContext": {"http": {"method": "GET"}},
            },
            None,
        )

        status_code = response.get("statusCode")
        headers = response.get("headers")
        body = response.get("body")

        if not isinstance(status_code, int):
            raise TypeError("Lambda response statusCode must be an integer")
        if not isinstance(headers, dict):
            raise TypeError("Lambda response headers must be an object")
        if not isinstance(body, str):
            raise TypeError("Lambda response body must be a string")

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
    parser = argparse.ArgumentParser(description="Run the みんアプ Phase 0 local server")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=4173)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        parser.error("--port must be between 1 and 65535")
    return args


def main() -> None:
    args = _parse_args()
    server = ThreadingHTTPServer((args.host, args.port), MinAppDevHandler)
    address = json.dumps({"host": args.host, "port": args.port}, ensure_ascii=False)
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
