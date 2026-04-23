from __future__ import annotations

import hmac
import os
import secrets
import threading
import time
from functools import wraps
from pathlib import Path
from typing import Callable

from flask import jsonify, redirect, request, session, url_for

try:
    from .user_store import UserStore
except ImportError:
    from user_store import UserStore


ADMIN_USERNAME_ENV = "LUNCH_ADMIN_USERNAME"
ADMIN_PASSWORD_ENV = "LUNCH_ADMIN_PASSWORD"
ADMIN_PASSWORD_HASH_ENV = "LUNCH_ADMIN_PASSWORD_HASH"
SECRET_KEY_ENV = "LUNCH_SERVER_SECRET_KEY"
LOGIN_ATTEMPTS_LIMIT_ENV = "LUNCH_LOGIN_ATTEMPTS_LIMIT"
LOGIN_LOCKOUT_SECONDS_ENV = "LUNCH_LOGIN_LOCKOUT_SECONDS"


def configure_security(app, data_dir: Path) -> None:
    global _user_store
    app.secret_key = os.environ.get(SECRET_KEY_ENV) or _load_or_create_secret(data_dir, "secret_key")
    app.config.update(
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE="Lax",
        SESSION_COOKIE_SECURE=_secure_cookie_enabled(),
        PERMANENT_SESSION_LIFETIME=60 * 60 * 8,
    )
    username_pepper = _load_or_create_secret(data_dir, "username_pepper")
    _user_store = UserStore(data_dir / "users.json", username_pepper)
    _user_store.bootstrap(
        env_username=os.environ.get(ADMIN_USERNAME_ENV),
        env_password=os.environ.get(ADMIN_PASSWORD_ENV),
        env_password_hash=os.environ.get(ADMIN_PASSWORD_HASH_ENV),
        legacy_credentials_path=data_dir / "admin_credentials.json",
        initial_password_path=data_dir / "admin_initial_password.txt",
    )


def login_required(view: Callable):
    @wraps(view)
    def wrapped(*args, **kwargs):
        if session.get("admin_authenticated") is True and _user_store.has_user(session.get("user_id")):
            return view(*args, **kwargs)
        session.clear()
        if request.path.startswith("/api/"):
            return jsonify({"status": "error", "code": "auth_required"}), 401
        return redirect(url_for("login", next=request.full_path.rstrip("?")))

    return wrapped


def csrf_required(view: Callable):
    @wraps(view)
    def wrapped(*args, **kwargs):
        expected = session.get("csrf_token")
        supplied = request.headers.get("X-CSRF-Token") or request.form.get("csrf_token")
        if not expected or not supplied or not hmac.compare_digest(expected, supplied):
            return jsonify({"status": "error", "code": "csrf_failed"}), 403
        return view(*args, **kwargs)

    return wrapped


def verify_login(username: str, password: str) -> dict | None:
    ip_address = _client_ip()
    if _is_login_locked(ip_address):
        return None

    user = _user_store.authenticate(username, password)
    if user:
        _clear_login_failures(ip_address)
        return user

    _record_login_failure(ip_address)
    return None


def start_admin_session(user_id: str) -> str:
    session.clear()
    session.permanent = True
    session["admin_authenticated"] = True
    session["user_id"] = user_id
    session["csrf_token"] = secrets.token_urlsafe(32)
    return session["csrf_token"]


def clear_admin_session() -> None:
    session.clear()


def csrf_token() -> str:
    token = session.get("csrf_token")
    if not token:
        token = secrets.token_urlsafe(32)
        session["csrf_token"] = token
    return token


def user_store() -> UserStore:
    return _user_store


def current_user_id() -> str:
    return str(session.get("user_id") or "")


def _load_or_create_secret(data_dir: Path, filename: str) -> str:
    path = data_dir / filename
    if path.exists():
        return path.read_text(encoding="utf-8").strip()
    secret = secrets.token_urlsafe(48)
    path.write_text(secret, encoding="utf-8")
    return secret


def _secure_cookie_enabled() -> bool:
    value = os.environ.get("LUNCH_COOKIE_SECURE", "auto").lower()
    if value in {"1", "true", "yes"}:
        return True
    if value in {"0", "false", "no"}:
        return False
    return False


def _client_ip() -> str:
    return request.remote_addr or "0.0.0.0"


def _is_login_locked(ip_address: str) -> bool:
    now = time.time()
    limit = int(os.environ.get(LOGIN_ATTEMPTS_LIMIT_ENV, "5"))
    lockout = int(os.environ.get(LOGIN_LOCKOUT_SECONDS_ENV, "900"))
    with _login_lock:
        record = _login_attempts.get(ip_address)
        if not record:
            return False
        if now - record["last_attempt"] >= lockout:
            _login_attempts.pop(ip_address, None)
            return False
        return record["failures"] >= limit


def _record_login_failure(ip_address: str) -> None:
    now = time.time()
    with _login_lock:
        record = _login_attempts.setdefault(ip_address, {"failures": 0, "last_attempt": 0.0})
        record["failures"] += 1
        record["last_attempt"] = now


def _clear_login_failures(ip_address: str) -> None:
    with _login_lock:
        _login_attempts.pop(ip_address, None)


_user_store: UserStore
_login_lock = threading.Lock()
_login_attempts: dict[str, dict[str, float | int]] = {}
