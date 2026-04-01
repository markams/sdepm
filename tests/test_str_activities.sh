#!/bin/bash

# Test script for activity submission endpoint of the SDEP API
# Expects BACKEND_BASE_URL environment variable to be set
# Optionally accepts BEARER_TOKEN environment variable for authenticated requests
# Optionally accepts API_VERSION environment variable (defaults to v0)
# Tests POST /str/activities endpoint with single activity

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

echo "🔍 Testing STR activity endpoints at: ${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities"

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
echo "📦 Creating fixture areas for activity tests..."
FIXTURE_IDS=$("$SCRIPT_DIR/lib/create_fixture_areas.sh" 3 "sdep-test-str-act-areas" 2>&1 | tee /dev/stderr | grep "^sdep-test-")
AREA_ID_1=$(echo "$FIXTURE_IDS" | sed -n '1p')
AREA_ID_2=$(echo "$FIXTURE_IDS" | sed -n '2p')
AREA_ID_3=$(echo "$FIXTURE_IDS" | sed -n '3p')

if [ -z "$AREA_ID_1" ] || [ -z "$AREA_ID_2" ] || [ -z "$AREA_ID_3" ]; then
    echo "❌ Error: Failed to create fixture areas"
    exit 1
fi
echo "✅ Using fixture area IDs: $AREA_ID_1, $AREA_ID_2, $AREA_ID_3"
echo

# Test 1: POST single activity (amsterdam-myhouse-1)
echo "Test 1: POST single activity (amsterdam-myhouse-1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Generate dynamic timestamps to avoid duplicate key errors
TIMESTAMP=$(date +%s)
START_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
END_TIME=$(date -u -d "+1 hour" +"%Y-%m-%dT%H:%M:%SZ")

# Prepare JSON payload (single activity)
read -r -d '' PAYLOAD <<EOF || true
{
  "activityId": "sdep-test-activity-single-$TIMESTAMP",
  "url": "http://sdep-test.example.com/amsterdam-myhouse-1",
  "registrationNumber": "REG0002",
  "address": {
    "thoroughfare": "Prinsengracht",
    "locatorDesignatorNumber": 265,
    "postCode": "1016HV",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME",
    "endDatetime": "$END_TIME"
  },
  "areaId": "$AREA_ID_1",
  "countryOfGuests": ["NLD", "DEU", "BEL"],
  "numberOfGuests": 4
}
EOF

if [ -n "$BEARER_TOKEN" ]; then
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")
else
    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -d "$PAYLOAD" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")
fi

http_code=$(echo "$response" | tail -n1)
body=$(echo "$response" | sed '$d')

echo "Response: $body"
echo "HTTP Status: $http_code"
echo

if [ "$http_code" -eq 201 ]; then
    # Check for ActivityOwnResponse format with activityId, createdAt, competentAuthorityId (no platformId)
    if echo "$body" | grep -q '"activityId"' && \
       echo "$body" | grep -q '"createdAt"' && \
       echo "$body" | grep -q '"competentAuthorityId"' && \
       ! echo "$body" | grep -q '"platformId"'; then
        echo "✅ Test 1 passed: Activity successfully submitted"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ Test 1 failed: Expected ActivityOwnResponse format in response (no platformId)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
elif [ "$http_code" -eq 401 ] && [ -z "$BEARER_TOKEN" ]; then
    echo "✅ Test 1 passed: Correctly rejected unauthenticated request (401)"
    PASSED_TESTS=$((PASSED_TESTS + 1))
else
    echo "❌ Test 1 failed: Unexpected HTTP status $http_code"
    FAILED_TESTS=$((FAILED_TESTS + 1))
fi

echo

