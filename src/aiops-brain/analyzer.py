"""Claude API integration for alert analysis and runbook generation.

Sends the Alertmanager alert metadata plus the raw Loki logs to Claude and
parses the structured response into discrete fields used to populate the
incidents table.
"""

import logging
import os
from dataclasses import dataclass

import anthropic

logger = logging.getLogger(__name__)

_MODEL = "claude-sonnet-4-20250514"
_MAX_TOKENS = 4096

_client = anthropic.Anthropic(api_key=os.environ["CLAUDE_API_KEY"])


@dataclass
class AnalysisResult:
    """Structured output from the Claude API call."""

    root_cause: str
    severity_assessment: str
    runbook: str
    auto_remediation_safe: bool
    full_response: str


_SYSTEM_PROMPT = """\
You are an expert SRE (Site Reliability Engineer) and incident responder.
You receive Kubernetes / infrastructure alerts along with the recent log output
from the affected service. Your job is to perform a thorough root-cause analysis
and produce a clear, actionable remediation runbook.

Always respond in the following exact structure (use these exact section headers):

## Root Cause
<concise root-cause explanation — 1-3 sentences>

## Severity Assessment
<severity level (Critical / High / Medium / Low) and brief justification>

## Remediation Runbook
<numbered, step-by-step remediation instructions that an on-call engineer can follow>

## Auto-Remediation Safe
<answer ONLY "yes" or "no" — "yes" means restarting the affected pod or scaling
the deployment would resolve the issue without risk of data loss or cascading failures>
"""


def _build_user_message(
    alert_name: str,
    severity: str,
    service: str,
    labels: dict,
    annotations: dict,
    logs: str,
) -> str:
    label_lines = "\n".join(f"  {k}: {v}" for k, v in labels.items())
    annotation_lines = "\n".join(f"  {k}: {v}" for k, v in annotations.items())
    return f"""\
## Alert Details
- **Alert Name**: {alert_name}
- **Reported Severity**: {severity}
- **Affected Service**: {service}

### Labels
{label_lines or "  (none)"}

### Annotations
{annotation_lines or "  (none)"}

## Recent Logs (last 10 minutes)
```
{logs}
```

Please analyse this incident and respond using the required structure.
"""


async def analyse_alert(
    alert_name: str,
    severity: str,
    service: str,
    labels: dict,
    annotations: dict,
    logs: str,
) -> AnalysisResult:
    """Call Claude API and return a parsed AnalysisResult.

    This is a synchronous Anthropic SDK call wrapped in an async function for
    compatibility with the FastAPI event loop (the SDK does not yet ship an
    async client in all versions, so we call it directly — acceptable for
    low-throughput webhook traffic).
    """
    user_message = _build_user_message(
        alert_name, severity, service, labels, annotations, logs
    )

    logger.info("claude_api alert_name=%s model=%s", alert_name, _MODEL)

    message = _client.messages.create(
        model=_MODEL,
        max_tokens=_MAX_TOKENS,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_message}],
    )

    full_response: str = message.content[0].text
    logger.info(
        "claude_api alert_name=%s input_tokens=%d output_tokens=%d",
        alert_name,
        message.usage.input_tokens,
        message.usage.output_tokens,
    )

    return AnalysisResult(
        root_cause=_extract_section(full_response, "Root Cause"),
        severity_assessment=_extract_section(full_response, "Severity Assessment"),
        runbook=_extract_section(full_response, "Remediation Runbook"),
        auto_remediation_safe=_parse_auto_remediation(full_response),
        full_response=full_response,
    )


def _extract_section(text: str, header: str) -> str:
    """Extract the body of a markdown ## Header section."""
    marker = f"## {header}"
    start = text.find(marker)
    if start == -1:
        return f"[{header} section not found in Claude response]"

    content_start = start + len(marker)
    # Find the next ## heading or end of string
    next_header = text.find("\n## ", content_start)
    raw = text[content_start: next_header if next_header != -1 else len(text)]
    return raw.strip()


def _parse_auto_remediation(text: str) -> bool:
    """Return True only when Claude explicitly answers 'yes' in the safe section."""
    section = _extract_section(text, "Auto-Remediation Safe").lower()
    return section.startswith("yes")
