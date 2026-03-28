"""Locust performance test for POST /str/activities/bulk.

Simulates a configurable number of activities/day brought back to activities/sec,
for a configurable duration, using the isolated testdata approach (sdep-test-perf-* naming).

Configuration via environment variables (set by Makefile):
    PERF_BATCH_SIZE: Number of activities per bulk request (default: 500)
    BACKEND_BASE_URL: API base URL (default: http://localhost:8000)
    API_VERSION: API version (default: v0)
    STR_CLIENT_ID: OAuth2 client ID for STR platform
    STR_CLIENT_SECRET: OAuth2 client secret for STR platform
    PERF_AREA_IDS: Comma-separated list of area IDs to use (created by Makefile)

Usage:
    Typically invoked via `make test-perf`, not directly.
    For manual use:
        locust -f tests/perf/locustfile.py --headless -u 1 -r 1 --run-time 60s
"""

import atexit
import os
import random
import string
import time
import uuid

import gevent
from locust import HttpUser, between, events, task

# Configuration from environment
BATCH_SIZE = int(os.environ.get("PERF_BATCH_SIZE", "500"))
API_VERSION = os.environ.get("API_VERSION", "v0")
STR_CLIENT_ID = os.environ.get("STR_CLIENT_ID", "sdep-test-str01")
STR_CLIENT_SECRET = os.environ.get("STR_CLIENT_SECRET", "")
PERF_AREA_IDS = [x for x in os.environ.get("PERF_AREA_IDS", "").split(",") if x]
PERF_USERS = int(os.environ.get("PERF_USERS", "1"))
PERF_MAX_DURATION_SECONDS = int(os.environ.get("PERF_MAX_DURATION_SECONDS", "300"))
PERF_ACTIVITIES_TARGET = int(os.environ.get("PERF_ACTIVITIES_TARGET", "500000"))
PERF_KEEP_DATA = os.environ.get("PERF_KEEP_DATA", "false").lower() in ("true", "1", "yes")
PERF_STOP_ON_TARGET = os.environ.get("PERF_STOP_ON_TARGET", "false").lower() in ("true", "1", "yes")
ACTIVITY_ID_PREFIX = "perf" if PERF_KEEP_DATA else "sdep-test-perf"
TARGET_TOTAL = PERF_ACTIVITIES_TARGET

# Global counters for summary
total_activities_ok = 0
total_activities_nok = 0
total_bulk_failures = 0
total_http_failures = 0
requests_per_endpoint: dict[str, int] = {}
MAX_CONSECUTIVE_FAILURES = 10
test_start_time = None


_locust_environment = None


@events.test_start.add_listener
def on_test_start(environment, **kwargs):
    global test_start_time, _locust_environment
    test_start_time = time.time()
    _locust_environment = environment


first_error_logged = False


@events.request.add_listener
def on_request(request_type, name, response_time, response_length, response, exception, **kwargs):
    """Track per-activity success/failure from bulk response."""
    global total_activities_ok, total_activities_nok, total_bulk_failures, total_http_failures, first_error_logged
    requests_per_endpoint[name] = requests_per_endpoint.get(name, 0) + 1
    if response is None:
        return
    if name == "/auth/token":
        return
    if response.status_code in (200, 201):
        total_bulk_failures = 0  # reset consecutive failure counter
        try:
            data = response.json()
            total_activities_ok += data.get("succeeded", 0)
            total_activities_nok += data.get("failed", 0)
        except Exception:
            pass
        # Stop early when target reached
        if PERF_STOP_ON_TARGET and total_activities_ok >= TARGET_TOTAL and _locust_environment:
            print(f"\n✅ Target reached ({total_activities_ok:,} >= {TARGET_TOTAL:,}), stopping early...")
            gevent.spawn_later(0.1, _locust_environment.runner.quit)
    else:
        total_bulk_failures += 1
        total_http_failures += 1
        if not first_error_logged:
            first_error_logged = True
            if response.status_code == 0:
                detail = str(exception) if exception else "no details"
                print(f"\n⚠️  Connection error on bulk request: {detail}")
                print("   The server likely processed the activities, but the connection dropped")
                print("   before the response arrived (e.g., load balancer timeout, connection")
                print("   reset under load). These are typically harmless — let the test continue")
                print("   and check the final results summary to confirm.\n")
            else:
                print(f"\n⚠️  First bulk error (HTTP {response.status_code}): {response.text[:500]}\n")
        # Abort if all requests are failing
        if total_bulk_failures >= MAX_CONSECUTIVE_FAILURES and _locust_environment:
            print(f"\n❌ Aborting: {MAX_CONSECUTIVE_FAILURES} consecutive bulk request failures")
            gevent.spawn_later(0.1, _locust_environment.runner.quit)


_summary_printed = False


def _human(n: float) -> str:
    """Format number with human-readable suffix: K, M, B."""
    abs_n = abs(n)
    if abs_n >= 1_000_000_000:
        return f"{n / 1_000_000_000:.0f}B"
    if abs_n >= 1_000_000:
        return f"{n / 1_000_000:.0f}M"
    if abs_n >= 1_000:
        return f"{n / 1_000:.0f}K"
    return str(int(n))


