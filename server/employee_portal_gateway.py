#!/usr/bin/env python3
"""WesiOS employee portal gateway.

Validates PocketBase employee tokens, creates a short-lived signed HttpOnly
session, and serves release files only to authenticated employees.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import time
from pathlib import Path
from typing import Any

import requests
from flask import Flask, Response, jsonify, make_response, request, send_file

PB_URL = os.environ.get("PB_URL", "http://127.0.0.1:8090").rstrip("/")
RELEASE_DIR = Path(os.environ.get("RELEASE_DIR", "/srv/wesios-releases"))
SESSION_SECRET = os.environ["PORTAL_SESSION_SECRET"].encode("utf-8")
SESSION_TTL = int(os.environ.get("PORTAL_SESSION_TTL", "28800"))
COOKIE_NAME = "wesios_portal"

app = Flask(__name__)

FILES = {
    "windows": ("wesios-windows-x64.zip", "application/zip"),
    "android": ("wesios-android.apk", "application/vnd.android.package-archive"),
}


def b64url(data: bytes) -> str:
    import base64
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def b64url_decode(value: str) -> bytes:
    import base64
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def sign(payload: dict[str, Any]) -> str:
    raw = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    body = b64url(raw)
    signature = b64url(hmac.new(SESSION_SECRET, body.encode("ascii"), hashlib.sha256).digest())
    return f"{body}.{signature}"


def verify(cookie: str | None) -> dict[str, Any] | None:
    if not cookie or "." not in cookie:
        return None
    body, signature = cookie.rsplit(".", 1)
    expected = b64url(hmac.new(SESSION_SECRET, body.encode("ascii"), hashlib.sha256).digest())
    if not hmac.compare_digest(signature, expected):
        return None
    try:
        payload = json.loads(b64url_decode(body))
    except (ValueError, json.JSONDecodeError):
        return None
    if int(payload.get("exp", 0)) < int(time.time()):
        return None
    if not payload.get("uid") or not payload.get("downloads"):
        return None
    return payload


def bearer_token() -> str | None:
    value = request.headers.get("Authorization", "")
    if not value.lower().startswith("bearer "):
        return None
    return value[7:].strip()


def validate_employee(token: str) -> dict[str, Any]:
    response = requests.post(
        f"{PB_URL}/api/collections/users/auth-refresh",
        headers={"Authorization": token},
        timeout=10,
    )
    if response.status_code != 200:
        raise PermissionError("PocketBase rejected the user session")
    data = response.json()
    record = data.get("record") or {}
    # Registration is disabled; only administrator-created users can reach here.
    # portalAccess is opt-out compatible while the field is being rolled out.
    if record.get("verified") is False or record.get("portalAccess") is False:
        raise PermissionError("Employee profile has no portal access")
    return record


@app.after_request
def security_headers(response: Response) -> Response:
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "DENY"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Cache-Control"] = "no-store"
    return response


@app.get("/health")
def health() -> Response:
    return jsonify({"ok": True})


@app.post("/session")
def create_session() -> Response:
    token = bearer_token()
    if not token:
        return jsonify({"error": "missing bearer token"}), 401
    try:
        record = validate_employee(token)
    except (PermissionError, requests.RequestException, ValueError):
        return jsonify({"error": "employee access denied"}), 403

    now = int(time.time())
    payload = {
        "uid": record.get("id"),
        "email": record.get("email"),
        "role": record.get("role", "employee"),
        "downloads": True,
        "iat": now,
        "exp": now + SESSION_TTL,
    }
    response = make_response(jsonify({"ok": True, "expires": payload["exp"]}))
    response.set_cookie(
        COOKIE_NAME,
        sign(payload),
        max_age=SESSION_TTL,
        secure=True,
        httponly=True,
        samesite="Strict",
        path="/portal/",
    )
    return response


@app.delete("/session")
def delete_session() -> Response:
    response = make_response(jsonify({"ok": True}))
    response.delete_cookie(COOKIE_NAME, path="/portal/", secure=True, httponly=True, samesite="Strict")
    return response


def require_session() -> dict[str, Any] | None:
    return verify(request.cookies.get(COOKIE_NAME))


@app.get("/manifest")
def manifest() -> Response:
    if require_session() is None:
        return jsonify({"error": "authentication required"}), 401
    path = RELEASE_DIR / "app-manifest.json"
    if not path.is_file():
        return jsonify({"error": "release manifest is not published"}), 503
    return send_file(path, mimetype="application/json", conditional=True)


@app.get("/download/<platform>")
def download(platform: str) -> Response:
    session = require_session()
    if session is None:
        return jsonify({"error": "authentication required"}), 401
    item = FILES.get(platform)
    if item is None:
        return jsonify({"error": "unsupported platform"}), 404
    filename, mimetype = item
    path = RELEASE_DIR / filename
    if not path.is_file():
        return jsonify({"error": "release file is not published"}), 503
    app.logger.info("download user=%s platform=%s file=%s", session.get("uid"), platform, filename)
    return send_file(path, mimetype=mimetype, as_attachment=True, download_name=filename, conditional=True)


if __name__ == "__main__":
    app.run(host="127.0.0.1", port=8091)
