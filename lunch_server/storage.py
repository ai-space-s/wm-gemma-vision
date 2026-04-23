from __future__ import annotations

import json
import threading
from copy import deepcopy
from datetime import date, datetime
from pathlib import Path
from typing import Any


MEAL_KEYS = ("breakfast", "lunch", "dinner")
MEAL_LABELS = {"breakfast": "조식", "lunch": "중식", "dinner": "석식"}


class LunchMenuStore:
    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.Lock()
        self.path.parent.mkdir(parents=True, exist_ok=True)
        if not self.path.exists():
            self._write({"menus": {}})

    def get_meals_response(self, target_date: date, meal: str = "all") -> dict[str, Any]:
        key = target_date.isoformat()
        if meal != "all" and meal not in MEAL_KEYS:
            return {
                "status": "error",
                "code": "invalid_meal",
                "date": key,
                "message": "meal must be one of all, breakfast, lunch, dinner.",
            }

        record = self._normalized_record_for_key(key)
        if record is None:
            if target_date.weekday() >= 5:
                return {
                    "status": "no_meal",
                    "code": "weekend",
                    "date": key,
                    "message": "주말",
                }
            return {
                "status": "no_menu_info",
                "code": "missing_menu",
                "date": key,
                "message": "미등록",
            }

        if meal != "all":
            return self._single_meal_response(key, record, meal)

        meals = record["meals"]
        available = {
            meal_key: meal_record
            for meal_key, meal_record in meals.items()
            if _meal_has_content(meal_record)
        }
        if available:
            return {
                "status": "ok",
                "source": "lunch_server",
                "date": key,
                "meals": meals,
                "record": record,
            }

        if all(not meals[meal_key].get("hasMeal", True) for meal_key in MEAL_KEYS):
            return {
                "status": "no_meal",
                "code": "closed",
                "date": key,
                "message": "미제공",
                "record": record,
            }

        return {
            "status": "no_menu_info",
            "code": "empty_menu",
            "date": key,
            "message": "미등록",
            "record": record,
        }

    def list_month(self, year: int, month: int) -> dict[str, Any]:
        prefix = f"{year:04d}-{month:02d}-"
        menus = self._read()["menus"]
        return {
            key: normalize_record(key, value)
            for key, value in menus.items()
            if key.startswith(prefix)
        }

    def preview_bulk_upsert(self, records: list[dict[str, Any]]) -> dict[str, int]:
        data = self._read()
        existing = data["menus"]
        dates = {item["date"] for item in records if item.get("date")}
        overwrite_count = sum(1 for key in dates if key in existing)
        return {
            "totalDates": len(dates),
            "overwriteDates": overwrite_count,
            "failedDates": 0,
        }

    def upsert(self, target_date: date, payload: dict[str, Any]) -> dict[str, Any]:
        record = normalize_record(target_date.isoformat(), payload)
        with self._lock:
            data = self._read()
            data["menus"][target_date.isoformat()] = record
            self._write(data)
        return record

    def bulk_upsert(self, records: list[dict[str, Any]]) -> list[dict[str, Any]]:
        normalized = [normalize_record(item["date"], item) for item in records if item.get("date")]
        with self._lock:
            data = self._read()
            for record in normalized:
                data["menus"][record["date"]] = record
            self._write(data)
        return normalized

    def delete(self, target_date: date) -> bool:
        key = target_date.isoformat()
        with self._lock:
            data = self._read()
            deleted = data["menus"].pop(key, None) is not None
            self._write(data)
        return deleted

    def _single_meal_response(self, key: str, record: dict[str, Any], meal: str) -> dict[str, Any]:
        meal_record = record["meals"][meal]
        if _meal_has_content(meal_record):
            return {
                "status": "ok",
                "source": "lunch_server",
                "date": key,
                "meal": meal,
                "mealLabel": MEAL_LABELS[meal],
                "menu": meal_record["menu"],
                "record": record,
            }

        if not meal_record.get("hasMeal", True):
            return {
                "status": "no_meal",
                "code": meal_record.get("reasonCode") or "closed",
                "date": key,
                "meal": meal,
                "mealLabel": MEAL_LABELS[meal],
                "reason": meal_record.get("reason", ""),
                "message": meal_record.get("reason") or "미제공",
                "record": record,
            }

        return {
            "status": "no_menu_info",
            "code": "empty_menu",
            "date": key,
            "meal": meal,
            "mealLabel": MEAL_LABELS[meal],
            "message": "미등록",
            "record": record,
        }

    def _normalized_record_for_key(self, key: str) -> dict[str, Any] | None:
        record = self._read()["menus"].get(key)
        if record is None:
            return None
        return normalize_record(key, record)

    def _read(self) -> dict[str, Any]:
        with self.path.open("r", encoding="utf-8") as fp:
            return json.load(fp)

    def _write(self, data: dict[str, Any]) -> None:
        temp_path = self.path.with_suffix(".tmp")
        with temp_path.open("w", encoding="utf-8") as fp:
            json.dump(data, fp, ensure_ascii=False, indent=2)
            fp.write("\n")
        temp_path.replace(self.path)


