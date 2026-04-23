from __future__ import annotations

import hmac
import json
import re
import secrets
import threading
import unicodedata
from datetime import datetime
from hashlib import sha256
from pathlib import Path
from typing import Any

from werkzeug.security import check_password_hash, generate_password_hash


USERNAME_PATTERN = re.compile(r"^[A-Za-z0-9_.@-]{3,64}$")
MIN_PASSWORD_LENGTH = 8
MAX_PASSWORD_LENGTH = 256


class UserStoreError(ValueError):
    pass


class DuplicateUserError(UserStoreError):
    pass


class LastUserError(UserStoreError):
    pass


class MissingUserError(UserStoreError):
    pass


class UserStore:
    def __init__(self, path: Path, username_pepper: str):
        self.path = path
        self.username_pepper = username_pepper.encode("utf-8")
        self._lock = threading.RLock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write({"version": 1, "users": {}})

    def bootstrap(
        self,
        *,
        env_username: str | None = None,
        env_password: str | None = None,
        env_password_hash: str | None = None,
        legacy_credentials_path: Path | None = None,
        initial_password_path: Path | None = None,
    ) -> None:
        with self._lock:
            if self.count_users() == 0 and legacy_credentials_path and legacy_credentials_path.exists():
                self._migrate_legacy_credentials(legacy_credentials_path)

            if env_username and (env_password or env_password_hash):
                password_hash = env_password_hash or generate_password_hash(env_password or "")
                self._upsert_hash(env_username, password_hash)

            if self.count_users() == 0:
                password = secrets.token_urlsafe(18)
                self.create_user("admin", password)
                if initial_password_path:
                    initial_password_path.write_text(
                        "username: admin\n"
                        f"password: {password}\n"
                        "Set LUNCH_ADMIN_USERNAME and LUNCH_ADMIN_PASSWORD or "
                        "LUNCH_ADMIN_PASSWORD_HASH for production.\n",
                        encoding="utf-8",
                    )
            elif initial_password_path and initial_password_path.exists():
                initial_password_path.unlink(missing_ok=True)

    def authenticate(self, username: str, password: str) -> dict[str, Any] | None:
        if len(username) > 256 or len(password) > MAX_PASSWORD_LENGTH:
            return None
        username_hash = self.hash_username(username)
        with self._lock:
            user = self._read()["users"].get(username_hash)
        if not user or not check_password_hash(user["passwordHash"], password):
            return None
        return self._public_user(username_hash, user)

    def list_users(self) -> list[dict[str, Any]]:
        with self._lock:
            users = self._read()["users"]
        return [
            self._public_user(user_id, user)
            for user_id, user in sorted(users.items(), key=lambda item: item[1].get("createdAt", ""))
        ]

    def has_user(self, user_id: str | None) -> bool:
        if not user_id:
            return False
        with self._lock:
            return user_id in self._read()["users"]

    def count_users(self) -> int:
        with self._lock:
            return len(self._read()["users"])

    def create_user(self, username: str, password: str) -> dict[str, Any]:
        normalized = normalize_username(username)
        validate_username(normalized)
        validate_password(password)
        user_id = self.hash_username(normalized)
        now = utc_now()
        with self._lock:
            data = self._read()
            if user_id in data["users"]:
                raise DuplicateUserError("duplicate_user")
            data["users"][user_id] = {
                "usernameHash": user_id,
                "passwordHash": generate_password_hash(password),
                "createdAt": now,
                "updatedAt": now,
            }
            self._write(data)
            return self._public_user(user_id, data["users"][user_id])

    def change_password(self, user_id: str, password: str) -> dict[str, Any]:
        validate_password(password)
        with self._lock:
            data = self._read()
            user = data["users"].get(user_id)
            if user is None:
                raise MissingUserError("missing_user")
            user["passwordHash"] = generate_password_hash(password)
            user["updatedAt"] = utc_now()
            self._write(data)
            return self._public_user(user_id, user)

    def delete_user(self, user_id: str) -> None:
        with self._lock:
            data = self._read()
            if user_id not in data["users"]:
                raise MissingUserError("missing_user")
            if len(data["users"]) <= 1:
                raise LastUserError("last_user")
            del data["users"][user_id]
            self._write(data)

    def hash_username(self, username: str) -> str:
        normalized = normalize_username(username)
        return hmac.new(self.username_pepper, normalized.encode("utf-8"), sha256).hexdigest()

    def _upsert_hash(self, username: str, password_hash: str) -> None:
        normalized = normalize_username(username)
        validate_username(normalized)
        user_id = self.hash_username(normalized)
        now = utc_now()
        data = self._read()
        existing = data["users"].get(user_id)
        data["users"][user_id] = {
            "usernameHash": user_id,
            "passwordHash": password_hash,
            "createdAt": (existing or {}).get("createdAt") or now,
            "updatedAt": now,
        }
        self._write(data)

    def _migrate_legacy_credentials(self, legacy_path: Path) -> None:
        try:
            legacy = json.loads(legacy_path.read_text(encoding="utf-8"))
            username = legacy.get("username")
            password_hash = legacy.get("password_hash") or legacy.get("passwordHash")
            if username and password_hash:
                self._upsert_hash(username, password_hash)
                legacy_path.unlink(missing_ok=True)
        except Exception:
            return

    def _public_user(self, user_id: str, user: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": user_id,
            "fingerprint": user_id[:12],
            "createdAt": user.get("createdAt", ""),
            "updatedAt": user.get("updatedAt", ""),
        }

    def _read(self) -> dict[str, Any]:
        with self.path.open("r", encoding="utf-8") as fp:
            data = json.load(fp)
        data.setdefault("version", 1)
        data.setdefault("users", {})
        return data

    def _write(self, data: dict[str, Any]) -> None:
        temp_path = self.path.with_suffix(".tmp")
        with temp_path.open("w", encoding="utf-8") as fp:
            json.dump(data, fp, ensure_ascii=False, indent=2)
            fp.write("\n")
        temp_path.replace(self.path)


def normalize_username(username: str) -> str:
    return unicodedata.normalize("NFKC", username).strip().casefold()


def validate_username(username: str) -> None:
    if not USERNAME_PATTERN.fullmatch(username):
        raise UserStoreError("invalid_username")


def validate_password(password: str) -> None:
    if len(password) < MIN_PASSWORD_LENGTH or len(password) > MAX_PASSWORD_LENGTH:
        raise UserStoreError("weak_password")


def utc_now() -> str:
    return datetime.utcnow().isoformat(timespec="seconds") + "Z"
