"""HTTP for the suites and triggers, with the behavior the checks rely on.

- Redirects are never followed: a check sees the reply the service sent.
- JSON bodies go out compact (no spaces), and raw bodies go out byte for byte. Some module services
  read their request by hand, so the bytes on the wire matter.
- Only a `Client` keeps cookies. The module-level helpers send none, so a console session never
  leaks into a call to another service.
- Every request has a timeout, so a service that hangs fails its check instead of stalling the run.
"""

from __future__ import annotations

import json
from typing import Any

import requests

TIMEOUT = 60  # seconds

JSON = {"content-type": "application/json"}


def body_bytes(body: Any) -> bytes:
    """A request body: bytes and str as given, anything else as compact JSON."""
    if isinstance(body, bytes):
        return body
    if isinstance(body, str):
        return body.encode("utf-8")
    return json.dumps(body, separators=(",", ":")).encode("utf-8")


def text(value: Any) -> str:
    """A JSON value as text, None as the empty string: how the shell harness compared fields."""
    return "" if value is None else str(value)


def request(method: str, url: str, **kwargs: Any) -> requests.Response:
    kwargs.setdefault("allow_redirects", False)
    kwargs.setdefault("timeout", TIMEOUT)
    return requests.request(method, url, **kwargs)


def get(url: str, **kwargs: Any) -> requests.Response:
    return request("GET", url, **kwargs)


def post(url: str, **kwargs: Any) -> requests.Response:
    return request("POST", url, **kwargs)


def post_json(url: str, body: Any, headers: dict[str, str] | None = None) -> requests.Response:
    """POST a JSON body (compact, or bytes/str sent as given) with content-type application/json."""
    return post(url, data=body_bytes(body), headers={**JSON, **(headers or {})})


def set_cookie_headers(response: requests.Response) -> list[str]:
    """Every Set-Cookie header of a reply, one entry per header."""
    return response.raw.headers.getlist("Set-Cookie")


class Client(requests.Session):
    """A cookie-keeping client, like curl with a cookie jar. It follows no redirects either."""

    def request(self, method: str, url: str, **kwargs: Any) -> requests.Response:  # type: ignore[override]
        kwargs.setdefault("allow_redirects", False)
        kwargs.setdefault("timeout", TIMEOUT)
        return super().request(method, url, **kwargs)


def console_sign_on(console_url: str, staff_id: str, password: str) -> tuple[Client, requests.Response]:
    """Sign on to the console with its form. Returns the client holding the session, and the reply."""
    client = Client()
    reply = client.post(f"{console_url}/login", data={"staff_id": staff_id, "password": password})
    return client, reply
