"""aiops-brain — the self-healing pipeline controller.

Receives Alertmanager webhooks, pulls Loki logs, analyses the incident via
Claude API, persists to PostgreSQL, opens a GitHub issue, and attempts
Kubernetes auto-remediation — all with zero human involvement.

Endpoints:
  POST /webhook        — Alertmanager webhook receiver
  GET  /health         — liveness / readiness probe
  GET  /incidents      — last 20 incidents (JSON)
  POST /security-scan  — trigger CryptoFlux security scan
  GET  /security-events — last 50 security scan incidents (JSON)
"""

import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from fastapi import BackgroundTasks, Depends, FastAPI
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from analyzer import analyse_alert
from database import Base, engine, get_db
from github_client import open_issue
from loki_client import fetch_logs
from models import Incident
from remediation import attempt_remediation
import security_monitor
from security_monitor import SecurityEvent
from slack_client import notify_incident

# ─── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s - %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("aiops-brain")

# ─── App ──────────────────────────────────────────────────────────────────────
app = FastAPI(
    title="aiops-brain",
    description="Self-healing infrastructure pipeline — webhook receiver and incident processor",
    version="1.0.0",
)


# ─── Startup: create tables ───────────────────────────────────────────────────
@app.on_event("startup")
async def on_startup() -> None:
    """Create all tables if they don't exist (idempotent)."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    logger.info("startup database tables ensured")


# ─── Pydantic schemas ─────────────────────────────────────────────────────────
class AlertLabel(BaseModel):
    """Alertmanager alert labels block (open schema)."""

    model_config = {"extra": "allow"}

    alertname: str = "UnknownAlert"
    severity: str = "unknown"
    service: str = "unknown"
    namespace: str = "apps"


class AlertAnnotation(BaseModel):
    model_config = {"extra": "allow"}


class AlertItem(BaseModel):
    status: str
    labels: AlertLabel
    annotations: dict[str, Any] = Field(default_factory=dict)
    startsAt: str = ""
    endsAt: str = ""
    fingerprint: str = ""

    model_config = {"extra": "allow"}


class AlertmanagerPayload(BaseModel):
    """Top-level Alertmanager webhook POST body (v4 format)."""

    receiver: str = ""
    status: str = "firing"
    alerts: list[AlertItem] = Field(default_factory=list)
    groupLabels: dict[str, Any] = Field(default_factory=dict)
    commonLabels: dict[str, Any] = Field(default_factory=dict)
    commonAnnotations: dict[str, Any] = Field(default_factory=dict)
    externalURL: str = ""
    version: str = "4"
    groupKey: str = ""

    model_config = {"extra": "allow"}


class IncidentResponse(BaseModel):
    """Public representation of a persisted incident."""

    id: uuid.UUID
    alert_name: str
    severity: str
    service: str
    fired_at: datetime
    resolved_at: datetime | None
    root_cause: str
    runbook: str
    github_issue_url: str | None
    remediation_action: str | None
    remediation_result: str | None
    created_at: datetime

    model_config = {"from_attributes": True}


# ─── Routes ───────────────────────────────────────────────────────────────────
@app.get("/health")
async def health() -> dict[str, str]:
    """Kubernetes liveness / readiness probe."""
    logger.info("endpoint=/health status=ok")
    return {"status": "ok"}


@app.get("/incidents", response_model=list[IncidentResponse])
async def list_incidents(db: AsyncSession = Depends(get_db)) -> list[Incident]:
    """Return the 20 most recent incidents, newest first."""
    logger.info("endpoint=/incidents")
    result = await db.execute(
        select(Incident).order_by(desc(Incident.created_at)).limit(20)
    )
    return list(result.scalars().all())


@app.post("/webhook", status_code=202)
async def webhook(
    payload: AlertmanagerPayload,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Receive Alertmanager webhook and kick off the incident pipeline.

    Returns 202 immediately so Alertmanager doesn't time out; the full
    analysis pipeline runs as a background task.
    """
    logger.info(
        "endpoint=/webhook status=%s alerts=%d",
        payload.status,
        len(payload.alerts),
    )

    for alert in payload.alerts:
        background_tasks.add_task(_process_alert, alert, payload, db)

    return {"status": "accepted", "alerts": str(len(payload.alerts))}


