"""Slack notification client using Block Kit.

Reads SLACK_WEBHOOK_URL from the environment. If the variable is absent or
empty the module initialises without error and every send call is a no-op,
so missing Slack config never crashes the pipeline.
"""

import logging
import os
from datetime import datetime

from slack_sdk.webhook import WebhookClient
from slack_sdk.errors import SlackApiError

logger = logging.getLogger(__name__)

_WEBHOOK_URL: str = os.environ.get("SLACK_WEBHOOK_URL", "")

_SEVERITY_EMOJI: dict[str, str] = {
    "critical": "🔴",
    "warning":  "🟡",
    "info":     "🔵",
}
_DEFAULT_EMOJI = "⚪"


def _emoji(severity: str) -> str:
    return _SEVERITY_EMOJI.get(severity.lower(), _DEFAULT_EMOJI)


def _build_blocks(
    alert_name: str,
    severity: str,
    service: str,
    fired_at: datetime,
    root_cause: str,
    github_issue_url: str | None,
) -> list[dict]:
    """Construct a Slack Block Kit payload for one incident."""
    fired_str = fired_at.strftime("%Y-%m-%d %H:%M:%S UTC")
    root_cause_excerpt = root_cause[:300] + ("…" if len(root_cause) > 300 else "")

    blocks: list[dict] = [
        # ── Header ────────────────────────────────────────────────────────────
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": f"{_emoji(severity)}  {alert_name}",
                "emoji": True,
            },
        },
        # ── Incident fields ───────────────────────────────────────────────────
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Service*\n`{service}`"},
                {"type": "mrkdwn", "text": f"*Severity*\n`{severity}`"},
                {"type": "mrkdwn", "text": f"*Fired At*\n{fired_str}"},
            ],
        },
        # ── Root cause excerpt ────────────────────────────────────────────────
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*Root Cause*\n{root_cause_excerpt}",
            },
        },
        {"type": "divider"},
    ]

    # ── GitHub issue button (only when an issue was created) ──────────────────
    if github_issue_url:
        blocks.append(
            {
                "type": "actions",
                "elements": [
                    {
                        "type": "button",
                        "text": {"type": "plain_text", "text": "View GitHub Issue", "emoji": True},
                        "url": github_issue_url,
                        "style": "primary",
                    }
                ],
            }
        )

    # ── Footer ────────────────────────────────────────────────────────────────
    blocks.append(
        {
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": "Responded by *aiops-brain* · powered by Claude AI",
                }
            ],
        }
    )

    return blocks


async def notify_incident(
    alert_name: str,
    severity: str,
    service: str,
    fired_at: datetime,
    root_cause: str,
    github_issue_url: str | None,
) -> None:
    """Send an incident notification to Slack.

    Silently skips if SLACK_WEBHOOK_URL is not configured.
    Logs a warning on delivery failure but never raises.
    """
    if not _WEBHOOK_URL:
        logger.debug("slack_notify skipped: SLACK_WEBHOOK_URL not configured")
        return

    blocks = _build_blocks(
        alert_name=alert_name,
        severity=severity,
        service=service,
        fired_at=fired_at,
        root_cause=root_cause,
        github_issue_url=github_issue_url,
    )

    try:
        client = WebhookClient(_WEBHOOK_URL)
        response = client.send(
            text=f"{_emoji(severity)} [{severity.upper()}] {alert_name} — {service}",
            blocks=blocks,
        )
        if response.status_code == 200:
            logger.info(
                "slack_notify alert=%s severity=%s status=sent", alert_name, severity
            )
        else:
            logger.warning(
                "slack_notify alert=%s status_code=%d body=%s",
                alert_name,
                response.status_code,
                response.body,
            )
    except SlackApiError as exc:
        logger.warning("slack_notify alert=%s error=%s", alert_name, exc)
    except Exception as exc:
        logger.warning("slack_notify alert=%s unexpected_error=%s", alert_name, exc)
