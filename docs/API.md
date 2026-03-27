<h1>API</h1>

In general, **keep the API as simple and concise as possible**.

*REST APIs are one of the most common kinds of web interfaces available today. Therefore, it's very important to design REST APIs properly so that we won't run into problems down the road.*

*Otherwise, we create problems for clients that use our APIs, which isn’t pleasant and detracts people from using our API.*

*If we don’t follow commonly accepted conventions, then we confuse the maintainers of the API and the clients that use them since it’s different from what everyone expects.*

https://stackoverflow.blog/2020/03/02/best-practices-for-rest-api-design/

---

## Patterns

| #                | Decision                                           | Motivation/example                                                                                                            |
| :--------------- | :------------------------------------------------- | :---------------------------------------------------------------------------------------------------------------------------- |
| **API&nbsp;01**  | Support OpenAPI 3.1.0                              | Swagger 2.0 is legacy - https://swagger.io/specification/                                                                     |
| **API&nbsp;02**  | All endpoints are self-explanatory/well-documented |                                                                                                                               |
| **API&nbsp;03**  | Use nouns instead of verbs                         | Best practice - https://logius-standaarden.github.io/API-Design-Rules/                                                        |
| **API&nbsp;04**  | Use plurals for resources that affect collections  | Best practice - https://logius-standaarden.github.io/API-Design-Rules/                                                        |
| **API&nbsp;05**  | Consistent datamodel                               | Avoid code duplication, only have `Activity`, `Area`, consider adding an attribute to indicate "non-reporting records" for CA |
| **API&nbsp;06**  | Consistent endpoints                               | Have POST/GET "mirrors": `POST /ca/areas`, `GET /str/areas`; `POST /str/activities`, `GET /ca/activities`                     |
| **API&nbsp;07**  | Consistent pagination                              | Have `offset` and `limit` for all endpoints with (potential) many records                                                     |
| **API&nbsp;08**  | Syntax validation                                  | Example: `postal code`                                                                                                        |
| **API&nbsp;09**  | Semantical validation                              | Example: `begin timestamp < end timestamp`                                                                                    |
| **API&nbsp;10**  | Integrity validation                               | Example: can only submit activities for existing areas                                                                        |
| **API&nbsp;11**  | Single record POST (default)                       | To avoid transaction performance issues and to keep the endpoints simple (as opposed to bulk updates)                         |
| **API&nbsp;11b** | Bulk POST (complement)                             | For high-volume STR platforms; available at `/str/activities/bulk` — see [Bulk endpoint](#bulk-endpoint) below                |
| **API&nbsp;12**  | Logical ordering => readability                    | For POST, request and response follow the same ordering, extra data in response is moved to the end                           |
| **API&nbsp;13**  | Essentiality                                       | Example: in POST activities, only `areaId` and `competentAuthorityId`, but no `competentAuthorityName`                        |
| **API&nbsp;14**  | Essentiality/security                              | Example: in POST activities request, no need to include `platformId`                                                          |
| **API&nbsp;15**  | Consistent HTTP response codes                     | See [HTTP status codes](#http-status-codes) below                                                                             |
| **API&nbsp;16**  | STR and CA: manage area change                     | Areas may change over time, SDEP only administrates the changes and exposes the latest "truth"                                |

---

## HTTP status codes

### Success

| HTTP Status | Meaning    | When                                                               |
| ----------- | ---------- | ------------------------------------------------------------------ |
| 200         | OK         | GET request completed successfully; bulk POST with partial success |
| 201         | Created    | POST request created a new resource                                |
| 204         | No Content | DELETE request completed successfully (e.g. deactivate area)       |

### Client errors

| HTTP Status | Meaning               | When                                                                                                                          |
| ----------- | --------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| 400         | Bad Request           | Invalid query parameters on a GET request (e.g. `offset=-1` or `limit=abc`), or missing client credentials                    |
| 401         | Unauthorized          | Missing, invalid, or expired authentication token; missing required token claims (`client_id`, `client_name`)                 |
| 403         | Forbidden             | Authenticated but missing a required role (`sdep_ca`, `sdep_str`, `sdep_read`, `sdep_write`)                                  |
| 404         | Not Found             | Requested resource does not exist, is unavailable, or has been deleted                                                        |
| 409         | Conflict              | Duplicate resource (unique constraint violation)                                                                              |
| 422         | Unprocessable Content | Invalid request body on a POST request (e.g. missing required field), or business rule violation (e.g. start time > end time) |

### Server errors

| HTTP Status | Meaning               | When                                                                   |
| ----------- | --------------------- | ---------------------------------------------------------------------- |
| 500         | Internal Server Error | Unexpected condition that prevented fulfilling the request (catch-all) |
| 503         | Service Unavailable   | Database or authorization server (Keycloak) temporarily unavailable    |

For the mapping between application exceptions and HTTP status codes, see [Exception Handling](ARCHITECTURE_TECH.md#exception-handling) in the Architecture document.

---

## Bulk endpoint

### Motivation

At high volumes (500K–4M records/day, ~6–46 records/second average), PostgreSQL is not the bottleneck — a standard Postgres instance can process thousands of transactions per second. The actual bottlenecks are:

1. **Network latency** — solved by batching 500–1000 items per API call
2. **Disk I/O (WAL pressure)** — solved by multi-row `INSERT ... VALUES` instead of individual inserts

The single-record `POST /str/activities` (API 11) remains the default. The bulk endpoint `POST /str/activities/bulk` (API 11b) is a complement for high-volume STR platforms.

### Why Application-First Validation?

Instead of having the database check each record via savepoints, errors are caught in the application layer:

- Application-level Pydantic validation is **many times faster** than database savepoints
- **Horizontally scalable**: add more API nodes under load
- **Single reference query per batch** (not per record)
- Only "clean" (validated) data reaches the database
-  No savepoints or nested transactions needed, which avoids the overhead of extra database round-trips.

### Validation flow (4 steps)

| Step                               | What                                                                                                                          | How                                                       |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------- |
| **1. Pydantic Check**              | Validate each item individually against the ActivityRequest schema. Mark failed items as NOK with the error reason.           | `TypeAdapter(ActivityRequest).validate_python()` per item |
| **2. Referential Integrity Check** | Fetch all referenced area IDs in a single query. Store in a Python `dict` for O(1) lookup. Items with unknown `areaId` → NOK. | `SELECT area_id, id FROM area WHERE area_id IN (...)`     |
| **3. Bulk Insert**                 | Insert all remaining OK records in a single database operation.                                                               | `session.execute(insert(Activity), list_of_valid_dicts)`  |
| **4. Feedback**                    | Return per-item OK/NOK response preserving original order, enriched with `status` and `errorMessage`.                         | JSON response with summary counts                         |

### HTTP status codes (bulk-specific)

| HTTP Status                   | When                                                                |
| ----------------------------- | ------------------------------------------------------------------- |
| **201 Created**               | All items created successfully (`failed == 0`)                      |
| **200 OK**                    | Partial success: some OK, some NOK (`succeeded > 0 AND failed > 0`) |
| **422 Unprocessable Content** | All items failed validation (`succeeded == 0`)                      |

### Design decisions

| #      | Decision                                                                                                                                                                                                          | Rationale                                                                                                                                                      |
| ------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **D1** | **Per-item Pydantic validation** — the request accepts raw dicts, each validated individually in the service layer                                                                                                | One invalid item should not block the other (999) items in the batch. If one item has a missing field, the rest are still processed.                             |
| **D2** | **Intra-batch duplicates: last-wins** — when the same `activityId` appears multiple times in a single batch, only the last occurrence is processed; earlier occurrences receive NOK                               | Deterministic and predictable for clients. Avoids ambiguity about which version "wins".                                                                        |
| **D3** | **Versioning: batch UPDATE before INSERT** — existing current versions in the database are marked as ended via a single batch `UPDATE ... WHERE activity_id IN (...)` before the bulk INSERT creates new versions | Consistent with single-endpoint versioning semantics, but uses batch operations (1 UPDATE + 1 INSERT) instead of per-item queries.                             |
| **D4** | **Platform resolution: version only on name change** — platform is resolved once per batch; a new version is only created if the JWT claim (`client_name`) has changed                                            | Avoids unnecessary versioning churn when the same platform submits many batches with unchanged credentials.                                                    |
| **D5** | **Deactivated entities rejected** — if an `activityId` has been deactivated (all versions have `endedAt` set), submitting it again is rejected (NOK)                                                              | Prevents "resurrecting" soft-deleted entities. Consistent with single endpoint behavior.                                                                       |
| **D6** | **No `ON CONFLICT DO NOTHING`** — SDEP uses explicit versioning (mark-as-ended + new insert) instead of database-level upsert                                                                                     | `ON CONFLICT DO NOTHING` is a general best practice for idempotency in bulk inserts. However, SDEP's data model requires explicit versioning with `endedAt` timestamps. |
| **D7** | **Single transaction scope** — the entire bulk operation runs in a single transaction; if the bulk INSERT fails, all changes roll back                                                                            | No partial database state. Consistent with the single endpoint's `get_async_db` auto-commit/rollback model.                                                    |
| **D8** | **SQLite compatibility** — the bulk INSERT and all queries work on both PostgreSQL and SQLite                                                                                                                     | Unit tests run on SQLite in-memory without requiring PostgreSQL. The `StringArray` TypeDecorator handles dialect differences.                                  |
