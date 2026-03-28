<h1>Performance Tests</h1>

The [../tests/perf](../tests/perf) directory contains a [Locust](https://locust.io/) test for load testing the SDEP bulk activity endpoint (`POST /str/activities/bulk`).

## Running Performance Tests

See [../Makefile](../Makefile). The Makefile delegates to [../scripts/run-tests-perf.sh](../scripts/run-tests-perf.sh).

Quick reference:

| Target           | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `make test-perf` | Run bulk performance test with various configuration options |

To run against a Kubernetes environment (TST, ACC, PRE, PRD), use the equivalent targets in `sdep-deployment` (e.g. `make test-perf-tst`).

## Implementation

`perf/locustfile.py`

**Purpose:** Load test the bulk activity endpoint (`POST /str/activities/bulk`) to measure throughput and validate capacity.

**Tooling:** [Locust](https://locust.io/) (Python-based load testing), installed on-demand via `uvx`.

**Design:**
- Authenticates via OAuth2 client credentials (same flow as integration tests)
- Generates realistic activity payloads with randomized addresses, guest counts, and country codes
- Submits batches via `POST /str/activities/bulk` at maximum throughput
- Collects per-request success/failure counts from the bulk response body
- Prints a summary with total activities, throughput (activities/sec), extrapolated capacity (activities/day), and comparison against the configured target

**How it works:**
1. Makefile creates fixture areas via `lib/create_fixture_areas.sh` (5 areas with `sdep-test-perf-*` IDs)
2. Spawns `PERF_USERS` concurrent Locust users (default: 10), ramping up at `PERF_RAMP_UP` users/second
3. Each Locust user authenticates at start and re-authenticates automatically when the bearer token expires (HTTP 401), then repeatedly submits bulk requests (0.1-0.5s pause between requests)
4. After the configured duration, Locust prints per-endpoint statistics and the custom summary block


## Results

After running the tests:

| Field                          | Meaning                                                                                     |
| ------------------------------ | ------------------------------------------------------------------------------------------- |
| **Configuration**              | Repeats the parameter values used for this test run                                         |
| **Total activities processed** | Sum of all per-item OK + NOK results across all HTTP requests, incl. overshoot              |
| **HTTP requests**              | Total HTTP requests with per-endpoint breakdown (auth + bulk)                               |
| **Throughput**                 | Actual sustained rate of successfully processed activities per second                       |
| **Bulk requests/sec**          | Actual sustained rate of bulk POST requests per second (x activities per request)           |
| **Extrapolated**               | Throughput projected over 24 hours — what the system *can* sustain                          |
| **Target**                     | What you *asked* for (`PERF_ACTIVITIES_TARGET`), reached by `PERF_USERS` concurrent users   |
| **Verdict**                    | Whether extrapolated capacity meets or exceeds the target, with the headroom ratio          |
| **Overshoot**                  | Only shown when `PERF_STOP_ON_TARGET=true` and total exceeds target (see explanation below) |

**Note on target vs extrapolated:** The target controls the *minimum* load (number of concurrent users). Each user fires requests as fast as possible, so actual throughput is whatever the server can sustain. The "extrapolated" value shows real capacity; the ratio tells you how much headroom exists above the target.

**Note on overshoot when `PERF_STOP_ON_TARGET=true`:** When the target is reached, the test signals Locust to stop. However, all concurrent users have already sent their current request, and those in-flight requests complete at the database level even though their responses may not be counted by Locust. The summary shows two overshoot values:
- **Overshoot (counted):** extra activities recorded in Locust's counter beyond the target (may be 0 if the runner shut down before counting the last responses)
- **Overshoot (max):** worst-case overshoot = `PERF_USERS x PERF_BATCH_SIZE` (e.g. 10 users x 1000 batch = 10,000 activities)

The actual database row count may be higher than what Locust reports. This is inherent to concurrent load testing — `runner.quit()` cannot cancel in-flight HTTP requests.

**Note on `PERF_RAMP_UP`:** Controls how many users are spawned per second (Locust's `-r` flag). Default is `1` (one user per second). With 10 users and ramp-up 1, all users are active within 10 seconds — fast enough for most tests while giving the system time to handle each user's authentication request sequentially. For stress testing with 100+ users, keeping ramp-up at 1/sec is important to avoid overwhelming the auth endpoint at startup. Set to a higher value (e.g. `PERF_RAMP_UP=10`) to spawn all users instantly.

## Benchmarks

Industry-standard benchmarks for API response times:

| Response time | Rating                     |
| ------------- | -------------------------- |
| < 100 ms      | Excellent (fast endpoints) |
| 100-300 ms    | Very good (typical APIs)   |
| 300-500 ms    | Acceptable                 |
| > 1 s         | Noticeable delay           |

**References:**
- Google SRE Workbook (Latency & SLOs)
- AWS Well-Architected Framework (Performance Efficiency)
- Nielsen Norman Group — [Response Time Limits](https://www.nngroup.com/articles/response-times-3-important-limits/)

**Contextualisation for bulk endpoints:**

- These benchmarks are based on individual HTTP requests
- When assessing bulk performance, consider both the per-request latency and the per-item cost (i.e., response time divided by batch size)
- For example, processing up to 1000 activities in a single request: a 200 ms response time equates to 0.2 ms per item (excellent), whereas 200 ms for a single-item endpoint would be considered only “very good”

## Tuning

### Connection pool chain

Requests flow through two connection pools before reaching PostgreSQL:

```
Locust users ─► sdep-backend (SQLAlchemy pool) ─► PgBouncer ─► PostgreSQL
```

Both pools must be sized correctly. If the SQLAlchemy pool is too small, requests queue inside the backend waiting for a database connection — even though PgBouncer and PostgreSQL have plenty of capacity.

### SQLAlchemy pool (`backend/app/db/config.py`)

| Parameter      | Description                                                    |
| -------------- | -------------------------------------------------------------- |
| `pool_size`    | Number of persistent connections kept open                     |
| `max_overflow` | Extra connections created on demand when `pool_size` is full   |
| **Total**      | `pool_size + max_overflow` = maximum concurrent DB connections |

The pool must accommodate the number of concurrent requests the backend handles. Each bulk request holds a connection for the duration of its database transaction — which can be several seconds under load. If all connections are in use, new requests wait up to 30 seconds and then fail with:

```
sqlalchemy.exc.TimeoutError: QueuePool limit of size N overflow M reached, connection timed out
```

**Sizing rule:** `pool_size + max_overflow` should be at least as large as the expected number of concurrent bulk requests, but must stay within PgBouncer's `default_pool_size` budget. With multiple backend replicas, divide the budget accordingly (e.g. 2 replicas with PgBouncer pool of 50 → 25 max connections per replica).

### PgBouncer pool (`sdep-cnpg Pooler` resource)

| Parameter           | Description                                                       |
| ------------------- | ----------------------------------------------------------------- |
| `default_pool_size` | Max server connections per user/database pair                     |
| `max_client_conn`   | Max client connections PgBouncer accepts (from all backend pods)  |
| `reserve_pool_size` | Extra connections available when the regular pool is fully in use |

PgBouncer sits between the backend and PostgreSQL. Its `default_pool_size` is the upper bound for how many connections all backend replicas combined can use simultaneously.

### Example: sizing for 50 concurrent users

| Layer      | Parameter           | Value | Rationale                                     |
| ---------- | ------------------- | ----- | --------------------------------------------- |
| SQLAlchemy | `pool_size`         | 20    | Persistent connections for steady-state load  |
| SQLAlchemy | `max_overflow`      | 30    | Burst capacity for peak load                  |
| SQLAlchemy | **total**           | 50    | Matches PgBouncer budget for a single replica |
| PgBouncer  | `default_pool_size` | 50    | Allows 50 concurrent server connections       |
| PgBouncer  | `max_client_conn`   | 1000  | Headroom for connection churn                 |

If you scale to 2 backend replicas, set SQLAlchemy to `pool_size=10, max_overflow=15` (25 per replica × 2 = 50 total ≤ PgBouncer's 50).


## Service Level Objectives (SLO)

When looking at approaches in public cloud, e.g. in Google SRE practice, SLOs for batch processing differ fundamentally from interactive services. Where request-driven services focus on *availability* and *latency*, batch SLOs revolve around data throughput and freshness.

### Service Level Indicators (SLIs)

Four SLIs are most relevant for bulk activity ingestion:

**A. Freshness**

Freshness measures how "stale" data is — the time between "data changed at source" and "data is available in our system". It is the most important SLI for systems that **pull** data on a schedule (e.g. a pipeline that polls an external source every 15 minutes).

SDEP is a **push API**: external STR platforms submit activities via HTTP whenever they choose, and the data is persisted within the same request. There is no scheduled pipeline, no polling interval, no batch window. The "freshness" is entirely controlled by the caller, not by SDEP. Any delay in data availability is already captured by the **throughput** and **latency** SLIs — if the system is too slow or backlogged, those metrics will show it.

- **Relevance to SDEP:** Low. Freshness is not a meaningful SLI for a push-based API.
- **Current coverage:** Not measured, and not needed.

**B. Coverage**

Batch processes can skip records due to corrupt data or configuration errors.

- **Definition:** The percentage of records successfully processed out of the total number of records submitted.
- **Example SLO:** At least 99.9% of submitted activities per day are successfully processed.
- **Current coverage:** Fully measured. The test reports a `Coverage (SLI)` percentage that combines all failure modes into a single number: `succeeded / (succeeded + nok + http_failures × batch_size)`. This accounts for application-level NOK items (validation failures, FK errors) as well as HTTP-level failures (502, connection reset) where the entire batch of `batch_size` activities is assumed lost.

**C. Correctness**

A bug in transformation logic can silently corrupt millions of records in a single batch run.

- **Definition:** The percentage of records where the output is valid according to defined business rules.
- **Measurement:** Typically done via "canary data" or integration tests that run alongside the pipeline.
- **Current coverage:** Not measured. The performance test generates randomized payloads but does not verify that the persisted data matches the submitted data. The existing integration tests (`tests/integration/`) cover correctness for individual requests but not under bulk load.
- **Suggestion:** After the performance test completes, sample a small number of submitted activities (e.g. 10) and verify them via `GET /str/activities/{id}`, checking that all fields match the submitted payload. This would catch silent data corruption under load (e.g. race conditions, partial writes).

**D. Throughput**

Useful for systems with variable load to ensure the pipeline keeps up with growth.

- **Definition:** The number of records processed per unit of time.
- **Example SLO:** The pipeline processes at least 100,000 records per second during peak hours.
- **Current coverage:** Fully measured. This is the primary metric of the performance test: `Throughput` (activities/sec), `Bulk requests/sec`, and `Extrapolated` (activities/day). The `Verdict` line compares extrapolated capacity against the configured target.

### Strategies for bulk updates

Google applies specific patterns to guarantee reliability at large volumes. Here is how SDEP implements them:

| Strategy                    | Description                                                                       | SDEP implementation                                                                                                                                                                                                                              |
| --------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **Atomicity**               | A batch request succeeds or fails as a whole, preventing partial states           | Each bulk request is a single database transaction. On error, the entire batch rolls back — no half-written state. Per-item validation failures are reported as NOK without aborting the valid items in the same batch.                          |
| **Idempotency**             | A bulk update can be retried without creating duplicates                          | Implemented via activity versioning: re-submitting an `activityId` marks the previous version as ended (`ended_at = now()`) and inserts a new current version. Duplicate `activityId` values within a single batch are deduplicated (last-wins). |
| **Side-by-side validation** | Compare output of a new batch version against the previous one before overwriting | Not currently implemented. Could be added as a post-ingestion step that compares record counts and checksums between the previous and current batch for a given platform.                                                                        |

### Error budgets for batch processing

Batch errors behave differently in an error budget than request-level errors:

- **Impact:** A single failing daily batch job can consume 100% of the daily error budget in one go — unlike interactive services where errors are distributed across many small requests.
- **Alerting:** Set alerts on "time-to-complete". If a batch job takes 2x longer than normal, this is often a precursor to an SLO breach.
- **SDEP relevance:** The performance test's `Verdict` line is essentially a throughput error budget check — if extrapolated capacity drops below the target, the system cannot sustain the required daily volume. The `10 consecutive failures` abort mechanism acts as an early warning: if the system is degraded enough to fail 10 requests in a row, the test stops rather than burning through the error budget.

### Summary: SLI measurement gaps

| SLI         | Measured by perf test?                                               | Suggested extension                            |
| ----------- | -------------------------------------------------------------------- | ---------------------------------------------- |
| Freshness   | N/A — not meaningful for a push-based API                            | —                                              |
| Coverage    | Yes — `Coverage (SLI)` in summary                                    | —                                              |
| Correctness | No                                                                   | Post-test sample-and-verify via GET endpoint   |
| Throughput  | Yes                                                                  | —                                              |

---
*Based on the Google SRE Workbook & Google Cloud Architecture Framework.*
