"""Security utilities and middleware.

This module provides:
- Bearer token authentication (JWT validation)
- Security headers middleware for OWASP compliance
- Audit log middleware for request tracking
"""

# Import audit log middleware
from app.security.audit import AuditLogMiddleware

# Import bearer token authentication for backwards compatibility
from app.security.bearer import (
    create_verify_bearer_token,
    get_keycloak_public_key,
    oauth2_scheme,
    validate_jwt_token,
    verify_bearer_token,
)

# Import security headers middleware
from app.security.headers import (
    ApiSecurityHeadersMiddleware,
    SecurityHeadersMiddleware,
)

__all__ = [
    "ApiSecurityHeadersMiddleware",
    "AuditLogMiddleware",
    "SecurityHeadersMiddleware",
    "create_verify_bearer_token",
    "get_keycloak_public_key",
    "oauth2_scheme",
    "validate_jwt_token",
    "verify_bearer_token",
]
