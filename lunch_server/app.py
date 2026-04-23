from __future__ import annotations

import json
import hmac
import os
from pathlib import Path
from tempfile import NamedTemporaryFile
from uuid import uuid4

from flask import Flask, jsonify, redirect, render_template, request, url_for
from werkzeug.utils import secure_filename

try:
    from auth import (
        clear_admin_session,
        configure_security,
        csrf_required,
        csrf_token,
        current_user_id,
        login_required,
        start_admin_session,
        user_store,
        verify_login,
    )
    from date_utils import parse_iso_date
    from storage import LunchMenuStore
    from user_store import UserStoreError
    from xlsx_importer import XlsxExtractionError, parse_xlsx_meal_menus
except ImportError:
    from auth import (
        clear_admin_session,
        configure_security,
        csrf_required,
        csrf_token,
        current_user_id,
        login_required,
        start_admin_session,
        user_store,
        verify_login,
    )
    from date_utils import parse_iso_date
    from storage import LunchMenuStore
    from user_store import UserStoreError
    from xlsx_importer import XlsxExtractionError, parse_xlsx_meal_menus


BASE_DIR = Path(__file__).resolve().parent
DATA_DIR = BASE_DIR / "data"
UPLOAD_DIR = BASE_DIR / "uploads"
DEFAULT_PORT = 7860


def create_app() -> Flask:
    app = Flask(__name__)
    app.config["MAX_CONTENT_LENGTH"] = 32 * 1024 * 1024
    data_dir = Path(os.environ.get("LUNCH_SERVER_DATA_DIR") or DATA_DIR).resolve()
    upload_dir = Path(os.environ.get("LUNCH_SERVER_UPLOAD_DIR") or UPLOAD_DIR).resolve()
    import_dir = data_dir / "imports"

    upload_dir.mkdir(parents=True, exist_ok=True)
    import_dir.mkdir(parents=True, exist_ok=True)
    configure_security(app, data_dir)

    store = LunchMenuStore(data_dir / "menus.json")

    @app.errorhandler(404)
    def not_found(error):
        if request.path.startswith("/api/"):
            return jsonify({"status": "error", "code": "not_found"}), 404
        return error

    @app.errorhandler(405)
    def method_not_allowed(error):
        if request.path.startswith("/api/"):
            return jsonify({"status": "error", "code": "method_not_allowed"}), 405
        return error

    @app.after_request
    def set_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Content-Security-Policy"] = (
            "default-src 'self'; "
            "script-src 'self'; "
            "style-src 'self'; "
            "img-src 'self' data:; "
            "connect-src 'self'; "
            "object-src 'none'; "
            "base-uri 'self'; "
            "frame-ancestors 'none'"
        )
        if request.is_secure:
            response.headers["Strict-Transport-Security"] = (
                "max-age=31536000; includeSubDomains; preload"
            )
        return response

    @app.get("/")
    def index():
        return render_template("index.html")

    @app.get("/admin")
    @login_required
    def admin():
        return render_template("admin.html", csrf_token=csrf_token())

    @app.get("/admin/users")
    @login_required
    def users_page():
        return _render_users_page()

    @app.post("/admin/users")
    @login_required
    @csrf_required
    def create_user():
        try:
            user_store().create_user(
                request.form.get("username", ""),
                request.form.get("password", ""),
            )
            return redirect(url_for("users_page", status="created"))
        except UserStoreError as exc:
            return _render_users_page(error=str(exc)), 400

    @app.post("/admin/users/<user_id>/password")
    @login_required
    @csrf_required
    def change_user_password(user_id: str):
        try:
            user_store().change_password(user_id, request.form.get("password", ""))
            return redirect(url_for("users_page", status="updated"))
        except UserStoreError as exc:
            return _render_users_page(error=str(exc)), 400

    @app.post("/admin/users/<user_id>/delete")
    @login_required
    @csrf_required
    def delete_user(user_id: str):
        deleting_self = hmac.compare_digest(current_user_id(), user_id)
        try:
            user_store().delete_user(user_id)
            if deleting_self:
                clear_admin_session()
                return redirect(url_for("login"))
            return redirect(url_for("users_page", status="deleted"))
        except UserStoreError as exc:
            return _render_users_page(error=str(exc)), 400

    @app.route("/login", methods=["GET", "POST"])
    def login():
        next_url = _safe_next_url(request.values.get("next") or url_for("admin"))
        error = False
        if request.method == "POST":
            expected = csrf_token()
            supplied = request.form.get("csrf_token") or ""
            user = None
            if hmac.compare_digest(supplied, expected):
                user = verify_login(
                    request.form.get("username", ""),
                    request.form.get("password", ""),
                )
            if user:
                start_admin_session(user["id"])
                return redirect(next_url)
            error = True
        return render_template("login.html", csrf_token=csrf_token(), next_url=next_url, error=error)

    @app.post("/logout")
    @login_required
    @csrf_required
    def logout():
        clear_admin_session()
        return redirect(url_for("index"))

    @app.get("/api/health")
    def health():
        return jsonify({"status": "ok"})

    @app.get("/api/meals")
    def get_meals():
        try:
            target_date = parse_iso_date(request.args.get("date"))
        except ValueError as exc:
            return jsonify({"status": "error", "code": "invalid_date", "message": str(exc)}), 400

        meal = (request.args.get("meal") or "all").strip().lower()
        response = store.get_meals_response(target_date, meal)
        status = 400 if response.get("status") == "error" else 200
        return jsonify(response), status

    @app.get("/api/menus")
    def get_month_menus():
        year = request.args.get("year", type=int)
        month = request.args.get("month", type=int)
        if not year or not month or month < 1 or month > 12:
            return jsonify({"status": "error", "code": "invalid_month"}), 400
        return jsonify({"status": "ok", "menus": store.list_month(year, month)})

    @app.put("/api/admin/menus/<date>")
    @login_required
    @csrf_required
    def upsert_menu(date: str):
        try:
            target_date = parse_iso_date(date)
        except ValueError as exc:
            return jsonify({"status": "error", "code": "invalid_date", "message": str(exc)}), 400

        payload = request.get_json(silent=True) or {}
        record = store.upsert(target_date, payload)
        return jsonify({"status": "ok", "record": record})

    @app.delete("/api/admin/menus/<date>")
    @login_required
    @csrf_required
    def delete_menu(date: str):
        try:
            target_date = parse_iso_date(date)
        except ValueError as exc:
            return jsonify({"status": "error", "code": "invalid_date", "message": str(exc)}), 400

        deleted = store.delete(target_date)
        return jsonify({"status": "ok", "deleted": deleted})

    @app.post("/api/admin/preview-xlsx")
    @login_required
    @csrf_required
    def preview_xlsx():
        uploaded = request.files.get("file")
        if uploaded is None or not uploaded.filename:
            return jsonify({"status": "error", "code": "missing_file"}), 400

        try:
            parsed_records = _parse_uploaded_xlsx(uploaded, upload_dir)
            import_id = uuid4().hex
            _import_path(import_id, import_dir).write_text(
                json.dumps({"records": parsed_records}, ensure_ascii=False),
                encoding="utf-8",
            )
            preview = store.preview_bulk_upsert(parsed_records)
            return jsonify({"status": "ok", "importId": import_id, **preview})
        except XlsxExtractionError as exc:
            return (
                jsonify(
                    {
                        "status": "error",
                        "code": "xlsx_extraction_failed",
                        "message": str(exc),
                    }
                ),
                422,
            )

    @app.post("/api/admin/commit-import")
    @login_required
    @csrf_required
    def commit_import():
        payload = request.get_json(silent=True) or {}
        import_id = str(payload.get("importId") or "")
        path = _import_path(import_id, import_dir)
        if not import_id or not path.exists():
            return jsonify({"status": "error", "code": "missing_import"}), 400

        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
            records = parsed.get("records") or []
            imported_records = store.bulk_upsert(records)
            path.unlink(missing_ok=True)
            return jsonify(
                {
                    "status": "ok",
                    "count": len(imported_records),
                    "failedDates": 0,
                }
            )
        except Exception as exc:
            return jsonify({"status": "error", "code": "import_failed", "message": str(exc)}), 500

    return app


