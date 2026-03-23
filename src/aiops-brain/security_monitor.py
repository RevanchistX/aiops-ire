"""CryptoFlux security monitor.

Scans Loki logs for security events across all CryptoFlux services:
  - SQL injection patterns in trading-ui SEARCH query logs
  - XSS payloads in trading-ui SEARCH query logs
  - Info-leak via /internal/* endpoint access
  - Hardcoded secret value appearing in any log
  - Transaction ingestion gap (no 'Cycle OK' in 15 min)
  - DR sync failures ('Sync error' in dr-sync logs)
"""

import logging
import re
from datetime import datetime, timedelta, timezone

import httpx
from pydantic import BaseModel

from loki_client import _now_ns, _minutes_ago_ns, _query_range

logger = logging.getLogger(__name__)

_SCAN_WINDOW_MINUTES: int = 15
_LOKI_LIMIT: int = 500

# Services scanned on every call to scan_all() — (app label, namespace)
_CRYPTOFLUX_SERVICES: list[tuple[str, str]] = [
    ("trading-ui", "cryptoflux"),
    ("liquidity-calc", "cryptoflux"),
    ("data-ingestion", "cryptoflux"),
    ("dr-sync", "cryptoflux"),
    ("attack-console", "cryptoflux"),
]

# ─── Compiled patterns ─────────────────────────────────────────────────────────

_SQL_INJECTION_RE = re.compile(
    r"OR\s+'1'\s*=\s*'1'"
    r"|UNION\s+SELECT"
    r"|DROP\s+TABLE"
    r"|--\s*$"
    r"|;\s*--"
    r"|'\s+OR\s+"
    r"|1\s*=\s*1",
    re.IGNORECASE | re.MULTILINE,
)

_XSS_RE = re.compile(
    r"<script"
    r"|javascript:"
    r"|onerror\s*="
    r"|onload\s*=",
    re.IGNORECASE,
)

_INFO_LEAK_RE = re.compile(r"/internal/(debug|info)", re.IGNORECASE)
_HARDCODED_SECRET_RE = re.compile(r"hardcoded_secret_123")
_CYCLE_OK_RE = re.compile(r"Cycle OK|ok=\d+", re.IGNORECASE)
_SYNC_ERROR_RE = re.compile(r"Sync error", re.IGNORECASE)
_CMD_INJECTION_RE = re.compile(r"CMD query=.*?([;&|`]|&&|\|\|)")
_BROKEN_AUTH_RE = re.compile(
    r"LOGIN attempt.*?(OR\s+'?1'?='?1|admin'\s*--|'\s*OR)",
    re.IGNORECASE,
)


# ─── Data model ───────────────────────────────────────────────────────────────

class SecurityEvent(BaseModel):
    """A detected security anomaly from log analysis."""

    event_type: str          # e.g. "SecurityScan:SQLInjection"
    severity: str            # critical / warning / info
    service: str             # cryptoflux service name
    description: str         # human-readable summary
    evidence: str            # matching log lines (newline-separated, capped at 10)


# ─── Loki fetch ───────────────────────────────────────────────────────────────

async def _fetch_logs(service: str, namespace: str) -> list[str]:
    """Return up to _LOKI_LIMIT log lines for the last _SCAN_WINDOW_MINUTES minutes."""
    end_ns = _now_ns()
    start_ns = _minutes_ago_ns(_SCAN_WINDOW_MINUTES)

    queries = [
        f'{{namespace="{namespace}", app="{service}"}}',
        f'{{namespace="{namespace}"}}',
    ]

    async with httpx.AsyncClient(timeout=30.0) as client:
        for logql in queries:
            lines = await _query_range(client, logql, start_ns, end_ns)
            if lines:
                logger.debug("security_scan service=%s logql=%r lines=%d", service, logql, len(lines))
                return lines

    logger.warning("security_scan service=%s result=no_logs", service)
    return []


# ─── Individual detectors ─────────────────────────────────────────────────────

def _check_sql_injection(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect SQL injection patterns in SEARCH query log entries."""
    evidence = [
        line for line in lines
        if "SEARCH query=" in line and _SQL_INJECTION_RE.search(line)
    ]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:SQLInjection",
        severity="critical",
        service=service,
        description="SQL injection pattern detected in trading-ui search query logs",
        evidence="\n".join(evidence[:10]),
    )


# Alias used by the attack-console detector list
_check_sqli = _check_sql_injection


def _check_xss(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect XSS payloads in SEARCH query log entries."""
    evidence = [
        line for line in lines
        if "SEARCH query=" in line and _XSS_RE.search(line)
    ]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:XSS",
        severity="critical",
        service=service,
        description="XSS payload detected in trading-ui search query logs",
        evidence="\n".join(evidence[:10]),
    )