# ─── Pipeline ─────────────────────────────────────────────────────────────────
async def _process_alert(
    alert: AlertItem,
    payload: AlertmanagerPayload,
    db: AsyncSession,
) -> None:
    """Full incident pipeline for a single alert.

    Steps:
      1. Extract metadata
      2. Fetch Loki logs
      3. Call Claude API for analysis
      4. Persist incident to PostgreSQL
      5. Open GitHub issue
      6. Send Slack notification
      7. Attempt auto-remediation
      8. Update incident in PostgreSQL
    """
    alert_name = alert.labels.alertname
    severity = alert.labels.severity
    service = alert.labels.service
    namespace = alert.labels.namespace

    logger.info(
        "pipeline alert=%s severity=%s service=%s step=start",
        alert_name,
        severity,
        service,
    )

    # ── 1. Parse fired_at ───────────────────────────────────────────────────
    try:
        fired_at = datetime.fromisoformat(alert.startsAt.replace("Z", "+00:00"))
    except (ValueError, AttributeError):
        fired_at = datetime.now(tz=timezone.utc)

    # ── 2. Fetch Loki logs ──────────────────────────────────────────────────
    logger.info("pipeline alert=%s step=fetch_logs service=%s", alert_name, service)
    logs = await fetch_logs(service=service, namespace=namespace)

    # ── 3. Deduplication check (30-minute window) ───────────────────────────
    cutoff = datetime.now(tz=timezone.utc).replace(tzinfo=None) - timedelta(minutes=30)
    dup_result = await db.execute(
        select(func.count(Incident.id))
        .where(Incident.alert_name == alert_name)
        .where(Incident.service == service)
        .where(Incident.created_at >= cutoff)
    )
    if dup_result.scalar() > 0:
        logger.info(
            "pipeline alert=%s deduplicated service=%s window=30m",
            alert_name, service,
        )
        return

    # ── 4. Claude API analysis ──────────────────────────────────────────────
    logger.info("pipeline alert=%s step=claude_analysis", alert_name)
    try:
        analysis = await analyse_alert(
            alert_name=alert_name,
            severity=severity,
            service=service,
            labels=alert.labels.model_dump(),
            annotations=alert.annotations,
            logs=logs,
        )
    except Exception as exc:
        logger.error("pipeline alert=%s step=claude_analysis error=%s", alert_name, exc)
        analysis = None

    root_cause = analysis.root_cause if analysis else "Claude analysis failed"
    runbook = analysis.runbook if analysis else "Manual investigation required"
    full_response = analysis.full_response if analysis else "n/a"
    auto_remediation_safe = analysis.auto_remediation_safe if analysis else False

    # ── 5. Persist incident ─────────────────────────────────────────────────
    logger.info("pipeline alert=%s step=persist", alert_name)
    incident = Incident(
        alert_name=alert_name,
        severity=severity,
        service=service,
        fired_at=fired_at.replace(tzinfo=None),  # store as naive UTC
        raw_alert=payload.model_dump(),
        logs_snapshot=logs,
        claude_analysis=full_response,
        root_cause=root_cause,
        runbook=runbook,
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)
    logger.info("pipeline alert=%s step=persist incident_id=%s", alert_name, incident.id)

    # ── 6. Open GitHub issue ────────────────────────────────────────────────
    logger.info("pipeline alert=%s step=github_issue", alert_name)
    issue_url = await open_issue(
        alert_name=alert_name,
        severity=severity,
        service=service,
        fired_at=fired_at,
        root_cause=root_cause,
        runbook=runbook,
        severity_assessment=analysis.severity_assessment if analysis else "Unknown",
        logs_snapshot=logs,
    )
    incident.github_issue_url = issue_url
    await db.commit()

    # ── 7. Slack notification ───────────────────────────────────────────────
    logger.info("pipeline alert=%s step=slack_notify", alert_name)
    await notify_incident(
        alert_name=alert_name,
        severity=severity,
        service=service,
        fired_at=fired_at,
        root_cause=root_cause,
        github_issue_url=issue_url,
    )

    # ── 8. Auto-remediation ─────────────────────────────────────────────────
    if auto_remediation_safe:
        logger.info("pipeline alert=%s step=remediation", alert_name)
        action, result = await attempt_remediation(
            alert_name=alert_name,
            service=service,
            namespace=namespace,
        )
    else:
        action = "skipped"
        result = "Claude assessed auto-remediation as unsafe for this alert type"
        logger.info(
            "pipeline alert=%s step=remediation action=skipped reason=claude_unsafe",
            alert_name,
        )

    # ── 9. Update remediation result ────────────────────────────────────────
    incident.remediation_action = action
    incident.remediation_result = result
    await db.commit()

    logger.info(
        "pipeline alert=%s step=done incident_id=%s issue=%s remediation=%s",
        alert_name,
        incident.id,
        issue_url,
        action,
    )


