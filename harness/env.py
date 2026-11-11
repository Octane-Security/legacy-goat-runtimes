"""Where the stack's services listen, which profile it runs under, and where the answer key is.

Every value is read from the environment when it is asked for, so a test or a trigger always sees
the current setting. An empty variable counts as unset, as `${VAR:-default}` did in the shell harness.
"""

from __future__ import annotations

import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The ports compose publishes (compose/compose.yaml).
_SERVICE_URLS = {
    "GATEWAY_URL": "http://localhost:8080",
    "COBOL_URL": "http://localhost:8082",
    "FORTRAN_URL": "http://localhost:8083",
    "SAS_URL": "http://localhost:8084",
    "PASCAL_URL": "http://localhost:8085",
    "ABAP_URL": "http://localhost:8086",
}


def setting(name: str, default: str) -> str:
    """An environment variable, or `default` when it is unset or empty."""
    return os.environ.get(name) or default


def url(name: str) -> str:
    """A service's base URL: GATEWAY_URL, COBOL_URL, FORTRAN_URL, SAS_URL, PASCAL_URL or ABAP_URL."""
    return setting(name, _SERVICE_URLS[name])


def profile() -> str:
    """The deployment profile the stack runs under (APP_PROFILE, default baseline)."""
    return setting("APP_PROFILE", "baseline")


def app_dir() -> Path:
    """The legacy-goat checkout that holds the answer key (APP_DIR, default the sibling checkout)."""
    value = os.environ.get("APP_DIR")
    return Path(value) if value else ROOT.parent / "legacy-goat"


def manifest_path() -> Path:
    return app_dir() / "benchmark" / "manifest.yaml"


def profile_setting(key: str, profile_name: str | None = None) -> str:
    """A setting's value in profiles/<profile>.env: the last `KEY=` line wins. Empty when absent."""
    path = ROOT / "profiles" / f"{profile_name or profile()}.env"
    value = ""
    for line in path.read_text().splitlines():
        if line.startswith(f"{key}="):
            value = line[len(key) + 1:]
    return value