def _print_summary():
    """Print performance summary (guarded against double printing)."""
    global _summary_printed
    if _summary_printed:
        return
    _summary_printed = True

    duration = time.time() - test_start_time if test_start_time else 0
    total = total_activities_ok + total_activities_nok
    throughput = total_activities_ok / duration if duration > 0 else 0
    extrapolated_day = throughput * 86400
    target_volume = PERF_ACTIVITIES_TARGET
    ratio = extrapolated_day / target_volume if target_volume > 0 else 0

    minutes = int(duration // 60)
    seconds = int(duration % 60)

    verdict = f"ABOVE TARGET ({ratio:.1f}x)" if extrapolated_day >= target_volume else f"BELOW TARGET ({ratio:.1f}x)"
    icon = "✅" if extrapolated_day >= target_volume else "❌"

    total_requests = sum(requests_per_endpoint.values())
    bulk_requests = requests_per_endpoint.get("/str/activities/bulk", 0)
    bulk_requests_per_sec = bulk_requests / duration if duration > 0 else 0

    def _cfg(name: str, value: str) -> str:
        return f"    {name:<27} = {value}"

    print()
    print("══ PERFORMANCE TEST RESULTS ══════════════════════════════")
    print("  Configuration:")
    print(_cfg("PERF_ACTIVITIES_TARGET", f"{target_volume:,} ({_human(target_volume)}) (target volume)"))
    print(_cfg("PERF_USERS", f"{PERF_USERS} (concurrent users to reach the target volume)"))
    print(_cfg("PERF_BATCH_SIZE", f"{BATCH_SIZE} (activities per HTTP request)"))
    print(_cfg("PERF_MAX_DURATION_SECONDS", f"{PERF_MAX_DURATION_SECONDS} ({PERF_MAX_DURATION_SECONDS / 60:.1f}m / {PERF_MAX_DURATION_SECONDS / 3600:.2f}h) (max. test duration)"))
    print(_cfg("PERF_STOP_ON_TARGET", f"{PERF_STOP_ON_TARGET} (stop early when target reached)"))
    print(_cfg("PERF_KEEP_DATA", f"{PERF_KEEP_DATA} (keep data in database)"))
    print("  Results:")
    print(f"    Total activities processed:  {total:,} ({_human(total)}) (succeeded + failed, incl. overshoot)")
    print(f"    Succeeded:                   {total_activities_ok:,} ({_human(total_activities_ok)}) (activities accepted by the API)")
    print(f"    Failed:                      {total_activities_nok:,} ({_human(total_activities_nok)}) (activities rejected by the API)")
    print(f"    HTTP failures:               {total_http_failures:,} (bulk requests that failed at HTTP level, e.g. 502/timeout)")
    estimated_lost = total_http_failures * BATCH_SIZE
    total_attempted = total_activities_ok + total_activities_nok + estimated_lost
    coverage_pct = (total_activities_ok / total_attempted * 100) if total_attempted > 0 else 0
    print(f"    Coverage (SLI):              {coverage_pct:.2f}% (succeeded / total attempted incl. estimated HTTP losses)")
    print(f"    HTTP requests:               {total_requests:,} total")
    for endpoint, count in sorted(requests_per_endpoint.items()):
        print(f"      {endpoint:<30} {count:,}")
    print(f"    Duration:                    {minutes}m {seconds:02d}s")
    print(f"    Throughput:                  {throughput:,.1f} activities/sec ({_human(throughput)}/s) (sustained rate)")
    print(f"    Bulk requests/sec:           {bulk_requests_per_sec:,.1f} req/sec (x PERF_BATCH_SIZE={BATCH_SIZE} activities/req)")
    print(f"    Extrapolated:                {extrapolated_day:,.0f} activities/day ({_human(extrapolated_day)}/day) (throughput x 24h)")
    print(f"    Target:                      {target_volume:,} activities/day ({_human(target_volume)}/day) (PERF_ACTIVITIES_TARGET across PERF_USERS={PERF_USERS})")
    print(f"    Verdict:                     {icon} {verdict}")
    if PERF_STOP_ON_TARGET and total_activities_ok >= target_volume:
        overshoot_counted = total_activities_ok - target_volume
        overshoot_max = PERF_USERS * BATCH_SIZE
        print(f"    Overshoot (counted):         +{overshoot_counted:,} ({_human(overshoot_counted)})")
        print(f"    Overshoot (max):             +{overshoot_max:,} ({_human(overshoot_max)}) (up to PERF_USERS={PERF_USERS} in-flight x PERF_BATCH_SIZE={BATCH_SIZE})")
    print("══════════════════════════════════════════════════════════")
    print()


@events.test_stop.add_listener
def on_test_stop(environment, **kwargs):
    _print_summary()


@atexit.register
def _atexit_handler():
    """Runs after Locust's own statistics table (atexit runs last)."""
    # Ensure summary prints even if test_stop didn't fire
    _print_summary()

    # Explanation of Locust's statistics tables (printed after the tables)
    print("Table 1. Response time statistics:")
    print()
    print("  # reqs     — total HTTP requests ")
    print("  # fails    — total failures (%) = non-2xx")
    print("  Avg        — response time in ms")
    print("  Min        — response time in ms")
    print("  Max        — response time in ms")
    print("  Med        — response time in ms")
    print("  req/s      — requests per second")
    print("  failures/s — failures per second")
    print()
    print("Table 2. Response time percentiles:")
    print()
    print("  p50 = median (half of requests are faster)")
    print("  p95 = 95% of requests are faster, only 5% are slower")
    print("  p99 = 99% of requests are faster (worst-case users)")
    print()
    print("  When p50 low && p99 high >> \"tail latency\":")
    print("  most requests are fast, but a few are very slow")
    print()
    print("Response time benchmarks (industry standard):")
    print()
    print("  1. < 100 ms          — Excellent (fast endpoints)")
    print("  2. 100-300 ms        — Very good (typical APIs)")
    print("  3. 300-500 ms        — Acceptable")
    print("  4. > 1 s             — Noticeable delay")
    print()
    print("  - Google SRE Workbook, AWS Well-Architected Framework,")
    print("  - AWS Well-Architected Framework,")
    print("  - Nielsen Norman Group (https://www.nngroup.com/articles/response-times-3-important-limits/)")
    print()
    print("Note on bulk endpoints:")
    print()
    print("  These benchmarks are based on individual HTTP requests.")
    print("  When assessing bulk performance, consider both the per-request latency")
    print("  and the per-item cost (i.e., response time divided by batch size).")
    print("  For example, processing up to 1000 activities in a single request:")
    print("  a 200 ms response time equates to 0.2 ms per item (excellent),")
    print("  whereas 200 ms for a single-item endpoint would be only \"very good\".")
    print()

def _generate_activity(area_id: str, timestamp: str) -> dict:
    """Generate a realistic activity dict for performance testing."""
    unique = uuid.uuid4().hex[:12]
    return {
        "activityId": f"{ACTIVITY_ID_PREFIX}-{unique}",
        "url": f"http://{ACTIVITY_ID_PREFIX}.example.com/{unique}",
        "registrationNumber": f"REGPERF{unique[:8].upper()}",
        "address": {
            "street": random.choice(["Prinsengracht", "Keizersgracht", "Herengracht", "Damrak", "Rokin"]),
            "number": random.randint(1, 999),
            "postalCode": f"{random.randint(1000, 9999)}{''.join(random.choices(string.ascii_uppercase, k=2))}",
            "city": random.choice(["Amsterdam", "Rotterdam", "Den Haag", "Utrecht", "Eindhoven"]),
        },
        "temporal": {
            "startDatetime": timestamp,
            "endDatetime": "2027-12-31T23:59:59Z",
        },
        "areaId": area_id,
        "numberOfGuests": random.randint(1, 10),
        "countryOfGuests": random.sample(["NLD", "DEU", "BEL", "FRA", "GBR", "ESP", "ITA", "USA"], k=random.randint(1, 3)),
    }


class BulkActivityUser(HttpUser):
    """Simulates an STR platform submitting bulk activities."""

    wait_time = between(0.1, 0.5)
    _token = None

    def on_start(self):
        """Authenticate via OAuth2 client credentials on start."""
        if not STR_CLIENT_SECRET:
            raise RuntimeError(
                "STR_CLIENT_SECRET not set. Run via 'make test-perf' or set env vars manually."
            )
        self._refresh_token()

    def _refresh_token(self):
        """Obtain a new bearer token via OAuth2 client credentials."""
        response = self.client.post(
            f"/api/{API_VERSION}/auth/token",
            data={
                "grant_type": "client_credentials",
                "client_id": STR_CLIENT_ID,
                "client_secret": STR_CLIENT_SECRET,
            },
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            name="/auth/token",
        )
        if response.status_code == 200:
            self._token = response.json().get("access_token")
        else:
            raise RuntimeError(f"Auth failed: {response.status_code} {response.text}")

    @task
    def post_bulk_activities(self):
        """Submit a batch of activities."""
        if not self._token:
            return

        if not PERF_AREA_IDS or PERF_AREA_IDS == [""]:
            raise RuntimeError("PERF_AREA_IDS not set. Run via 'make test-perf'.")

        timestamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        activities = [
            _generate_activity(random.choice(PERF_AREA_IDS), timestamp)
            for _ in range(BATCH_SIZE)
        ]

        response = self.client.post(
            f"/api/{API_VERSION}/str/activities/bulk",
            json={"activities": activities},
            headers={
                "Authorization": f"Bearer {self._token}",
                "Content-Type": "application/json",
            },
            name="/str/activities/bulk",
        )

        if response.status_code == 401:
            self._refresh_token()
            self.client.post(
                f"/api/{API_VERSION}/str/activities/bulk",
                json={"activities": activities},
                headers={
                    "Authorization": f"Bearer {self._token}",
                    "Content-Type": "application/json",
                },
                name="/str/activities/bulk",
            )
