"""Bring the stack up under a profile, and wait for the gateway to answer.

`deploy` runs the compose command in COMPOSE_CMD (the Makefile passes the one it built, with the
profile's env-file), or `podman compose` with this repo's compose file and the profile's env-file.
APP_SRC, when set in the environment, picks the app tree to mount: compose reads it from the
command's environment.
"""

from __future__ import annotations

import os
import shlex
import subprocess
import time

import requests

from harness import env


def compose_command(profile: str) -> list[str]:
    configured = os.environ.get("COMPOSE_CMD")
    if configured:
        return shlex.split(configured)
    return [
        "podman", "compose",
        "-f", str(env.ROOT / "compose" / "compose.yaml"),
        "--env-file", str(env.ROOT / "compose" / ".env"),
        "--env-file", str(env.ROOT / "profiles" / f"{profile}.env"),
    ]


def deploy(profile: str) -> None:
    """(Re)create every service. A failed recreate falls back to a plain `up`; the health wait that
    follows decides whether the stack is usable."""
    command = compose_command(profile)
    quiet = {"stdout": subprocess.DEVNULL, "stderr": subprocess.DEVNULL}
    if subprocess.run([*command, "up", "-d", "--force-recreate"], **quiet).returncode != 0:
        subprocess.run([*command, "up", "-d"], **quiet)


def gateway_healthy(gateway_url: str) -> bool:
    try:
        return requests.get(f"{gateway_url}/healthz", timeout=10).text.rstrip("\n") == "ok"
    except requests.RequestException:
        return False


def wait_for_gateway(gateway_url: str, timeout: float, interval: float = 3.0) -> bool:
    """Poll the gateway's /healthz until it answers `ok` or `timeout` seconds pass."""
    deadline = time.monotonic() + timeout
    while True:
        if gateway_healthy(gateway_url):
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(interval)
