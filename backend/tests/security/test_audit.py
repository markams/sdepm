"""Tests for audit log middleware."""

import asyncio
from unittest.mock import AsyncMock, patch

import pytest
from app.main import app
from app.security.audit import SKIP_PATHS, _resolve_action
from httpx import ASGITransport, AsyncClient
from jose import jwt


def _make_jwt(claims: dict) -> str:
    """Create an unsigned JWT for testing."""
    return jwt.encode(claims, key="test-secret", algorithm="HS256")


@pytest.mark.asyncio
class TestActionMapping:
    """Test action resolution from HTTP method + path."""

    @pytest.mark.parametrize(
        "method, path, expected_action, expected_type, expected_id",
        [
            ("POST", "/api/v0/ca/areas", "area.create", "area", None),
            ("GET", "/api/v0/ca/areas", "area.list", "area", None),
            ("GET", "/api/v0/ca/areas/count", "area.count", "area", None),
            ("GET", "/api/v0/ca/areas/abc-123", "area.read", "area", "abc-123"),
            ("DELETE", "/api/v0/ca/areas/abc-123", "area.delete", "area", "abc-123"),
            ("POST", "/api/v0/str/activities", "activity.create", "activity", None),
            ("GET", "/api/v0/str/areas", "area.list", "area", None),
            ("GET", "/api/v0/str/areas/count", "area.count", "area", None),
            ("GET", "/api/v0/str/areas/xyz-456", "area.read", "area", "xyz-456"),
            ("GET", "/api/v0/ca/activities", "activity.list", "activity", None),
            ("GET", "/api/v0/ca/activities/count", "activity.count", "activity", None),
            ("POST", "/api/v0/auth/token", "auth.token", "auth", None),
            ("GET", "/api/v0/ping", "system.ping", "system", None),
        ],
    )
    async def test_action_mapping(
        self, method, path, expected_action, expected_type, expected_id
    ):
        """Test that all endpoint→action mappings produce correct results."""
        action, resource_type, resource_id = _resolve_action(method, path)
        assert action == expected_action
        assert resource_type == expected_type
        assert resource_id == expected_id

    async def test_unknown_path_fallback(self):
        """Test that unmatched paths fall back to {method}.unknown."""
        action, resource_type, resource_id = _resolve_action("GET", "/api/v0/unknown")
        assert action == "get.unknown"
        assert resource_type is None
        assert resource_id is None

    async def test_version_agnostic(self):
        """Test that action mapping works for any API version."""
        action, resource_type, _ = _resolve_action("POST", "/api/v1/ca/areas")
        assert action == "area.create"
        assert resource_type == "area"


@pytest.mark.asyncio
class TestAuditMiddleware:
    """Test audit log middleware integration."""

    async def test_audit_record_created_for_business_endpoint(self):
        """Test that audit record is created for business endpoints."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                response = await client.get("/api/v0/ping")
                # Allow background task to execute
                await asyncio.sleep(0.1)

                mock_write.assert_called_once()
                record = mock_write.call_args[0][0]
                assert record.action == "system.ping"
                assert record.http_method == "GET"
                assert record.path == "/api/v0/ping"
                assert record.status_code == response.status_code
                assert record.request_id is not None
                assert record.duration_ms is not None

    async def test_audit_skipped_for_health_endpoint(self):
        """Test that audit is skipped for health/docs endpoints."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get("/api/health")
                await asyncio.sleep(0.1)
                mock_write.assert_not_called()

    async def test_audit_skipped_for_root(self):
        """Test that audit is skipped for root endpoint."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get("/")
                await asyncio.sleep(0.1)
                mock_write.assert_not_called()

    async def test_audit_skipped_for_openapi(self):
        """Test that audit is skipped for OpenAPI docs endpoint."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get("/api/v0/openapi.json")
                await asyncio.sleep(0.1)
                mock_write.assert_not_called()

    async def test_client_id_extracted_from_jwt(self):
        """Test that client_id is extracted from JWT token."""
        token = _make_jwt(
            {
                "client_id": "gemeente-amsterdam",
                "client_name": "Gemeente Amsterdam",
                "realm_access": {"roles": ["competent-authority"]},
            }
        )
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get(
                    "/api/v0/ping",
                    headers={"Authorization": f"Bearer {token}"},
                )
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert record.client_id == "gemeente-amsterdam"
                assert record.client_name == "Gemeente Amsterdam"
                assert record.roles == "competent-authority"

    async def test_unauthenticated_request_logged_with_null_client(self):
        """Test that unauthenticated requests are logged with client_id=None."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get("/api/v0/ping")
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert record.client_id is None
                assert record.client_name is None
                assert record.roles is None

    async def test_failure_status_logged_with_success_false(self):
        """Test that failure status codes are logged with success=False."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                # Hit a protected endpoint without auth → expect 401
                await client.get("/api/v0/ca/areas")
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert record.status_code >= 400
                assert record.success is False

    async def test_audit_write_failure_does_not_break_request(self):
        """Test that audit write failure doesn't break the request."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record",
                side_effect=Exception("DB connection failed"),
            ):
                # Request should still succeed despite audit failure
                response = await client.get("/api/v0/ping")
                assert response.status_code in (200, 401)

    async def test_skip_paths_are_complete(self):
        """Test that skip paths match the documented set."""
        expected = {
            "/",
            "/api/health",
            "/api/v0/openapi.json",
            "/api/v0/docs",
            "/api/v0/redoc",
        }
        assert expected == SKIP_PATHS

    async def test_client_ip_from_x_forwarded_for(self):
        """Test that client IP is extracted from X-Forwarded-For header."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get(
                    "/api/v0/ping",
                    headers={"X-Forwarded-For": "203.0.113.10, 10.0.0.1"},
                )
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert record.client_ip == "203.0.113.10"

    async def test_user_agent_captured(self):
        """Test that user agent is captured in audit record."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get(
                    "/api/v0/ping",
                    headers={"User-Agent": "test-agent/1.0"},
                )
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert record.user_agent == "test-agent/1.0"

    async def test_query_params_captured(self):
        """Test that query parameters are captured in audit record."""
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            with patch(
                "app.security.audit._write_audit_record", new_callable=AsyncMock
            ) as mock_write:
                await client.get("/api/v0/ping?foo=bar&baz=1")
                await asyncio.sleep(0.1)

                record = mock_write.call_args[0][0]
                assert "foo=bar" in record.query_params
