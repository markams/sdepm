"""Automated audit log retention cleanup."""

import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, select

from app.db.config import create_async_session
from app.models.audit_log import AuditLog

logger = logging.getLogger(__name__)

BATCH_SIZE = 1000


async def delete_old_audit_logs(retention_days: int) -> int:
    """Delete audit log rows older than *retention_days*. Returns total rows deleted."""
    cutoff = datetime.now(UTC) - timedelta(days=retention_days)
    total_deleted = 0

    while True:
        async with create_async_session() as session, session.begin():
            # Subquery to find a batch of expired row IDs
            subq = (
                select(AuditLog.id).where(AuditLog.timestamp < cutoff).limit(BATCH_SIZE)
            )
            result = await session.execute(
                delete(AuditLog).where(AuditLog.id.in_(subq))
            )
            deleted = result.rowcount
            total_deleted += deleted

        if deleted < BATCH_SIZE:
            break

    return total_deleted


async def audit_log_cleanup_loop(
    retention_days: int, interval_seconds: float = 3600.0
) -> None:
    """Periodically delete expired audit log rows. Runs until cancelled."""
    while True:
        try:
            deleted = await delete_old_audit_logs(retention_days)
            if deleted:
                logger.info("Audit log cleanup: deleted %d expired rows", deleted)
        except Exception:
            logger.exception("Audit log cleanup cycle failed")

        await asyncio.sleep(interval_seconds)