# Test 2: POST with optional activityId field
echo "Test 2: POST with optional activityId field"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Only run if authenticated
if [ -n "$BEARER_TOKEN" ]; then
    # Generate dynamic timestamps with offset to avoid collisions with Test 1
    START_TIME_2=$(date -u -d "+4 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_2=$(date -u -d "+5 hours" +"%Y-%m-%dT%H:%M:%SZ")

    # Generate unique URL using epoch timestamp to ensure test idempotence
    UNIQUE_ID=$(date +%s%N | cut -b1-12)

    # Prepare payload with activityId (single activity)
    read -r -d '' PAYLOAD_WITH_ID <<EOF || true
{
  "activityId": "sdep-test-activity-custom-$UNIQUE_ID",
  "url": "http://sdep-test.example.com/amsterdam-with-id-$UNIQUE_ID",
  "registrationNumber": "REGID001",
  "address": {
    "thoroughfare": "Prinsengracht",
    "locatorDesignatorNumber": 267,
    "postCode": "1016HV",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME_2",
    "endDatetime": "$END_TIME_2"
  },
  "areaId": "$AREA_ID_1",
  "countryOfGuests": ["NLD"],
  "numberOfGuests": 2
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_WITH_ID" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 201 ]; then
        # Check for ActivityOwnResponse format with competentAuthorityId (no platformId)
        if echo "$body" | grep -q '"activityId"' && \
           echo "$body" | grep -q '"createdAt"' && \
           echo "$body" | grep -q '"competentAuthorityId"' && \
           ! echo "$body" | grep -q '"platformId"'; then
            echo "✅ Test 2 passed: Activity with custom activityId successfully submitted"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 2 failed: Expected ActivityOwnResponse format (no platformId)"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 2 failed: Expected 201 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 2 (requires authentication)"
fi

echo

# Test 3: POST with validation error (missing required field)
echo "Test 3: POST with validation error (missing required field)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Only run if authenticated
if [ -n "$BEARER_TOKEN" ]; then
    # Generate dynamic timestamps with offset to avoid collisions
    START_TIME_3=$(date -u -d "+6 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_3=$(date -u -d "+7 hours" +"%Y-%m-%dT%H:%M:%SZ")

    # Prepare invalid payload (missing 'registrationNumber' required field)
    read -r -d '' PAYLOAD_INVALID <<EOF || true
{
  "url": "http://sdep-test.example.com/amsterdam-invalid",
  "address": {
    "thoroughfare": "Prinsengracht",
    "locatorDesignatorNumber": 999,
    "postCode": "1016HV",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME_3",
    "endDatetime": "$END_TIME_3"
  },
  "areaId": "$AREA_ID_1",
  "countryOfGuests": ["NLD"],
  "numberOfGuests": 2
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_INVALID" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 422 ]; then
        echo "✅ Test 3 passed: Validation error correctly returned (422)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ Test 3 failed: Expected 422 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 3 (requires authentication)"
fi

echo

# Test 3b: POST with non-existent country code (valid format but not a real ISO code)
echo "Test 3b: POST with non-existent country code (ZZZ)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Only run if authenticated
if [ -n "$BEARER_TOKEN" ]; then
    START_TIME_3B=$(date -u -d "+7 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_3B=$(date -u -d "+8 hours" +"%Y-%m-%dT%H:%M:%SZ")

    read -r -d '' PAYLOAD_BAD_COUNTRY <<EOF || true
{
  "url": "http://sdep-test.example.com/amsterdam-bad-country",
  "registrationNumber": "REGBADCC",
  "address": {
    "thoroughfare": "Prinsengracht",
    "locatorDesignatorNumber": 999,
    "postCode": "1016HV",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME_3B",
    "endDatetime": "$END_TIME_3B"
  },
  "areaId": "$AREA_ID_1",
  "countryOfGuests": ["ZZZ"],
  "numberOfGuests": 2
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_BAD_COUNTRY" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 422 ]; then
        echo "✅ Test 3b passed: Non-existent country code correctly rejected (422)"
        PASSED_TESTS=$((PASSED_TESTS + 1))
    else
        echo "❌ Test 3b failed: Expected 422 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 3b (requires authentication)"
fi

echo

# Test 4: POST with non-existent area
echo "Test 4: POST with non-existent area (business logic error)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

# Only run if authenticated
if [ -n "$BEARER_TOKEN" ]; then
    START_TIME_4=$(date -u -d "+8 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_4=$(date -u -d "+9 hours" +"%Y-%m-%dT%H:%M:%SZ")
    UNIQUE_ID=$(date +%s%N | cut -b1-13)

    read -r -d '' PAYLOAD_BAD_AREA <<EOF || true
{
  "activityId": "sdep-test-activity-bad-area-$UNIQUE_ID",
  "url": "http://sdep-test.example.com/bad-area-$UNIQUE_ID",
  "registrationNumber": "REGBAD001",
  "address": {
    "thoroughfare": "Bad Area Street",
    "locatorDesignatorNumber": 200,
    "postCode": "2000BB",
    "postName": "Nowhere"
  },
  "temporal": {
    "startDatetime": "$START_TIME_4",
    "endDatetime": "$END_TIME_4"
  },
  "areaId": "00000000-0000-0000-0000-000000000000",
  "numberOfGuests": 3
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_BAD_AREA" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 422 ]; then
        if echo "$body" | grep -qi "area.*not found"; then
            echo "✅ Test 4 passed: Non-existent area correctly returned 422 with area not found"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 4 failed: Expected area not found message in response"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 4 failed: Expected 422 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 4 (requires authentication)"
fi

echo

# Test 5: Versioning - submit same activityId twice
echo "Test 5: Versioning - submit same activityId twice"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL_TESTS=$((TOTAL_TESTS + 1))

if [ -n "$BEARER_TOKEN" ]; then
    VERSIONED_ID="sdep-test-activity-versioned-$(date +%s)"
    START_TIME_V=$(date -u -d "+10 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_V=$(date -u -d "+11 hours" +"%Y-%m-%dT%H:%M:%SZ")

    # Submit v1
    read -r -d '' PAYLOAD_V1 <<EOF || true
{
  "activityId": "$VERSIONED_ID",
  "url": "http://sdep-test.example.com/versioned-v1-$(date +%s%N | cut -b1-13)",
  "registrationNumber": "REGV1",
  "address": {
    "thoroughfare": "Versioned Street",
    "locatorDesignatorNumber": 1,
    "postCode": "1000AA",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME_V",
    "endDatetime": "$END_TIME_V"
  },
  "areaId": "$AREA_ID_1",
  "numberOfGuests": 2
}
EOF

    curl -s -o /dev/null -w "" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_V1" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities"

    START_TIME_V2=$(date -u -d "+12 hours" +"%Y-%m-%dT%H:%M:%SZ")
    END_TIME_V2=$(date -u -d "+13 hours" +"%Y-%m-%dT%H:%M:%SZ")

    # Submit v2 with same activityId
    read -r -d '' PAYLOAD_V2 <<EOF || true
{
  "activityId": "$VERSIONED_ID",
  "url": "http://sdep-test.example.com/versioned-v2-$(date +%s%N | cut -b1-13)",
  "registrationNumber": "REGV2",
  "address": {
    "thoroughfare": "Versioned Street",
    "locatorDesignatorNumber": 2,
    "postCode": "2000BB",
    "postName": "Amsterdam"
  },
  "temporal": {
    "startDatetime": "$START_TIME_V2",
    "endDatetime": "$END_TIME_V2"
  },
  "areaId": "$AREA_ID_1",
  "numberOfGuests": 3
}
EOF

    response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${BEARER_TOKEN}" \
        -d "$PAYLOAD_V2" \
        "${BACKEND_BASE_URL}/api/${API_VERSION}/str/activities")

    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')

    echo "Response: $body"
    echo "HTTP Status: $http_code"
    echo

    if [ "$http_code" -eq 201 ]; then
        if echo "$body" | grep -q "\"activityId\":\"${VERSIONED_ID}\""; then
            echo "✅ Test 5 passed: Versioned activity submission returned latest"
            PASSED_TESTS=$((PASSED_TESTS + 1))
        else
            echo "❌ Test 5 failed: Expected activityId to match versioned ID"
            FAILED_TESTS=$((FAILED_TESTS + 1))
        fi
    else
        echo "❌ Test 5 failed: Expected 201 but got $http_code"
        FAILED_TESTS=$((FAILED_TESTS + 1))
    fi
else
    echo "⏭️  Skipping Test 5 (requires authentication)"
fi

echo

# Summary
echo "═══════════════════════════════════════"
echo "Test Summary:"
echo "  Total:  $TOTAL_TESTS"
echo "  Passed: $PASSED_TESTS ✅"
echo "  Failed: $FAILED_TESTS ❌"
echo "═══════════════════════════════════════"

if [ $FAILED_TESTS -eq 0 ]; then
    echo "✅ All activity endpoint tests passed!"
    exit 0
else
    echo "❌ Some activity endpoint tests failed!"
    exit 1
fi
