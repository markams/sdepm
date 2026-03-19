<h1>Security</h1>

## Authorization

### oAuth2

Adopted oAuth2 with JWT, which is the standard for trusted machine-to-machine (M2M) interaction.

https://datatracker.ietf.org/doc/html/rfc6749#section-4.4

### Smaller platforms

Smaller platforms can opt for delegating SDEP API-invocation to third-parties.

In such case, the platform arranges data submission with their party; the party becomes registered in SDEP.

## Audit log

To log "who did what, where, when, from where, and with what result", plus enough context to reconstruct important actions.

### Implementation approach

- **Middleware-based:** A Starlette `BaseHTTPMiddleware` intercepts every request/response cycle
- **Async background writes:** Audit records are written via `asyncio.create_task()` so they never block the response
- **Append-only:** The `audit_log` table is insert-only; no updates or deletes
- **Error-resilient:** Audit write failures are logged but never break the request

### Core audit fields

For each request that matters (auth, data change, sensitive read), capture:

| Field            | Source                                     | Description                                                      |
| :--------------- | :----------------------------------------- | :--------------------------------------------------------------- |
| **timestamp**    | Server clock                               | UTC, server default `now()`                                      |
| **requestId**    | Generated                                  | UUID4 correlation ID                                             |
| **clientId**     | JWT `client_id` claim                      | OAuth2 client identifier (nullable for unauthenticated requests) |
| **clientName**   | JWT `client_name` claim                    | Human-readable client name (nullable)                            |
| **roles**        | JWT `realm_access.roles`                   | Comma-separated role list (nullable)                             |
| **action**       | Derived from method + path                 | Semantic action name, e.g. `area.create`                         |
| **resourceType** | Derived from path                          | Entity type, e.g. `area`, `activity`                             |
| **resourceId**   | Extracted from path                        | Entity identifier (nullable for list/create operations)          |
| **httpMethod**   | Request                                    | HTTP method (`GET`, `POST`, `DELETE`)                            |
| **path**         | Request                                    | Request path, e.g. `/api/v0/ca/areas`                            |
| **queryParams**  | Request                                    | Query string (nullable)                                          |
| **statusCode**   | Response                                   | HTTP status code                                                 |
| **success**      | Derived from statusCode                    | `true` if statusCode < 400                                       |
| **clientIp**     | `X-Forwarded-For` or `request.client.host` | Client IP address                                                |
| **userAgent**    | `User-Agent` header                        | Client user agent string                                         |
| **durationMs**   | Calculated                                 | Request processing time in milliseconds                          |

### Action mapping

The middleware derives a semantic action and resource type from the HTTP method and request path:

| Method | Path pattern             | Action            | Resource type |
| :----- | :----------------------- | :---------------- | :------------ |
| POST   | `/*/ca/areas`            | `area.create`     | `area`        |
| GET    | `/*/ca/areas`            | `area.list`       | `area`        |
| GET    | `/*/ca/areas/count`      | `area.count`      | `area`        |
| GET    | `/*/ca/areas/{id}`       | `area.read`       | `area`        |
| DELETE | `/*/ca/areas/{id}`       | `area.delete`     | `area`        |
| POST   | `/*/str/activities`      | `activity.create` | `activity`    |
| GET    | `/*/str/areas`           | `area.list`       | `area`        |
| GET    | `/*/str/areas/count`     | `area.count`      | `area`        |
| GET    | `/*/str/areas/{id}`      | `area.read`       | `area`        |
| GET    | `/*/ca/activities`       | `activity.list`   | `activity`    |
| GET    | `/*/ca/activities/count` | `activity.count`  | `activity`    |
| POST   | `/*/auth/token`          | `auth.token`      | `auth`        |
| GET    | `/*/ping`                | `system.ping`     | `system`      |

Unmatched paths fall back to `{method}.unknown`.

### Skip list

The following paths are **not** audited (high-frequency, low-value):

- `/` (root)
- `/api/health`
- `/api/v0/openapi.json`
- `/api/v0/docs`
- `/api/v0/redoc`

### Payload and parameter logging

Be careful but intentional about request/response details:

- Log non-sensitive parameters (ids, filters, pagination, flags)
- For bodies, either:
  - log only allowlisted fields (e.g. `old_email`, `new_email`), or
  - store a hash/summary instead of raw data
- Never log secrets: passwords, tokens, full credit cards, full personal IDs
- For sensitive reads, log "which record was read by whom" without dumping the content

Example record (JSON):

```json
{
  "timestamp": "2026-03-17T06:52:01Z",
  "request_id": "b3f7a1c2-...",
  "client_id": "gemeente-amsterdam",
  "client_name": "Gemeente Amsterdam",
  "roles": "competent-authority",
  "action": "area.create",
  "resource_type": "area",
  "resource_id": null,
  "http_method": "POST",
  "path": "/api/v0/ca/areas",
  "status_code": 201,
  "success": true,
  "client_ip": "203.0.113.10",
  "user_agent": "python-httpx/0.27.0",
  "duration_ms": 42
}
```

### Retention

Expired audit log rows are automatically deleted by a background task that runs every hour. The retention period is configurable via the `AUDITLOG_RETENTION` environment variable (default: **1 day**). Deletion is batched (1.000 rows per batch) to avoid long-running transactions.

The retention logic in `audit_retention.py` is split into two functions with distinct responsibilities:

| Function                                                   | Responsibility                                                                                                                                                                                                                                                               | Invocation                                                                                                                                                                                                  |
| :--------------------------------------------------------- | :--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `delete_old_audit_logs(retention_days)`                    | **One-shot deletion.** Deletes all audit log rows older than `retention_days` in batches of 1.000. Returns the total number of deleted rows. This is a pure async function that runs to completion and then returns — it does not loop or sleep.                             | Called by `audit_log_cleanup_loop` on each cycle. Can also be called standalone in scripts, tests, or one-off maintenance tasks.                                                                            |
| `audit_log_cleanup_loop(retention_days, interval_seconds)` | **Infinite scheduling loop.** Calls `delete_old_audit_logs` once, then sleeps for `interval_seconds` (default 3.600 s = 1 hour), and repeats indefinitely until the task is cancelled. Catches and logs any exceptions so that a single failed cycle does not kill the loop. | Created as an `asyncio.Task` inside the FastAPI `lifespan` context manager in `main.py`. The task starts when the application boots and is cancelled (via `task.cancel()`) when the application shuts down. |

In short: `delete_old_audit_logs` does the actual work; `audit_log_cleanup_loop` is the scheduler that ensures that work runs repeatedly for the lifetime of the application.

### Roadmap

- Restricted RBAC for viewing audit logs (admin-only API endpoint)
- Role/permissions audit: log which permissions were evaluated
- Hash/sign the audit streams for tamper detection
- Structured log forwarding to SIEM (e.g. ELK, Splunk)
