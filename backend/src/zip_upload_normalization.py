from __future__ import annotations

import io
import stat
import zipfile
from pathlib import PurePosixPath

from errors import ApiProblem
from phase2_backend import _safe_zip_paths


def _is_desktop_packaging_metadata(parts: list[str]) -> bool:
    return parts[0] == "__MACOSX" or parts[-1] == ".DS_Store"


def _strip_desktop_packaging_metadata(zip_bytes: bytes) -> bytes | None:
    """Remove only well-known Finder metadata, after validating archive paths.

    Returns None when no such metadata exists so callers can preserve ordinary
    uploads byte-for-byte.
    """
    try:
        archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except zipfile.BadZipFile as exc:
        raise ApiProblem(400, "invalid_zip", "正しいZIPファイルではありません。") from exc

    with archive:
        kept: list[zipfile.ZipInfo] = []
        removed_any = False
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

            if _is_desktop_packaging_metadata(parts):
                removed_any = True
                continue
            kept.append(info)

        if not removed_any:
            return None

        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as cleaned:
            for info in kept:
                cleaned.writestr(PurePosixPath(info.filename).as_posix(), archive.read(info))
        return output.getvalue()


def _unwrap_single_top_level_folder(zip_bytes: bytes) -> tuple[bytes, list[str]]:
    try:
        archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except zipfile.BadZipFile as exc:
        raise ApiProblem(400, "invalid_zip", "正しいZIPファイルではありません。") from exc

    with archive:
        file_infos = [info for info in archive.infolist() if not info.is_dir()]
        if not file_infos:
            raise ApiProblem(400, "index_missing", "ZIP内に index.html が必要です。")

        names = [PurePosixPath(info.filename).as_posix() for info in file_infos]
        if any("/" not in name for name in names):
            raise ApiProblem(
                400,
                "index_missing",
                "index.html はZIP直下、またはZIP内の1つのフォルダ直下に置いてください。",
            )

        roots = {name.split("/", 1)[0] for name in names}
        if len(roots) != 1:
            raise ApiProblem(
                400,
                "index_missing",
                "ZIP直下に index.html がない場合、ZIP内のトップフォルダは1つだけにしてください。",
            )

        root = next(iter(roots))
        if f"{root}/index.html" not in names:
            raise ApiProblem(
                400,
                "index_missing",
                "index.html はZIP直下、またはZIP内の1つのフォルダ直下に置いてください。",
            )

        bad_file = archive.testzip()
        if bad_file is not None:
            raise ApiProblem(400, "invalid_zip_crc", f"ZIP内のファイルが破損しています: {bad_file}")

        output = io.BytesIO()
        with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as normalized:
            prefix = f"{root}/"
            for info, name in zip(file_infos, names, strict=True):
                if not name.startswith(prefix):
                    raise ApiProblem(
                        400,
                        "index_missing",
                        "ZIP内のトップフォルダ構成を判定できませんでした。",
                    )
                relative = name[len(prefix) :]
                if not relative:
                    continue
                normalized.writestr(relative, archive.read(info))

    normalized_bytes = output.getvalue()
    return normalized_bytes, _safe_zip_paths(normalized_bytes)


def normalize_uploaded_zip(zip_bytes: bytes) -> tuple[bytes, list[str]]:
    """Return a canonical app ZIP with index.html at the archive root.

    Already-canonical ZIPs are returned byte-for-byte unchanged. Desktop ZIPs
    may contain Finder packaging metadata; only `__MACOSX` and `.DS_Store` are
    removed. If root index.html is then missing, exactly one top-level folder
    may be unwrapped when it directly contains index.html.

    Ambiguous layouts and all existing security validation errors are rejected.
    """
    initial_error: ApiProblem | None = None
    try:
        return zip_bytes, _safe_zip_paths(zip_bytes)
    except ApiProblem as exc:
        if exc.error not in {"index_missing", "unsupported_file_type"}:
            raise
        initial_error = exc

    cleaned = _strip_desktop_packaging_metadata(zip_bytes)
    candidate = zip_bytes if cleaned is None else cleaned

    try:
        files = _safe_zip_paths(candidate)
        return candidate, files
    except ApiProblem as exc:
        if exc.error != "index_missing":
            raise
        if cleaned is None and initial_error.error == "unsupported_file_type":
            raise initial_error

    return _unwrap_single_top_level_folder(candidate)
