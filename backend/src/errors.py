from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ApiProblem(Exception):
    status_code: int
    error: str
    message: str
