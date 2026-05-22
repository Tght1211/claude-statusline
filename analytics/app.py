import os
import json
import sqlite3
from pathlib import Path
from flask import Flask, jsonify, request, send_from_directory

app = Flask(__name__, static_folder="static", static_url_path="")

DB_PATH = os.environ.get("ANALYTICS_DB", str(Path.home() / ".claude/statusline/analytics.db"))
PROVIDERS_DIR = os.environ.get("PROVIDERS_DIR", str(Path.home() / ".claude/statusline/providers"))


def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=5)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def parse_date_filters():
    from_date = request.args.get("from")
    to_date = request.args.get("to")
    model = request.args.get("model")
    conditions = []
    params = []
    if from_date:
        conditions.append("timestamp >= ?")
        params.append(from_date)
    if to_date:
        conditions.append("timestamp <= ?")
        params.append(to_date + "T23:59:59Z")
    if model:
        conditions.append("model LIKE ?")
        params.append(f"%{model}%")
    where = " WHERE " + " AND ".join(conditions) if conditions else ""
    return where, params


@app.route("/")
def index():
    return send_from_directory("static", "index.html")


@app.route("/api/usage/summary")
def usage_summary():
    where, params = parse_date_filters()
    db = get_db()
    row = db.execute(f"""
        SELECT COUNT(*) as request_count,
               COALESCE(SUM(cost_usd), 0) as total_cost,
               COALESCE(SUM(input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens), 0) as total_tokens,
               COALESCE(SUM(input_tokens), 0) as total_input,
               COALESCE(SUM(output_tokens), 0) as total_output,
               COALESCE(SUM(cache_creation_input_tokens), 0) as total_cache_create,
               COALESCE(SUM(cache_read_input_tokens), 0) as total_cache_read
        FROM requests{where}
    """, params).fetchone()
    db.close()
    return jsonify(dict(row))


@app.route("/api/overview")
def overview():
    """Combined endpoint for overview page - single request instead of 5."""
    from datetime import date, timedelta
    today = date.today().isoformat()
    week_ago = (date.today() - timedelta(days=7)).isoformat()
    month_start = today[:8] + "01"

    db = get_db()

    def sum_cost(from_date):
        row = db.execute(
            "SELECT COALESCE(SUM(cost_usd), 0) as c FROM requests WHERE timestamp >= ?",
            (from_date,),
        ).fetchone()
        return row["c"]

    total_row = db.execute(
        "SELECT COALESCE(SUM(cost_usd), 0) as c FROM requests"
    ).fetchone()

    daily = db.execute("""
        SELECT date(timestamp) as date, COUNT(*) as count,
               SUM(cost_usd) as cost,
               SUM(input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens) as tokens
        FROM requests GROUP BY date(timestamp) ORDER BY date(timestamp)
    """).fetchall()

    result = {
        "today": sum_cost(today),
        "week": sum_cost(week_ago),
        "month": sum_cost(month_start),
        "total": total_row["c"],
        "daily": [dict(r) for r in daily],
    }
    db.close()
    return jsonify(result)


@app.route("/api/usage/daily")
def usage_daily():
    where, params = parse_date_filters()
    db = get_db()
    rows = db.execute(f"""
        SELECT date(timestamp) as date,
               COUNT(*) as count,
               SUM(cost_usd) as cost,
               SUM(input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens) as tokens
        FROM requests{where}
        GROUP BY date(timestamp)
        ORDER BY date(timestamp)
    """, params).fetchall()
    db.close()
    return jsonify([dict(r) for r in rows])


@app.route("/api/usage/by-model")
def usage_by_model():
    where, params = parse_date_filters()
    db = get_db()
    rows = db.execute(f"""
        SELECT model,
               COUNT(*) as count,
               SUM(cost_usd) as cost,
               SUM(input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens) as tokens
        FROM requests{where}
        GROUP BY model
        ORDER BY cost DESC
    """, params).fetchall()
    db.close()
    return jsonify([dict(r) for r in rows])


@app.route("/api/usage/by-session")
def usage_by_session():
    where, params = parse_date_filters()
    db = get_db()
    rows = db.execute(f"""
        SELECT session_id,
               cwd,
               COUNT(*) as count,
               SUM(cost_usd) as cost,
               SUM(input_tokens + output_tokens + cache_creation_input_tokens + cache_read_input_tokens) as tokens,
               MIN(timestamp) as first_ts,
               MAX(timestamp) as last_ts
        FROM requests{where}
        GROUP BY session_id
        ORDER BY first_ts DESC
        LIMIT 200
    """, params).fetchall()
    db.close()
    return jsonify([dict(r) for r in rows])


