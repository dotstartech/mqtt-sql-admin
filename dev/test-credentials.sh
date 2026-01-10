#!/bin/bash
# Test all credential loading methods

PASSED=0
FAILED=0

pass() { echo "✓ PASS: $1"; PASSED=$((PASSED + 1)); }
fail() { echo "✗ FAIL: $1"; FAILED=$((FAILED + 1)); }

cleanup() {
    docker rm -f mqbase-cred-test 2>/dev/null || true
}

wait_for_container() {
    local max_wait=15
    local count=0
    while [ $count -lt $max_wait ]; do
        if curl -s -o /dev/null http://127.0.0.1:18080/health 2>/dev/null; then
            return 0
        fi
        sleep 1
        ((count++))
    done
    return 1
}

test_http_auth() {
    local user="$1"
    local pass="$2"
    local expected="$3"
    # Use /mqtt-credentials which requires auth and returns JSON
    local code=$(curl -s -o /dev/null -w "%{http_code}" -u "$user:$pass" http://127.0.0.1:18080/mqtt-credentials 2>/dev/null)
    if [ "$code" = "$expected" ]; then
        return 0
    else
        echo "  (expected $expected, got $code)"
        return 1
    fi
}

echo "========================================"
echo "Credential Loading Test Suite"
echo "========================================"
echo ""

cleanup

# =============================================================================
echo "=== TEST 1: Auto-generated credentials ==="
# =============================================================================
docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    # Extract auto-generated password from logs
    HTTP_PASS=$(docker logs mqbase-cred-test 2>&1 | grep -A3 "HTTP Basic Auth" | grep "Password:" | awk '{print $2}')
    
    if [ -n "$HTTP_PASS" ]; then
        pass "Auto-generated password printed to logs"
    else
        fail "Auto-generated password not found in logs"
    fi
    
    if test_http_auth "admin" "$HTTP_PASS" "200"; then
        pass "Auth with auto-generated password works"
    else
        fail "Auth with auto-generated password failed"
    fi
    
    if test_http_auth "admin" "wrongpass" "401"; then
        pass "Wrong password correctly rejected"
    else
        fail "Wrong password not rejected"
    fi
    
    # Check log message
    if docker logs mqbase-cred-test 2>&1 | grep -q "auto-generated"; then
        pass "Log shows 'auto-generated' source"
    else
        fail "Log doesn't show correct source"
    fi
else
    fail "Container failed to start"
fi
cleanup
echo ""

# =============================================================================
echo "=== TEST 2: Environment variables ==="
# =============================================================================
docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    -e MQBASE_USER=envuser:envpass123 \
    -e MQBASE_MQTT_USER=mqttuser:mqttpass456 \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    if test_http_auth "envuser" "envpass123" "200"; then
        pass "Auth with env var credentials works"
    else
        fail "Auth with env var credentials failed"
    fi
    
    if test_http_auth "envuser" "wrongpass" "401"; then
        pass "Wrong password correctly rejected"
    else
        fail "Wrong password not rejected"
    fi
    
    if test_http_auth "admin" "admin" "401"; then
        pass "Default credentials correctly rejected"
    else
        fail "Default credentials should be rejected"
    fi
    
    # Check log message
    if docker logs mqbase-cred-test 2>&1 | grep -q "environment variables"; then
        pass "Log shows 'environment variables' source"
    else
        fail "Log doesn't show correct source"
    fi
    
    # Check no warning was printed
    if ! docker logs mqbase-cred-test 2>&1 | grep -q "WARNING.*credentials"; then
        pass "No credential warning printed"
    else
        fail "Unexpected credential warning printed"
    fi
else
    fail "Container failed to start"
fi
cleanup
echo ""

# =============================================================================
echo "=== TEST 3: Mounted secrets file ==="
# =============================================================================
# Create temporary secrets file
TEMP_SECRETS=$(mktemp)
echo "MQBASE_USER=fileuser:filepass789" > "$TEMP_SECRETS"
echo "MQBASE_MQTT_USER=filemqtt:filemqttpass" >> "$TEMP_SECRETS"

docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    -v "$TEMP_SECRETS:/mosquitto/config/secrets.conf:ro" \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    if test_http_auth "fileuser" "filepass789" "200"; then
        pass "Auth with mounted file credentials works"
    else
        fail "Auth with mounted file credentials failed"
    fi
    
    if test_http_auth "fileuser" "wrongpass" "401"; then
        pass "Wrong password correctly rejected"
    else
        fail "Wrong password not rejected"
    fi
    
    # Check log message
    if docker logs mqbase-cred-test 2>&1 | grep -q "mounted config"; then
        pass "Log shows 'mounted config' source"
    else
        fail "Log doesn't show correct source"
    fi
else
    fail "Container failed to start"
fi
cleanup
rm -f "$TEMP_SECRETS"
echo ""

# =============================================================================
echo "=== TEST 4: Priority - Env vars override mounted file ==="
# =============================================================================
TEMP_SECRETS=$(mktemp)
echo "MQBASE_USER=fileuser:filepass" > "$TEMP_SECRETS"
echo "MQBASE_MQTT_USER=filemqtt:filemqttpass" >> "$TEMP_SECRETS"

docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    -e MQBASE_USER=envuser:envpass \
    -e MQBASE_MQTT_USER=envmqtt:envmqttpass \
    -v "$TEMP_SECRETS:/mosquitto/config/secrets.conf:ro" \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    # Env vars should take priority
    if test_http_auth "envuser" "envpass" "200"; then
        pass "Env vars take priority over mounted file"
    else
        fail "Env vars should take priority"
    fi
    
    # File credentials should NOT work
    if test_http_auth "fileuser" "filepass" "401"; then
        pass "Mounted file credentials correctly overridden"
    else
        fail "Mounted file credentials should be overridden"
    fi
else
    fail "Container failed to start"
fi
cleanup
rm -f "$TEMP_SECRETS"
echo ""

# =============================================================================
echo "=== TEST 5: Partial credentials (only MQBASE_USER) ==="
# =============================================================================
docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    -e MQBASE_USER=partialuser:partialpass \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    if test_http_auth "partialuser" "partialpass" "200"; then
        pass "Partial env var (MQBASE_USER only) works"
    else
        fail "Partial env var failed"
    fi
    
    # MQTT user should be auto-generated
    if docker logs mqbase-cred-test 2>&1 | grep -q "No MQBASE_MQTT_USER credentials"; then
        pass "Missing MQBASE_MQTT_USER triggers auto-generation"
    else
        fail "Should auto-generate missing MQBASE_MQTT_USER"
    fi
    
    # But no warning for MQBASE_USER
    if ! docker logs mqbase-cred-test 2>&1 | grep -q "No MQBASE_USER credentials"; then
        pass "No warning for provided MQBASE_USER"
    else
        fail "Should not warn about provided MQBASE_USER"
    fi
else
    fail "Container failed to start"
fi
cleanup
echo ""

# =============================================================================
echo "=== TEST 6: Special characters in password ==="
# =============================================================================
docker run -d --name mqbase-cred-test \
    -p 11883:1883 -p 18080:8080 \
    -e 'MQBASE_USER=admin:p@ss:w0rd!#$%' \
    -e 'MQBASE_MQTT_USER=mqtt:mqtt123' \
    mqbase:latest >/dev/null 2>&1

if wait_for_container; then
    if test_http_auth "admin" 'p@ss:w0rd!#$%' "200"; then
        pass "Special characters in password work"
    else
        fail "Special characters in password failed"
    fi
else
    fail "Container failed to start"
fi
cleanup
echo ""

# =============================================================================
echo "========================================"
echo "Test Summary"
echo "========================================"
echo "Passed: $PASSED"
echo "Failed: $FAILED"
echo "========================================"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
