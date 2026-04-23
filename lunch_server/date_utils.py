from __future__ import annotations

from datetime import date, datetime


def parse_iso_date(value: str | None) -> date:
    text = (value or "").strip()
    if not text:
        raise ValueError("date query parameter is required in YYYY-MM-DD format.")

    try:
        return datetime.strptime(text, "%Y-%m-%d").date()
    except ValueError as exc:
        raise ValueError(f"date must be in YYYY-MM-DD format: {value}") from exc