@app.route("/api/usage/requests")
def usage_requests():
    where, params = parse_date_filters()
    session_id = request.args.get("session_id")
    if session_id:
        if where:
            where += " AND session_id = ?"
        else:
            where = " WHERE session_id = ?"
        params.append(session_id)
    db = get_db()
    rows = db.execute(f"""
        SELECT message_id, session_id, model, timestamp, cwd,
               input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens,
               cost_usd
        FROM requests{where}
        ORDER BY timestamp DESC
        LIMIT 500
    """, params).fetchall()
    db.close()
    return jsonify([dict(r) for r in rows])


@app.route("/api/providers")
def list_providers():
    providers = []
    providers_path = Path(PROVIDERS_DIR)
    if not providers_path.exists():
        return jsonify(providers)
    for d in sorted(providers_path.iterdir()):
        manifest_path = d / "manifest.json" if d.is_dir() else None
        if not manifest_path:
            if d.is_symlink():
                target = d.resolve()
                manifest_path = target / "manifest.json"
            else:
                continue
        if manifest_path and manifest_path.exists():
            try:
                manifest = json.loads(manifest_path.read_text())
                manifest["hasConfig"] = (d / "config.json").exists() or (d.resolve() / "config.json").exists()
                providers.append(manifest)
            except (json.JSONDecodeError, OSError):
                continue
    return jsonify(providers)


@app.route("/api/providers/<provider_id>")
def get_provider(provider_id):
    provider_path = Path(PROVIDERS_DIR) / provider_id
    if not provider_path.exists() and not provider_path.is_symlink():
        return jsonify({"error": "Provider not found"}), 404
    real_path = provider_path.resolve()
    manifest_path = real_path / "manifest.json"
    if not manifest_path.exists():
        return jsonify({"error": "Invalid provider: no manifest.json"}), 404
    manifest = json.loads(manifest_path.read_text())
    config_path = real_path / "config.json"
    config = {}
    if config_path.exists():
        try:
            config = json.loads(config_path.read_text())
        except (json.JSONDecodeError, OSError):
            pass
    return jsonify({"manifest": manifest, "config": config})


@app.route("/api/providers/<provider_id>/config", methods=["PUT"])
def update_provider_config(provider_id):
    provider_path = Path(PROVIDERS_DIR) / provider_id
    if not provider_path.exists() and not provider_path.is_symlink():
        return jsonify({"error": "Provider not found"}), 404
    real_path = provider_path.resolve()
    config_path = real_path / "config.json"
    data = request.get_json()
    if not data:
        return jsonify({"error": "Empty body"}), 400
    config_path.write_text(json.dumps(data, indent=2, ensure_ascii=False))
    return jsonify({"ok": True})


@app.route("/api/providers", methods=["POST"])
def create_provider():
    data = request.get_json()
    if not data or "id" not in data:
        return jsonify({"error": "Missing provider id"}), 400
    pid = data["id"]
    provider_path = Path(PROVIDERS_DIR) / pid
    if provider_path.exists():
        return jsonify({"error": "Provider already exists"}), 409
    provider_path.mkdir(parents=True)
    manifest = {
        "id": pid,
        "name": data.get("name", pid),
        "version": "1.0.0",
        "description": data.get("description", ""),
        "match": data.get("match", []),
        "cacheTtl": data.get("cacheTtl", 120),
        "fetch": "fetch.sh",
    }
    if data.get("modelMap"):
        manifest["modelMap"] = data["modelMap"]
    (provider_path / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False))
    fetch_template = '#!/bin/bash\n# TODO: implement quota fetching\nerr() { jq -cn --arg m "$1" \'{error:$m}\'; exit 0; }\nerr "Not implemented"\n'
    fetch_path = provider_path / "fetch.sh"
    fetch_path.write_text(fetch_template)
    fetch_path.chmod(0o755)
    return jsonify(manifest), 201


@app.route("/api/providers/<provider_id>", methods=["DELETE"])
def delete_provider(provider_id):
    if request.args.get("confirm") != "true":
        return jsonify({"error": "Add ?confirm=true to confirm deletion"}), 400
    provider_path = Path(PROVIDERS_DIR) / provider_id
    if not provider_path.exists() and not provider_path.is_symlink():
        return jsonify({"error": "Provider not found"}), 404
    import shutil
    if provider_path.is_symlink():
        provider_path.unlink()
    else:
        shutil.rmtree(provider_path)
    return jsonify({"ok": True})


if __name__ == "__main__":
    port = int(os.environ.get("PORT", 5211))
    print(f"Analytics server starting on http://localhost:{port}")
    app.run(host="127.0.0.1", port=port, debug=False)
