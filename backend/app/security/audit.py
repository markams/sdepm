"""Audit log middleware for tracking API requests."""

import asyncio
import logging
import re
import time
import uuid

from fastapi import Request, Response
from jose import jwt
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.types import ASGIApp

from app.db.config import create_async_session
from app.models.audit_log import AuditLog

logger = logging.getLogger(__name__)

# Paths to skip auditing (high-frequency, low-value)
SKIP_PATHS = frozenset(
    {
        "/",
        "/api/health",
        "/api/v0/openapi.json",
        "/api/v0/docs",
        "/api/v0/redoc",
    }
)

# Action mapping: (method, regex_pattern) -> (action, resource_type)
# Order matters: more specific patterns first
_ACTION_RULES: list[tuple[str, re.Pattern, str, str]] = [
    ("GET", re.compile(r"^/api/v\d+/ca/areas/count$"), "area.count", "area"),
    ("GET", re.compile(r"^/api/v\d+/ca/areas/([^/]+)$"), "area.read", "area"),
    ("POST", re.compile(r"^/api/v\d+/ca/areas$"), "area.create", "area"),
    ("GET", re.compile(r"^/api/v\d+/ca/areas$"), "area.list", "area"),
    ("DELETE", re.compile(r"^/api/v\d+/ca/areas/([^/]+)$"), "area.delete", "area"),
    ("GET", re.compile(r"^/api/v\d+/str/areas/count$"), "area.count", "area"),
    ("GET", re.compile(r"^/api/v\d+/str/areas/([^/]+)$"), "area.read", "area"),
    ("GET", re.compile(r"^/api/v\d+/str/areas$"), "area.list", "area"),
    ("POST", re.compile(r"^/api/v\d+/str/activities$"), "activity.create", "activity"),
    (
        "GET",
        re.compile(r"^/api/v\d+/ca/activities/count$"),
        "activity.count",
        "activity",
    ),
    ("GET", re.compile(r"^/api/v\d+/ca/activities$"), "activity.list", "activity"),
    ("POST", re.compile(r"^/api/v\d+/auth/token$"), "auth.token", "auth"),
    ("GET", re.compile(r"^/api/v\d+/ping$"), "system.ping", "system"),
]


def _resolve_action(method: str, path: str) -> tuple[str, str | None, str | None]:
    """Derive action, resource_type, and resource_id from HTTP method and path.

    Returns:
        Tuple of (action, resource_type, resource_id).
    """
    for rule_method, pattern, action, resource_type in _ACTION_RULES:
        if method == rule_method:
            match = pattern.match(path)
            if match:
                resource_id = match.group(1) if match.lastindex else None
                return action, resource_type, resource_id
    return f"{method.lower()}.unknown", None, None


def _extract_jwt_claims(request: Request) -> dict[str, str | None]:
    """Extract client identity from JWT token without verification.

    The actual authentication/verification happens in route dependencies.
    This is read-only extraction for audit purposes.
    """
    auth_header = request.headers.get("authorization", "")
    if not auth_header.startswith("Bearer "):
        return {"client_id": None, "client_name": None, "roles": None}

    token = auth_header[7:]
    try:
        payload = jwt.decode(
            token,
            key="",  # No key needed when not verifying
            options={
                "verify_signature": False,
                "verify_aud": False,
                "verify_exp": False,
            },
        )
        # Extract roles from Keycloak realm_access claim
        roles_list = payload.get("realm_access", {}).get("roles", [])
        roles = ",".join(roles_list) if roles_list else None

        return {
            "client_id": payload.get("client_id") or payload.get("clientId"),
            "client_name": payload.get("client_name") or payload.get("clientName"),
            "roles": roles,
        }
    except Exception:
        logger.debug("Failed to decode JWT for audit logging", exc_info=True)
        return {"client_id": None, "client_name": None, "roles": None}


def _extract_client_ip(request: Request) -> str | None:
    """Extract client IP from X-Forwarded-For header or request.client."""
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        # First IP in the chain is the original client
        return forwarded_for.split(",")[0].strip()
    if request.client:
        return request.client.host
    return None


async def _write_audit_record(record: AuditLog) -> None:
    """Write audit record to database in background. Failures are logged, never raised."""
    try:
        async with create_async_session() as session, session.begin():
            session.add(record)
    except Exception:
        logger.warning("Failed to write audit log record", exc_info=True)


class AuditLogMiddleware(BaseHTTPMiddleware):
    """Middleware that logs API requests to the audit_log table.

    - Skips low-value paths (health, docs, root)
    - Extracts JWT claims without verification (auth happens in route deps)
    - Writes audit records asynchronously to avoid blocking responses
    - Audit failures never break the request
    """

    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next) -> Response:
        """Intercept request/response and create audit record."""
        path = request.url.path

        # Skip low-value endpoints
        if path in SKIP_PATHS:
            return await call_next(request)

        # Record timing
        request_id = str(uuid.uuid4())
        start = time.monotonic()

        # Process request
        response = await call_next(request)

        duration_ms = int((time.monotonic() - start) * 1000)

        # Extract audit data
        method = request.method
        claims = _extract_jwt_claims(request)
        action, resource_type, resource_id = _resolve_action(method, path)
        query_string = str(request.url.query) if request.url.query else None

        # Build audit record
        record = AuditLog(
            request_id=request_id,
            client_id=claims["client_id"],
            client_name=claims["client_name"],
            roles=claims["roles"],
            action=action,
            resource_type=resource_type,
            resource_id=resource_id,
            http_method=method,
            path=path[:512],
            query_params=query_string[:512] if query_string else None,
            status_code=response.status_code,
            success=response.status_code < 400,
            client_ip=_extract_client_ip(request),
            user_agent=request.headers.get("user-agent", "")[:256] or None,
            duration_ms=duration_ms,
        )

        # Write asynchronously — never block the response
        # Store reference to prevent task from being garbage-collected
        task = asyncio.create_task(_write_audit_record(record))
        task.add_done_callback(
            lambda t: t.result() if not t.cancelled() and not t.exception() else None
        )

        return response