def normalize_record(key: str, payload: dict[str, Any]) -> dict[str, Any]:
    if "meals" in payload:
        meals_payload = payload.get("meals") or {}
        meals = {
            meal_key: normalize_meal(meals_payload.get(meal_key) or {})
            for meal_key in MEAL_KEYS
        }
    else:
        meals = {meal_key: normalize_meal({}) for meal_key in MEAL_KEYS}
        meals["lunch"] = normalize_meal(
            {
                "hasMeal": payload.get("hasLunch", payload.get("has_lunch", True)),
                "reason": payload.get("reason"),
                "reasonCode": payload.get("reasonCode") or payload.get("reason_code"),
                "menu": payload.get("menu") or {},
            }
        )

    return {
        "date": key,
        "meals": meals,
        "source": _clean_text(payload.get("source")) or "manual",
        "updatedAt": _clean_text(payload.get("updatedAt"))
        or datetime.utcnow().isoformat(timespec="seconds") + "Z",
    }


def normalize_meal(payload: dict[str, Any]) -> dict[str, Any]:
    menu = payload.get("menu") or {}
    return {
        "hasMeal": bool(payload.get("hasMeal", payload.get("has_meal", True))),
        "reason": _clean_text(payload.get("reason")),
        "reasonCode": _clean_text(payload.get("reasonCode") or payload.get("reason_code")),
        "menu": normalize_menu(menu),
    }


def normalize_menu(payload: dict[str, Any]) -> dict[str, Any]:
    items = _clean_list(payload.get("items"))
    side_dishes = _clean_list(payload.get("sideDishes") or payload.get("side_dishes"))
    menu = {
        "main": _clean_text(payload.get("main")),
        "soup": _clean_text(payload.get("soup")),
        "sideDishes": side_dishes,
        "dessert": _clean_text(payload.get("dessert")),
        "drink": _clean_text(payload.get("drink")),
        "items": items,
        "notes": _clean_text(payload.get("notes")),
        "rawText": _clean_text(payload.get("rawText") or payload.get("raw_text")),
    }
    if not menu["items"]:
        menu["items"] = [
            value
            for value in [
                menu["main"],
                menu["soup"],
                *menu["sideDishes"],
                menu["dessert"],
                menu["drink"],
            ]
            if value
        ]
    return menu


def _meal_has_content(meal_record: dict[str, Any]) -> bool:
    return meal_record.get("hasMeal", True) and _menu_has_content(meal_record.get("menu") or {})


def _menu_has_content(menu: dict[str, Any]) -> bool:
    return any(
        [
            menu.get("main"),
            menu.get("soup"),
            menu.get("sideDishes"),
            menu.get("dessert"),
            menu.get("drink"),
            menu.get("items"),
            menu.get("rawText"),
        ]
    )


def _clean_text(value: Any) -> str:
    if value is None:
        return ""
    return str(value).strip()


def _clean_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, str):
        parts = value.replace("\r", "\n").split("\n")
    else:
        parts = list(value)
    return [_clean_text(item) for item in parts if _clean_text(item)]
