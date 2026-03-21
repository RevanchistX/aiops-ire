"""Loki HTTP API client.

Queries /loki/api/v1/query_range and returns a single concatenated log string
suitable for inclusion in the Claude API prompt.
"""

import logging
import os
from datetime import datetime, timedelta, timezone

import httpx

logger = logging.getLogger(__name__)

LOKI_URL: str = os.environ["LOKI_URL"].rstrip("/")
_LOG_WINDOW_MINUTES: int = 10
_MAX_LOG_LINES: int = 500


def _now_ns() -> int:
    """Current UTC time as nanosecond epoch (Loki's native timestamp format)."""
    return int(datetime.now(tz=timezone.utc).timestamp() * 1e9)


def _minutes_ago_ns(minutes: int) -> int:
    delta = datetime.now(tz=timezone.utc) - timedelta(minutes=minutes)
    return int(delta.timestamp() * 1e9)


async def fetch_logs(service: str, namespace: str = "apps") -> str:
    """Fetch the last ``_LOG_WINDOW_MINUTES`` minutes of logs for *service*.

    Falls back to a broad namespace query when the service-specific stream
    returns no results (e.g. the label hasn't propagated yet).

    Returns a single newline-joined string of log lines, or a placeholder
    when no logs are found.
    """
    end_ns = _now_ns()
    start_ns = _minutes_ago_ns(_LOG_WINDOW_MINUTES)

    queries = [
        f'{{namespace="{namespace}", app="{service}"}}',
        f'{{namespace="{namespace}"}}',
    ]

    async with httpx.AsyncClient(timeout=30.0) as client:
        for logql in queries:
            lines = await _query_range(client, logql, start_ns, end_ns)
            if lines:
                logger.info(
                    "loki_query query=%r lines_returned=%d", logql, len(lines)
                )
                return "\n".join(lines)

    logger.warning("loki_query service=%s result=no_logs_found", service)
    return f"[no logs found for service={service} in the last {_LOG_WINDOW_MINUTES} minutes]"


async def _query_range(
    client: httpx.AsyncClient,
    query: str,
    start_ns: int,
    end_ns: int,
) -> list[str]:
    """Execute one Loki query_range call and return a flat list of log lines."""
    try:
        resp = await client.get(
            f"{LOKI_URL}/loki/api/v1/query_range",
            params={
                "query": query,
                "start": str(start_ns),
                "end": str(end_ns),
                "limit": str(_MAX_LOG_LINES),
                "direction": "forward",
            },
        )
        resp.raise_for_status()
    except httpx.HTTPError as exc:
        logger.error("loki_query error=%s", exc)
        return []

    payload = resp.json()
    lines: list[str] = []

    for stream in payload.get("data", {}).get("result", []):
        for ts_ns, log_line in stream.get("values", []):
            # Convert nanosecond epoch to readable timestamp
            ts = datetime.fromtimestamp(int(ts_ns) / 1e9, tz=timezone.utc)
            lines.append(f"{ts.strftime('%Y-%m-%dT%H:%M:%SZ')} {log_line}")

    return lines
