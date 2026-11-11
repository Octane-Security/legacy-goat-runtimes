"""Shared setup for the suites: stack deployment, the health wait, and the profile."""

from __future__ import annotations

import pytest

from harness import env, stack


def pytest_addoption(parser: pytest.Parser) -> None:
    group = parser.getgroup("legacy-goat")
    group.addoption(
        "--deploy",
        action="store_true",
        help="(re)create the stack under APP_PROFILE before the tests, from APP_SRC when it is set, "
             "with the compose command in COMPOSE_CMD (default: podman compose)",
    )
    group.addoption(
        "--stack-timeout",
        type=float,
        default=0.0,
        metavar="SECONDS",
        help="wait up to SECONDS for the gateway's /healthz before the tests (default: no wait)",
    )


@pytest.fixture(scope="session", autouse=True)
def stack_ready(pytestconfig: pytest.Config) -> None:
    """Deploys the stack when asked, then waits for the gateway when asked. Stops the run if the
    gateway never answers."""
    deploy = pytestconfig.getoption("--deploy")
    timeout = pytestconfig.getoption("--stack-timeout")
    reporter = pytestconfig.pluginmanager.get_plugin("terminalreporter")
    say = reporter.write_line if reporter else print
    profile = env.profile()
    gateway = env.url("GATEWAY_URL")
    if deploy:
        source = env.setting("APP_SRC", "")
        say(f"(re)creating the stack under {profile}{f' from {source}' if source else ''}")
        stack.deploy(profile)
    if timeout > 0:
        say(f"waiting for the gateway at {gateway}")
        if not stack.wait_for_gateway(gateway, timeout):
            pytest.exit(f"gateway not healthy at {gateway}", returncode=1)


@pytest.fixture(scope="session")
def profile() -> str:
    return env.profile()
