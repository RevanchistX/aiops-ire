"""Attack Console — DVWA-style security vulnerability demonstration app.

This Flask application intentionally demonstrates common web vulnerabilities
for security training purposes. DO NOT deploy in production.
"""

import logging
import os
import sqlite3

import requests
from flask import Flask, request, render_template_string, render_template

app = Flask(__name__)

logging.basicConfig(
    level=logging.WARNING,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("attack-console")

TRADING_DATA_URL = os.environ.get("TRADING_DATA_URL", "http://trading-data:7100")

# ─── In-memory stores ─────────────────────────────────────────────────────────

# XSS stored comments
_comments: list[str] = []

# SQLi demo — in-memory SQLite with a users table
_db_conn = sqlite3.connect(":memory:", check_same_thread=False)
_db_conn.execute(
    "CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, password TEXT, role TEXT)"
)
_db_conn.executemany(
    "INSERT INTO users VALUES (?, ?, ?, ?)",
    [
        (1, "admin", "supersecret", "admin"),
        (2, "alice", "password123", "user"),
        (3, "bob", "letmein", "user"),
    ],
)
_db_conn.commit()


# ─── Helpers ──────────────────────────────────────────────────────────────────


def _client_ip() -> str:
    """Return the best-guess client IP from request context."""
    return request.headers.get("X-Forwarded-For", request.remote_addr or "unknown")


# ─── Routes ───────────────────────────────────────────────────────────────────


@app.route("/")
def index():
    """Landing page — list all vulnerability categories."""
    return render_template("index.html")


@app.route("/sqli", methods=["GET", "POST"])
def sqli():
    """SQL injection demonstration."""
    query = result_vuln = result_safe = error = None

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        ip = _client_ip()

        logger.warning("SQLI attempt username=%s ip=%s", username, ip)

        # Vulnerable: raw string interpolation
        query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
        try:
            cur = _db_conn.execute(query)
            rows = cur.fetchall()
            result_vuln = rows if rows else []
        except Exception as exc:
            error = str(exc)
            result_vuln = []

        # Safe: parameterized query
        try:
            cur2 = _db_conn.execute(
                "SELECT * FROM users WHERE username=? AND password=?",
                (username, password),
            )
            result_safe = cur2.fetchall()
        except Exception:
            result_safe = []

    return render_template(
        "sqli.html",
        query=query,
        result_vuln=result_vuln,
        result_safe=result_safe,
        error=error,
    )


@app.route("/xss", methods=["GET", "POST"])
def xss():
    """XSS (reflected + stored) demonstration."""
    reflected = None

    if request.method == "POST":
        comment = request.form.get("comment", "")
        action = request.form.get("action", "stored")
        ip = _client_ip()

        logger.warning("XSS attempt comment=%r ip=%s", comment[:120], ip)

        if action == "reflected":
            # Reflected XSS — value rendered unescaped in the template via |safe
            reflected = comment
        else:
            # Stored XSS — saved to in-memory list, displayed unescaped
            _comments.append(comment)

    return render_template("xss.html", reflected=reflected, comments=_comments)


@app.route("/login", methods=["GET", "POST"])
def login():
    """Broken authentication / SQLi bypass demonstration."""
    success = fake_jwt = None
    error = None

    if request.method == "POST":
        username = request.form.get("username", "")
        password = request.form.get("password", "")
        ip = _client_ip()

        logger.warning("LOGIN attempt user=%s ip=%s", username, ip)

        # Vulnerable: raw string interpolation — bypass with  admin' OR '1'='1' --
        query = f"SELECT * FROM users WHERE username='{username}' AND password='{password}'"
        try:
            cur = _db_conn.execute(query)
            row = cur.fetchone()
            if row:
                success = True
                # Fake JWT — obviously not cryptographically valid
                import base64, json
                header = base64.b64encode(b'{"alg":"none","typ":"JWT"}').decode()
                payload_data = {"sub": row[1], "role": row[3], "iat": 1700000000}
                payload = base64.b64encode(
                    json.dumps(payload_data).encode()
                ).decode()
                fake_jwt = f"{header}.{payload}.fakesignature"
            else:
                error = "Invalid credentials"
        except Exception as exc:
            error = str(exc)

    return render_template("login.html", success=success, fake_jwt=fake_jwt, error=error)


@app.route("/info-leak")
def info_leak():
    """Information leakage — calls trading-data internal endpoint."""
    ip = _client_ip()
    logger.warning("INFO-LEAK probe ip=%s", ip)

    data = error = None
    url = f"{TRADING_DATA_URL}/internal/info"
    try:
        resp = requests.get(url, timeout=5)
        data = resp.text
        status = resp.status_code
    except Exception as exc:
        error = str(exc)
        status = None

    return render_template("info_leak.html", data=data, error=error, url=url, status=status)


@app.route("/cmd-injection", methods=["GET", "POST"])
def cmd_injection():
    """OS command injection demonstration."""
    output = None

    if request.method == "POST":
        target = request.form.get("target", "")
        ip = _client_ip()

        logger.warning("CMD query=%s ip=%s", target, ip)

        # Vulnerable: unvalidated input passed to shell
        try:
            output = os.popen(f"ping -c 1 {target}").read()  # noqa: S605
        except Exception as exc:
            output = f"Error: {exc}"

    return render_template("cmd_injection.html", output=output)


@app.route("/api/health")
def health():
    """Health check endpoint."""
    from flask import jsonify
    return jsonify({"status": "ok"})
