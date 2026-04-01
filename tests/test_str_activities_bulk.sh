#!/bin/bash

# Test script for bulk activity submission endpoint of the SDEP API
# Expects BACKEND_BASE_URL environment variable to be set
# Optionally accepts BEARER_TOKEN environment variable for authenticated requests
# Optionally accepts API_VERSION environment variable (defaults to v0)
# Tests POST /str/activities/bulk endpoint

set -e

if [ -z "$BACKEND_BASE_URL" ]; then
    echo "❌ Error: BACKEND_BASE_URL environment variable is not set"
    exit 1
fi

# Default API version to v0 if not set
API_VERSION=${API_VERSION:-v0}

# STR endpoint requires authorized client
# Load token from ./tmp/.bearer_token file
if [ -f ./tmp/.bearer_token ]; then
    BEARER_TOKEN=$(cat ./tmp/.bearer_token)
    echo "🔑 Loaded BEARER_TOKEN from ./tmp/.bearer_token"
else
    echo "⚠️  No ./tmp/.bearer_token file found"
fi

echo "🔍 Testing STR bulk activity endpoints at: ${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities/bulk"

# Check if BEARER_TOKEN is set
if [ -n "$BEARER_TOKEN" ]; then
    echo "🔑 Using Bearer token for authentication"
else
    echo "⚠️  No BEARER_TOKEN set - making unauthenticated request (should fail)"
fi
echo

# Track test results
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Setup: Create fixture areas so tests work on empty DB
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
echo "📦 Creating fixture areas for bulk activity tests..."
FIXTURE_IDS=$("$SCRIPT_DIR/lib/create_fixture_areas.sh" 3 "sdep-test-bulk-areas" 2>&1 | tee /dev/stderr | grep "^sdep-test-")
AREA_ID_1=$(echo "$FIXTURE_IDS" | sed -n '1p')
AREA_ID_2=$(echo "$FIXTURE_IDS" | sed -n '2p')
AREA_ID_3=$(echo "$FIXTURE_IDS" | sed -n '3p')

if [ -z "$AREA_ID_1" ] || [ -z "$AREA_ID_2" ] || [ -z "$AREA_ID_3" ]; then
    echo "❌ Error: Failed to create fixture areas"
    exit 1
fi
echo "✅ Using fixture area IDs: $AREA_ID_1, $AREA_ID_2, $AREA_ID_3"
echo

# Generate dynamic timestamps
TIMESTAMP=$(date +%s)
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u -d "+1 hour" +"%Y-%m-%dT%H:%M:%SZ")

