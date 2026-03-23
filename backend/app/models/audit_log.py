"""Audit log model."""

from datetime import datetime

from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from app.db.config import Base


class AuditLog(Base):
    """Append-only audit log for API requests.

    Tracks "who did what, when, and with what result" for
    compliance, security monitoring, and operational accountability.
    """

    __tablename__ = "audit_log"

    # Primary key
    id: Mapped[int] = mapped_column(primary_key=True)

    # Timestamp
    timestamp: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now(), index=True
    )

    # Request correlation
    request_id: Mapped[str] = mapped_column(String(64), nullable=False, index=True)

    # Actor identity (from JWT claims)
    roles: Mapped[str | None] = mapped_column(String(256), nullable=True)

    # Semantic action
    resource_type: Mapped[str | None] = mapped_column(String(32), nullable=True)
    action: Mapped[str] = mapped_column(String(64), nullable=False)

    # HTTP request details
    http_method: Mapped[str] = mapped_column(String(10), nullable=False)
    path: Mapped[str] = mapped_column(String(512), nullable=False)

    # Response details
    http_status_code: Mapped[int] = mapped_column(Integer, nullable=False)
    status_code: Mapped[str] = mapped_column(String(3), nullable=False)

    # Performance
    duration_ms: Mapped[int | None] = mapped_column(Integer, nullable=True)

    def __repr__(self) -> str:
        """String representation of AuditLog."""
        return f"<AuditLog(id={self.id}, action='{self.action}')>"