# ─── Security scan endpoints ───────────────────────────────────────────────────

@app.post("/security-scan", status_code=202)
async def security_scan(
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
) -> dict[str, str]:
    """Trigger a CryptoFlux security scan in the background.

    Scans the last 15 minutes of Loki logs for all CryptoFlux services.
    Each detected SecurityEvent is persisted, Slacked, and filed as a
    GitHub issue. Returns 202 immediately so the CronJob curl doesn't block.
    """
    logger.info("endpoint=/security-scan accepted")
    background_tasks.add_task(_run_security_scan, db)
    return {"status": "accepted"}


@app.get("/security-events", response_model=list[IncidentResponse])
async def list_security_events(db: AsyncSession = Depends(get_db)) -> list[Incident]:
    """Return the 50 most recent security-scan incidents, newest first."""
    logger.info("endpoint=/security-events")
    result = await db.execute(
        select(Incident)
        .where(Incident.alert_name.like("SecurityScan:%"))
        .order_by(desc(Incident.created_at))
        .limit(50)
    )
    return list(result.scalars().all())


# ─── Security pipeline ────────────────────────────────────────────────────────

async def _run_security_scan(db: AsyncSession) -> None:
    """Run the full security scan and process every detected event."""
    logger.info("security_scan step=start")
    try:
        events = await security_monitor.scan_all()
    except Exception as exc:
        logger.error("security_scan step=scan_all error=%s", exc)
        return

    for event in events:
        try:
            await _process_security_event(event, db)
        except Exception as exc:
            logger.error(
                "security_scan step=process_event type=%s error=%s",
                event.event_type, exc,
            )

    logger.info("security_scan step=done events_processed=%d", len(events))


async def _process_security_event(event: SecurityEvent, db: AsyncSession) -> None:
    """Persist a SecurityEvent to PostgreSQL, open a GitHub issue, and notify Slack.

    Steps mirror the regular alert pipeline but skip Claude analysis and
    auto-remediation — security events require human review.
    """
    now = datetime.now(tz=timezone.utc)

    logger.info(
        "security_event step=start type=%s severity=%s service=%s",
        event.event_type, event.severity, event.service,
    )

    # ── 0. Deduplication check (1-hour window) ───────────────────────────────
    cutoff = datetime.now(tz=timezone.utc).replace(tzinfo=None) - timedelta(hours=1)
    dup_result = await db.execute(
        select(func.count(Incident.id))
        .where(Incident.alert_name == event.event_type)
        .where(Incident.service == event.service)
        .where(Incident.created_at >= cutoff)
    )
    if dup_result.scalar() > 0:
        logger.info(
            "security_event deduplicated type=%s service=%s",
            event.event_type, event.service,
        )
        return

    # ── 1. Persist ──────────────────────────────────────────────────────────
    incident = Incident(
        alert_name=event.event_type,
        severity=event.severity,
        service=event.service,
        fired_at=now.replace(tzinfo=None),
        raw_alert={},
        logs_snapshot=event.evidence,
        claude_analysis="Security scan — no Claude analysis performed",
        root_cause=event.description,
        runbook=(
            "## Security Remediation\n\n"
            "1. Review the evidence logs attached to this incident.\n"
            "2. Identify the source IP and user account.\n"
            "3. Patch or remove the vulnerable endpoint.\n"
            "4. Rotate any exposed credentials.\n"
            "5. Verify no data exfiltration occurred."
        ),
    )
    db.add(incident)
    await db.commit()
    await db.refresh(incident)
    logger.info("security_event step=persisted incident_id=%s", incident.id)

    # ── 2. GitHub issue ─────────────────────────────────────────────────────
    issue_url = await open_issue(
        alert_name=event.event_type,
        severity=event.severity,
        service=event.service,
        fired_at=now,
        root_cause=event.description,
        runbook=incident.runbook,
        severity_assessment=f"Security event classified as {event.severity} by aiops-brain security scanner",
        logs_snapshot=event.evidence,
    )
    incident.github_issue_url = issue_url
    await db.commit()

    # ── 3. Slack notification ───────────────────────────────────────────────
    await notify_incident(
        alert_name=event.event_type,
        severity=event.severity,
        service=event.service,
        fired_at=now,
        root_cause=event.description,
        github_issue_url=issue_url,
    )

    logger.info(
        "security_event step=done type=%s incident_id=%s issue=%s",
        event.event_type, incident.id, issue_url,
    )