# Test 1: POST bulk activities (all valid)
echo "Test 1: POST bulk activities (all valid → 201)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if [ -n "$BEARER_TOKEN" ]; then
    read -r -d '' PAYLOAD <<EOF || true
{
  "activities": [
    {
      "activityId": "sdep-test-bulk-ok1-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-ok1",
      "registrationNumber": "REGBULK001",
      "address": {"thoroughfare": "Prinsengracht", "locatorDesignatorNumber": 265, "postCode": "1016HV", "postName": "Amsterdam"},
      "temporal": {"startDatetime": "$START_TIME", "endDatetime": "$END_TIME"},
      "areaId": "$AREA_ID_1",
      "numberOfGuests": 4
    },
    {
      "activityId": "sdep-test-bulk-ok2-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-ok2",
      "registrationNumber": "REGBULK002",
      "address": {"thoroughfare": "Keizersgracht", "locatorDesignatorNumber": 100, "postCode": "1015AA", "postName": "Amsterdam"},
      "temporal": {"startDatetime": "$START_TIME", "endDatetime": "$END_TIME"},
      "areaId": "$AREA_ID_2",
      "numberOfGuests": 2
    }
  ]
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities/bulk")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 201 ]; then
        if echo "$body" | grep -q '"succeeded":2' && echo "$body" | grep -q '"failed":0'; then
            echo "✅ Test 1 passed: All activities created (201)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 1 failed: Expected succeeded=2, failed=0"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 1 failed: Expected 201 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 1 (requires authentication)"
fi

echo

# Test 2: POST bulk activities (partial success)
echo "Test 2: POST bulk activities (partial success → 200)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if [ -n "$BEARER_TOKEN" ]; then
    START_TIME_2=$(date -u -d "+2 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_2=$(date -u -d "+3 hours" +"%Y-%m-%dT%H:%M:%SZ")

    read -r -d '' PAYLOAD_PARTIAL <<EOF || true
{
  "activities": [
    {
      "activityId": "sdep-test-bulk-partial1-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-partial1",
      "registrationNumber": "REGPART001",
      "address": {"thoroughfare": "Prinsengracht", "locatorDesignatorNumber": 265, "postCode": "1016HV", "postName": "Amsterdam"},
      "temporal": {"startDatetime": "$START_TIME_2", "endDatetime": "$END_TIME_2"},
      "areaId": "$AREA_ID_1",
      "numberOfGuests": 4
    },
    {
      "activityId": "sdep-test-bulk-partial2-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-partial2",
      "registrationNumber": "REGPART002",
      "address": {"thoroughfare": "Bad Street", "locatorDesignatorNumber": 1, "postCode": "0000AA", "postName": "Nowhere"},
      "temporal": {"startDatetime": "$START_TIME_2", "endDatetime": "$END_TIME_2"},
      "areaId": "nonexistent-area-id",
      "numberOfGuests": 2
    }
  ]
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_PARTIAL" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities/bulk")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 200 ]; then
        if echo "$body" | grep -q '"succeeded":1' && echo "$body" | grep -q '"failed":1'; then
            echo "✅ Test 2 passed: Partial success (200)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 2 failed: Expected succeeded=1, failed=1"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 2 failed: Expected 200 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 2 (requires authentication)"
fi

echo

# Test 3: POST bulk activities (all invalid → 422)
echo "Test 3: POST bulk activities (all invalid → 422)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if [ -n "$BEARER_TOKEN" ]; then
    START_TIME_3=$(date -u -d "+4 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_3=$(date -u -d "+5 hours" +"%Y-%m-%dT%H:%M:%SZ")

    read -r -d '' PAYLOAD_FAIL <<EOF || true
{
  "activities": [
    {
      "activityId": "sdep-test-bulk-fail1-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-fail1",
      "registrationNumber": "REGFAIL001",
      "address": {"thoroughfare": "Bad Street", "locatorDesignatorNumber": 1, "postCode": "0000AA", "postName": "Nowhere"},
      "temporal": {"startDatetime": "$START_TIME_3", "endDatetime": "$END_TIME_3"},
      "areaId": "nonexistent-area-1"
    },
    {
      "activityId": "sdep-test-bulk-fail2-$TIMESTAMP",
      "url": "http://sdep-test.example.com/bulk-fail2",
      "registrationNumber": "REGFAIL002",
      "address": {"thoroughfare": "Bad Street", "locatorDesignatorNumber": 2, "postCode": "0000BB", "postName": "Nowhere"},
      "temporal": {"startDatetime": "$START_TIME_3", "endDatetime": "$END_TIME_3"},
      "areaId": "nonexistent-area-2"
    }
  ]
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_FAIL" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities/bulk")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 422 ]; then
        if echo "$body" | grep -q '"succeeded":0' && echo "$body" | grep -q '"failed":2'; then
            echo "✅ Test 3 passed: All failed (422)"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 3 failed: Expected succeeded=0, failed=2"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 3 failed: Expected 422 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 3 (requires authentication)"
fi

echo

# Test 4: POST bulk without auth (→ 401)
echo "Test 4: POST bulk activities without authentication (→ 401)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

response=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"activities": [{"areaId": "test"}]}' \
    "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities/bulk")

http_code=$(echo "$response" | tail -n1)

echo "HTTP Status: $http_code"
echo

if [ "$http_code" -eq 401 ]; then
    echo "✅ Test 4 passed: Correctly rejected unauthenticated request (401)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ Test 4 failed: Expected 401 but got $http_code"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo

# Summary
echo "═══════════════════════════════════════"
echo "Test Summary (bulk activities):"
echo "  Total:  $TOTAL_TESTS"
echo "  Passed: $PASSED_TESTS ✅"
echo "  Failed: $FAILED_TESTS ❌"
echo "═══════════════════════════════════════"

if [ $FAILED_TESTS -eq 0 ]; then
    echo "✅ All bulk activity endpoint tests passed!"
    exit 0
else
    echo "❌ Some bulk activity endpoint tests failed!"
    exit 1
fi
