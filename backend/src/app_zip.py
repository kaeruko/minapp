from __future__ import annotations

import io
import mimetypes
import stat
import zipfile
from pathlib import PurePosixPath

from errors import ApiProblem

MAX_ZIP_BYTES = 2 * 1024 * 1024
MAX_UNCOMPRESSED_BYTES = 8 * 1024 * 1024
MAX_FILE_BYTES = 4 * 1024 * 1024
MAX_FILE_COUNT = 100

_ALLOWED_SUFFIXES = {
    ".html",
    ".css",
    ".js",
    ".mjs",
    ".json",
    ".txt",
    ".png",
    ".jpg",
    ".jpeg",
    ".gif",
    ".webp",
    ".ico",
    ".mp3",
    ".m4a",
    ".ogg",
    ".wav",
}


def safe_zip_paths(data: bytes) -> list[str]:
    if not isinstance(data, bytes):
        raise TypeError("ZIP payload must be bytes")
    if not data:
        raise ApiProblem(400, "empty_zip", "ZIPファイルが空です。")
    if len(data) > MAX_ZIP_BYTES:
        raise ApiProblem(413, "zip_too_large", "ZIPファイルは2MB以下にしてください。")

    try:
        archive = zipfile.ZipFile(io.BytesIO(data))
    except zipfile.BadZipFile as exc:
        raise ApiProblem(400, "invalid_zip", "正しいZIPファイルではありません。") from exc

    files: list[str] = []
    seen: set[str] = set()
    total_uncompressed = 0

    with archive:
        for info in archive.infolist():
            raw_name = info.filename
            if not isinstance(raw_name, str) or not raw_name:
                raise ApiProblem(400, "invalid_zip_path", "ZIP内に不正なファイル名があります。")
            if "\\" in raw_name or "\x00" in raw_name or raw_name.startswith("/"):
                raise ApiProblem(400, "invalid_zip_path", f"ZIP内のパスが不正です: {raw_name}")

            parts = raw_name.rstrip("/").split("/")
            if any(part in {"", ".", ".."} for part in parts):
                raise ApiProblem(400, "invalid_zip_path", f"ZIP内のパスが不正です: {raw_name}")

            mode = (info.external_attr >> 16) & 0o170000
            if mode == stat.S_IFLNK:
                raise ApiProblem(400, "zip_symlink_forbidden", "ZIP内のシンボリックリンクは使えません。")
            if info.flag_bits & 0x1:
                raise ApiProblem(400, "encrypted_zip_forbidden", "暗号化ZIPは使えません。")
            if info.is_dir():
                continue

            path = PurePosixPath(raw_name).as_posix()
            if path in seen:
                raise ApiProblem(400, "duplicate_zip_path", f"ZIP内に同名ファイルがあります: {path}")
            seen.add(path)

            suffix = PurePosixPath(path).suffix.lower()
            if suffix not in _ALLOWED_SUFFIXES:
                raise ApiProblem(400, "unsupported_file_type", f"MVPではこの種類のファイルは使えません: {path}")
            if info.file_size > MAX_FILE_BYTES:
                raise ApiProblem(413, "file_too_large", f"ZIP内のファイルが大きすぎます: {path}")

            total_uncompressed += info.file_size
            if total_uncompressed > MAX_UNCOMPRESSED_BYTES:
                raise ApiProblem(413, "zip_expands_too_large", "ZIP展開後の合計サイズは8MB以下にしてください。")

            files.append(path)
            if len(files) > MAX_FILE_COUNT:
                raise ApiProblem(413, "too_many_files", "ZIP内のファイル数は100個以下にしてください。")

        if "index.html" not in seen:
            raise ApiProblem(400, "index_missing", "ZIP直下に index.html が必要です。")

        bad_file = archive.testzip()
        if bad_file is not None:
            raise ApiProblem(400, "invalid_zip_crc", f"ZIP内のファイルが破損しています: {bad_file}")

    files.sort()
    return files


def content_type(path: str) -> str:
    suffix = PurePosixPath(path).suffix.lower()
    explicit = {
        ".html": "text/html; charset=utf-8",
        ".css": "text/css; charset=utf-8",
        ".js": "text/javascript; charset=utf-8",
        ".mjs": "text/javascript; charset=utf-8",
        ".json": "application/json; charset=utf-8",
        ".txt": "text/plain; charset=utf-8",
        ".mp3": "audio/mpeg",
        ".m4a": "audio/mp4",
        ".ogg": "audio/ogg",
        ".wav": "audio/wav",
    }
    if suffix in explicit:
        return explicit[suffix]
    guessed, _ = mimetypes.guess_type(path)
    return guessed or "application/octet-stream"
