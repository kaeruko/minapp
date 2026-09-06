from __future__ import annotations

import io
import zipfile
from pathlib import PurePosixPath

from errors import ApiProblem
from phase2_backend import _safe_zip_paths


def normalize_uploaded_zip(zip_bytes: bytes) -> tuple[bytes, list[str]]:
    """Return a canonical app ZIP with index.html at the archive root.

    Already-canonical ZIPs are returned byte-for-byte unchanged. If the only
    problem is a missing root index.html, accept exactly one common top-level
    directory when that directory contains index.html directly, and rewrite
    the archive without that one directory level.

    Ambiguous layouts are deliberately rejected rather than guessed.
    """
    try:
        return zip_bytes, _safe_zip_paths(zip_bytes)
    except ApiProblem as exc:
        if exc.error != "index_missing":
            raise

    try:
        archive = zipfile.ZipFile(io.BytesIO(zip_bytes))
    except zipfile.BadZipFile as exc:
        # _safe_zip_paths normally owns this error, but keep the helper
        # fail-fast if the archive changes between validation attempts.
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
    files = _safe_zip_paths(normalized_bytes)
    return normalized_bytes, files