def _check_info_leak(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect access to /internal/debug or /internal/info endpoints."""
    evidence = [line for line in lines if _INFO_LEAK_RE.search(line)]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:InfoLeak",
        severity="warning",
        service=service,
        description=(
            "/internal/debug or /internal/info endpoint was accessed — "
            "environment variables may have been exposed"
        ),
        evidence="\n".join(evidence[:10]),
    )


def _check_hardcoded_secret(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect the literal hardcoded_secret_123 value appearing in any log line."""
    evidence = [line for line in lines if _HARDCODED_SECRET_RE.search(line)]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:HardcodedSecret",
        severity="warning",
        service=service,
        description=(
            "Hardcoded secret 'hardcoded_secret_123' found in logs — "
            "INTERNAL_SERVICE_KEY is hardcoded in liquidity-calc"
        ),
        evidence="\n".join(evidence[:10]),
    )


def _check_transaction_gap(lines: list[str], service: str) -> SecurityEvent | None:
    """Fire when no 'Cycle OK' appears in data-ingestion logs for the scan window."""
    if lines and any(_CYCLE_OK_RE.search(line) for line in lines):
        return None
    recent = lines[-5:] if lines else ["[no logs found for data-ingestion]"]
    return SecurityEvent(
        event_type="SecurityScan:TransactionGap",
        severity="critical",
        service=service,
        description=(
            f"No 'Cycle OK' entry found in data-ingestion logs "
            f"over the last {_SCAN_WINDOW_MINUTES} minutes — ingestion may have stalled"
        ),
        evidence="\n".join(recent),
    )


def _check_dr_sync_failure(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect 'Sync error' messages in dr-sync logs."""
    evidence = [line for line in lines if _SYNC_ERROR_RE.search(line)]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:DRSyncFailure",
        severity="warning",
        service=service,
        description=(
            "DR sync errors detected — replication lag may exceed the "
            "RPO target of 5 minutes"
        ),
        evidence="\n".join(evidence[:10]),
    )


def _check_cmd_injection(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect OS command injection attempts in attack-console CMD logs."""
    evidence = [
        line for line in lines
        if "CMD query=" in line and _CMD_INJECTION_RE.search(line)
    ]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:CommandInjection",
        severity="critical",
        service=service,
        description=(
            "OS command injection pattern detected in attack-console CMD logs — "
            "shell metacharacters (;, &, |, `) found in ping target input"
        ),
        evidence="\n".join(evidence[:10]),
    )


def _check_broken_auth(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect SQL injection-based login bypass attempts in attack-console LOGIN logs."""
    evidence = [
        line for line in lines
        if "LOGIN attempt" in line and _BROKEN_AUTH_RE.search(line)
    ]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:BrokenAuth",
        severity="critical",
        service=service,
        description=(
            "Authentication bypass via SQL injection detected in attack-console login logs — "
            "OR '1'='1' or admin'-- pattern found in username field"
        ),
        evidence="\n".join(evidence[:10]),
    )


def _check_xss_stored(lines: list[str], service: str) -> SecurityEvent | None:
    """Detect stored/reflected XSS payloads in attack-console XSS logs."""
    evidence = [
        line for line in lines
        if "XSS attempt" in line and _XSS_RE.search(line)
    ]
    if not evidence:
        return None
    return SecurityEvent(
        event_type="SecurityScan:XSS",
        severity="critical",
        service=service,
        description=(
            "XSS payload detected in attack-console stored/reflected XSS logs — "
            "<script>, javascript:, or onerror= found in comment input"
        ),
        evidence="\n".join(evidence[:10]),
    )


# ─── Main scan entry point ────────────────────────────────────────────────────

_DETECTORS: dict[str, list] = {
    "trading-ui":     [_check_sql_injection, _check_xss, _check_info_leak],
    "liquidity-calc": [_check_hardcoded_secret],
    "data-ingestion": [_check_transaction_gap],
    "dr-sync":        [_check_dr_sync_failure],
    "attack-console": [_check_cmd_injection, _check_broken_auth, _check_sqli, _check_xss_stored],
}


async def scan_all() -> list[SecurityEvent]:
    """Scan all CryptoFlux services and return every detected SecurityEvent.

    Queries the last 15 minutes of Loki logs per service and runs each
    applicable detector. Never raises — individual errors are logged and
    skipped so one failing service doesn't abort the entire scan.
    """
    events: list[SecurityEvent] = []

    for service, namespace in _CRYPTOFLUX_SERVICES:
        try:
            lines = await _fetch_logs(service, namespace)
            logger.info("security_scan service=%s lines_fetched=%d", service, len(lines))
        except Exception as exc:
            logger.error("security_scan service=%s fetch_error=%s", service, exc)
            continue

        for detector in _DETECTORS.get(service, []):
            try:
                event = detector(lines, service)
            except Exception as exc:
                logger.error("security_scan service=%s detector=%s error=%s", service, detector.__name__, exc)
                continue

            if event:
                logger.warning(
                    "security_event type=%s severity=%s service=%s",
                    event.event_type, event.severity, event.service,
                )
                events.append(event)

    logger.info("security_scan complete events_found=%d", len(events))
    return events
