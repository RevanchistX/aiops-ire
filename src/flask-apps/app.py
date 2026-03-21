"""Flask chaos-target microservice.

Exposes intentionally broken endpoints for chaos engineering experiments.
Prometheus metrics are exported on /metrics via prometheus-client.
"""

import logging
import math
import random
import threading
import time

from flask import Flask, jsonify
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("flask-app")

# ─── App ──────────────────────────────────────────────────────────────────────
app = Flask(__name__)

# ─── Prometheus metrics ───────────────────────────────────────────────────────
REQUEST_COUNT = Counter(
    "flask_app_requests_total",
    "Total number of requests by endpoint and status",
    ["endpoint", "status_code"],
)
REQUEST_LATENCY = Histogram(
    "flask_app_request_duration_seconds",
    "Request latency by endpoint",
    ["endpoint"],
)

# In-memory store so the memory leak is actually reachable across requests
_memory_leak_store: list = []


# ─── Helpers ──────────────────────────────────────────────────────────────────
def _log_request(endpoint: str, status: int) -> None:
    """Log every request with ISO timestamp, endpoint name, and HTTP status."""
    logger.info("endpoint=%s status=%d", endpoint, status)


# ─── Routes ───────────────────────────────────────────────────────────────────
@app.route("/health")
def health() -> tuple:
    """Liveness / readiness probe — always returns 200."""
    _log_request("/health", 200)
    REQUEST_COUNT.labels(endpoint="/health", status_code="200").inc()
    return jsonify({"status": "ok"}), 200


@app.route("/cpu")
def cpu() -> tuple:
    """Spike a single CPU core for 30 seconds via busy-loop math, then respond."""
    _log_request("/cpu", 200)
    REQUEST_COUNT.labels(endpoint="/cpu", status_code="200").inc()

    duration = 30  # seconds

    def _burn(seconds: int) -> None:
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            # Tight arithmetic loop — keeps one core pinned at ~100 %
            _ = math.sqrt(random.random()) * math.pi

    thread = threading.Thread(target=_burn, args=(duration,), daemon=True)
    thread.start()

    logger.info("endpoint=/cpu action=cpu_spike_started duration_seconds=%d", duration)
    return jsonify({"status": "cpu spike started", "duration_seconds": duration}), 200


@app.route("/memory")
def memory() -> tuple:
    """Append ~10 MB of data to an in-process list, leaking memory intentionally."""
    _log_request("/memory", 200)
    REQUEST_COUNT.labels(endpoint="/memory", status_code="200").inc()

    chunk_size_mb = 10
    chunk = " " * (chunk_size_mb * 1024 * 1024)
    _memory_leak_store.append(chunk)

    total_mb = len(_memory_leak_store) * chunk_size_mb
    logger.info(
        "endpoint=/memory action=memory_leak chunk_mb=%d total_leaked_mb=%d",
        chunk_size_mb,
        total_mb,
    )
    return jsonify({"status": "memory leaked", "total_leaked_mb": total_mb}), 200


@app.route("/error")
def error() -> tuple:
    """Always returns HTTP 500 to trigger Prometheus error-rate alerts."""
    _log_request("/error", 500)
    REQUEST_COUNT.labels(endpoint="/error", status_code="500").inc()
    logger.error("endpoint=/error action=intentional_error")
    return jsonify({"status": "error", "message": "intentional failure"}), 500


@app.route("/slow")
def slow() -> tuple:
    """Sleep for a random 5–30 s delay to trigger latency alerts."""
    delay = random.uniform(5, 30)
    logger.info("endpoint=/slow action=sleeping delay_seconds=%.2f", delay)

    with REQUEST_LATENCY.labels(endpoint="/slow").time():
        time.sleep(delay)

    _log_request("/slow", 200)
    REQUEST_COUNT.labels(endpoint="/slow", status_code="200").inc()
    return jsonify({"status": "ok", "delay_seconds": round(delay, 2)}), 200


@app.route("/metrics")
def metrics():
    """Prometheus metrics scrape endpoint."""
    _log_request("/metrics", 200)
    return generate_latest(), 200, {"Content-Type": CONTENT_TYPE_LATEST}


# ─── Entrypoint ───────────────────────────────────────────────────────────────
if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
