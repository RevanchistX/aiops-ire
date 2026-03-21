"""SQLAlchemy ORM model for the incidents table.

Schema mirrors the canonical definition in CLAUDE.md exactly.
"""

import uuid
from datetime import datetime
from typing import Any

from sqlalchemy import VARCHAR, TEXT, TIMESTAMP, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from database import Base


class Incident(Base):
    """Persisted record for every alert that passes through the aiops-brain."""

    __tablename__ = "incidents"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    alert_name: Mapped[str] = mapped_column(VARCHAR, nullable=False)
    severity: Mapped[str] = mapped_column(VARCHAR, nullable=False)
    service: Mapped[str] = mapped_column(VARCHAR, nullable=False)
    fired_at: Mapped[datetime] = mapped_column(TIMESTAMP, nullable=False)
    resolved_at: Mapped[datetime | None] = mapped_column(TIMESTAMP, nullable=True)

    # Raw Alertmanager payload stored as JSONB for ad-hoc querying
    raw_alert: Mapped[dict[str, Any]] = mapped_column(JSONB, nullable=False)

    logs_snapshot: Mapped[str] = mapped_column(TEXT, nullable=False)
    claude_analysis: Mapped[str] = mapped_column(TEXT, nullable=False)
    root_cause: Mapped[str] = mapped_column(TEXT, nullable=False)
    runbook: Mapped[str] = mapped_column(TEXT, nullable=False)

    github_issue_url: Mapped[str | None] = mapped_column(VARCHAR, nullable=True)
    remediation_action: Mapped[str | None] = mapped_column(VARCHAR, nullable=True)
    remediation_result: Mapped[str | None] = mapped_column(VARCHAR, nullable=True)

    created_at: Mapped[datetime] = mapped_column(
        TIMESTAMP,
        server_default=func.now(),
        nullable=False,
    )
