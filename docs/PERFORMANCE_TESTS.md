<h1>Performance Tests</h1>

The [../tests/perf](../tests/perf) directory contains a [Locust](https://locust.io/) test for load testing the SDEP bulk activity endpoint (`POST /str/activities/bulk`).

## Running Performance Tests

See [../Makefile](../Makefile).

Quick reference:

| Target           | Description                                                  |
| ---------------- | ------------------------------------------------------------ |
| `make test-perf` | Run bulk performance test with various configuratoin options |

## `perf/locustfile.py`

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


## Understanding the results

After running the tests:

| Field                          | Meaning                                                                                    |
| ------------------------------ | ------------------------------------------------------------------------------------------ |
| **Configuration**              | Repeats the parameter values used for this test run                                        |
| **Total activities processed** | Sum of all per-item OK + NOK results across all HTTP requests                              |
| **HTTP requests**              | Total HTTP requests with per-endpoint breakdown (auth + bulk)                              |
| **Throughput**                 | Actual sustained rate of successfully processed activities per second                      |
| **Bulk requests/sec**          | Actual sustained rate of bulk POST requests per second (x activities per request)          |
| **Extrapolated**               | Throughput projected over 24 hours — what the system *can* sustain                         |
| **Target**                     | What you *asked* for (`PERF_ACTIVITIES_PER_DAY` x `PERF_USERS`)                            |
| **Verdict**                    | Whether extrapolated capacity meets or exceeds the target, with the headroom ratio         |
| **Overshoot**                  | Only shown when `PERF_STOP_ON_TARGET=true` and total exceeds target (see explanation below) |

**Note on target vs extrapolated:** The target controls the *minimum* load (number of concurrent users). Each user fires requests as fast as possible, so actual throughput is whatever the server can sustain. The "extrapolated" value shows real capacity; the ratio tells you how much headroom exists above the target.

**Note on overshoot when `PERF_STOP_ON_TARGET=true`:** When the target is reached, the test signals Locust to stop. However, all concurrent users have already sent their current request, and those in-flight responses still arrive and are counted. This means the total activities processed may exceed the target by up to `PERF_USERS x PERF_BATCH_SIZE`. For example, with 100 users and batch size 1000, the overshoot is at most 100,000 activities. This is inherent to concurrent load testing — `runner.quit()` cannot cancel in-flight HTTP requests.

**Note on `PERF_RAMP_UP`:** Controls how many users are spawned per second (Locust's `-r` flag). Default is `1` (one user per second). With 10 users and ramp-up 1, all users are active within 10 seconds — fast enough for most tests while giving the system time to handle each user's authentication request sequentially. For stress testing with 100+ users, keeping ramp-up at 1/sec is important to avoid overwhelming the auth endpoint at startup. Set to a higher value (e.g. `PERF_RAMP_UP=10`) to spawn all users instantly.

### Response time benchmarks

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

- These benchmarks apply to individual HTTP requests
- The bulk endpoint processes up to 1000 activities per request, so a 200ms response for 1000 items (0.2ms/item) is excellent, whereas 200ms for a single-item endpoint would be just "very good"
- When evaluating bulk performance, consider the per-item cost (response time / batch size) alongside the per-request latency