def _parse_uploaded_xlsx(uploaded, upload_dir: Path) -> list[dict]:
    filename = secure_filename(uploaded.filename) or "menu.xlsx"
    suffix = Path(filename).suffix or ".xlsx"
    with NamedTemporaryFile(delete=False, suffix=suffix, dir=upload_dir) as temp:
        temp_path = Path(temp.name)
        uploaded.save(temp)

    try:
        return parse_xlsx_meal_menus(temp_path, source_filename=uploaded.filename)
    finally:
        try:
            temp_path.unlink(missing_ok=True)
        except OSError:
            pass


def _import_path(import_id: str, import_dir: Path) -> Path:
    safe_id = "".join(ch for ch in import_id if ch.isalnum())
    return import_dir / f"{safe_id}.json"


def _safe_next_url(next_url: str) -> str:
    if next_url.startswith("/") and not next_url.startswith("//"):
        return next_url
    return url_for("admin")


def _render_users_page(error: str = ""):
    return render_template(
        "users.html",
        csrf_token=csrf_token(),
        users=user_store().list_users(),
        current_user_id=current_user_id(),
        status=request.args.get("status", ""),
        error=error,
    )


app = create_app()


if __name__ == "__main__":
    port = int(os.environ.get("PORT", DEFAULT_PORT))
    app.run(host="127.0.0.1", port=port, debug=os.environ.get("FLASK_DEBUG") == "1")
