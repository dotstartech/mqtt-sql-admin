#!/bin/bash
# Integration test script for mqtt-sql-admin
# Tests MQTT message persistence and topic exclusion
#
# Topic structure: {data|cmd}/{dev|test|prod}/...
# Exclusion patterns: cmd/# (transient commands not persisted)
#
# Test user can only publish to +/test/# topics

set -e

BROKER="${MQTT_BROKER:-127.0.0.1}"
PORT="${MQTT_PORT:-1883}"
USER="${MQTT_USER:-test}"
PASS="${MQTT_PASS:-test}"
DB_URL="${DB_URL:-http://127.0.0.1:8080/db-admin/}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

PASSED=0
FAILED=0

log_pass() { echo -e "${GREEN}✓ PASS${NC}: $1"; PASSED=$((PASSED + 1)); }
log_fail() { echo -e "${RED}✗ FAIL${NC}: $1"; FAILED=$((FAILED + 1)); }
log_info() { echo -e "${YELLOW}→${NC} $1"; }

# Query database and return count
db_count() {
    curl -s -X POST "$DB_URL" \
        -H "Content-Type: application/json" \
        -d '{"statements": ["SELECT COUNT(*) FROM msg"]}' | \
        jq -r '.[0].results.rows[0][0]'
}

# Query database for messages matching topic pattern
db_find_topic() {
    local topic="$1"
    curl -s -X POST "$DB_URL" \
        -H "Content-Type: application/json" \
        -d "{\"statements\": [\"SELECT COUNT(*) FROM msg WHERE topic = '$topic'\"]}" | \
        jq -r '.[0].results.rows[0][0]'
}

# Generate unique test ID
TEST_ID=$(date +%s)_$(head -c 4 /dev/urandom | xxd -p)

echo "========================================"
echo "MQTT-SQL-Admin Integration Test"
echo "========================================"
echo "Broker: $BROKER:$PORT"
echo "User: $USER"
echo "DB URL: $DB_URL"
echo "Test ID: $TEST_ID"
echo "========================================"
echo ""

# Get initial count
INITIAL_COUNT=$(db_count)
log_info "Initial message count: $INITIAL_COUNT"
echo ""

# -----------------------------------------
# Test 1: Persistent message (data/test/...)
# -----------------------------------------
echo "--- Test 1: Persistent message ---"
TOPIC_PERSIST="data/test/sensor"
MSG_PERSIST="{\"test_id\":\"$TEST_ID\",\"type\":\"persistent\",\"value\":42}"

log_info "Publishing to $TOPIC_PERSIST (should be persisted)"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_PERSIST" -m "$MSG_PERSIST" -q 1

sleep 1
COUNT_AFTER_1=$(db_count)
if [ "$COUNT_AFTER_1" -gt "$INITIAL_COUNT" ]; then
    log_pass "Message count increased ($INITIAL_COUNT -> $COUNT_AFTER_1)"
else
    log_fail "Message count did not increase ($INITIAL_COUNT -> $COUNT_AFTER_1)"
fi
echo ""

# -----------------------------------------
# Test 2: Transient message (cmd/test/...)
# -----------------------------------------
echo "--- Test 2: Transient message (excluded) ---"
TOPIC_TRANSIENT="cmd/test/action"
MSG_TRANSIENT="{\"test_id\":\"$TEST_ID\",\"type\":\"transient\",\"action\":\"ping\"}"

log_info "Publishing to $TOPIC_TRANSIENT (should NOT be persisted - excluded by cmd/#)"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_TRANSIENT" -m "$MSG_TRANSIENT" -q 0

sleep 1
COUNT_AFTER_2=$(db_count)
if [ "$COUNT_AFTER_2" -eq "$COUNT_AFTER_1" ]; then
    log_pass "Message count unchanged ($COUNT_AFTER_1 -> $COUNT_AFTER_2) - correctly excluded"
else
    log_fail "Message count changed ($COUNT_AFTER_1 -> $COUNT_AFTER_2) - should have been excluded"
fi
echo ""

# -----------------------------------------
# Test 3: Multiple persistent messages
# -----------------------------------------
echo "--- Test 3: Multiple persistent messages ---"
for i in 1 2 3; do
    TOPIC="data/test/batch_$i"
    MSG="{\"test_id\":\"$TEST_ID\",\"batch\":$i}"
    mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC" -m "$MSG" -q 1
    log_info "Published to $TOPIC"
done

sleep 1
COUNT_AFTER_3=$(db_count)
EXPECTED=$((COUNT_AFTER_2 + 3))
if [ "$COUNT_AFTER_3" -eq "$EXPECTED" ]; then
    log_pass "3 messages added ($COUNT_AFTER_2 -> $COUNT_AFTER_3)"
else
    log_fail "Expected $EXPECTED messages, got $COUNT_AFTER_3"
fi
echo ""

# -----------------------------------------
# Test 4: Verify specific topic in database
# -----------------------------------------
echo "--- Test 4: Verify topic in database ---"
FOUND=$(db_find_topic "$TOPIC_PERSIST")
if [ "$FOUND" -ge 1 ]; then
    log_pass "Found $FOUND message(s) with topic '$TOPIC_PERSIST'"
else
    log_fail "No messages found with topic '$TOPIC_PERSIST'"
fi

FOUND_CMD=$(db_find_topic "$TOPIC_TRANSIENT")
if [ "$FOUND_CMD" -eq 0 ]; then
    log_pass "No messages found with excluded topic '$TOPIC_TRANSIENT'"
else
    log_fail "Found $FOUND_CMD message(s) with excluded topic '$TOPIC_TRANSIENT' (should be 0)"
fi
echo ""

# -----------------------------------------
# Test 5: Retained messages
# -----------------------------------------
echo "--- Test 5: Retained messages ---"
TOPIC_RETAINED_1="data/test/state/device1"
TOPIC_RETAINED_2="data/test/state/device2"
MSG_RETAINED_1="{\"test_id\":\"$TEST_ID\",\"type\":\"retained\",\"device\":\"device1\",\"status\":\"online\"}"
MSG_RETAINED_2="{\"test_id\":\"$TEST_ID\",\"type\":\"retained\",\"device\":\"device2\",\"status\":\"active\"}"

log_info "Publishing retained message to $TOPIC_RETAINED_1"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_RETAINED_1" -m "$MSG_RETAINED_1" -q 1 -r

log_info "Publishing retained message to $TOPIC_RETAINED_2"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_RETAINED_2" -m "$MSG_RETAINED_2" -q 1 -r

sleep 1
COUNT_AFTER_5=$(db_count)
EXPECTED=$((COUNT_AFTER_3 + 2))
if [ "$COUNT_AFTER_5" -ge "$EXPECTED" ]; then
    log_pass "Retained messages persisted ($COUNT_AFTER_3 -> $COUNT_AFTER_5)"
else
    log_fail "Expected at least $EXPECTED messages, got $COUNT_AFTER_5"
fi
echo ""

# -----------------------------------------
# Test 6: Delete with ULID property (targeted delete)
# -----------------------------------------
echo "--- Test 6: Delete with ULID property ---"
TOPIC_DELETE_ULID="data/test/delete_ulid_$TEST_ID"

# Publish first message
log_info "Publishing first retained message to $TOPIC_DELETE_ULID"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DELETE_ULID" -m '{"msg":"first"}' -q 1 -r -V 5
sleep 0.5

# Get the ULID of the first message
FIRST_ULID=$(curl -s -X POST "$DB_URL" \
    -H "Content-Type: application/json" \
    -d "{\"statements\": [\"SELECT ulid FROM msg WHERE topic = '$TOPIC_DELETE_ULID' ORDER BY ulid DESC LIMIT 1\"]}" | \
    jq -r '.[0].results.rows[0][0]')
log_info "First message ULID: $FIRST_ULID"

# Publish second message (will be retained)
log_info "Publishing second retained message to $TOPIC_DELETE_ULID"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DELETE_ULID" -m '{"msg":"second"}' -q 1 -r -V 5
sleep 0.5

COUNT_BEFORE_DELETE=$(db_find_topic "$TOPIC_DELETE_ULID")
log_info "Messages before targeted delete: $COUNT_BEFORE_DELETE"

# Delete first message by passing ULID as user property
log_info "Deleting first message by ULID property"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DELETE_ULID" -r -n -V 5 \
    -D publish user-property ulid "$FIRST_ULID"
sleep 0.5

COUNT_AFTER_DELETE=$(db_find_topic "$TOPIC_DELETE_ULID")
# Check that the second message still exists
REMAINING_MSG=$(curl -s -X POST "$DB_URL" \
    -H "Content-Type: application/json" \
    -d "{\"statements\": [\"SELECT payload FROM msg WHERE topic = '$TOPIC_DELETE_ULID' LIMIT 1\"]}" | \
    jq -r '.[0].results.rows[0][0]')

if [ "$COUNT_AFTER_DELETE" -eq 1 ] && [[ "$REMAINING_MSG" == *"second"* ]]; then
    log_pass "Targeted delete worked - first message deleted, second remains ($COUNT_BEFORE_DELETE -> $COUNT_AFTER_DELETE)"
else
    log_fail "Targeted delete failed - expected 1 message with 'second', got $COUNT_AFTER_DELETE messages, content: $REMAINING_MSG"
fi
echo ""

# -----------------------------------------
# Test 7: Delete without ULID (fallback - deletes most recent)
# -----------------------------------------
echo "--- Test 7: Delete without ULID (fallback) ---"
TOPIC_DELETE_FALLBACK="data/test/delete_fallback_$TEST_ID"

# Publish a retained message
log_info "Publishing retained message to $TOPIC_DELETE_FALLBACK"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DELETE_FALLBACK" -m '{"msg":"to_delete"}' -q 1 -r -V 5
sleep 0.5

COUNT_BEFORE_FALLBACK=$(db_find_topic "$TOPIC_DELETE_FALLBACK")
log_info "Messages before fallback delete: $COUNT_BEFORE_FALLBACK"

# Delete by sending empty retained (no ULID property - uses fallback)
log_info "Deleting message using fallback (no ULID property)"
mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DELETE_FALLBACK" -r -n -V 5
sleep 0.5

COUNT_AFTER_FALLBACK=$(db_find_topic "$TOPIC_DELETE_FALLBACK")
if [ "$COUNT_AFTER_FALLBACK" -eq 0 ]; then
    log_pass "Fallback delete worked - message deleted ($COUNT_BEFORE_FALLBACK -> $COUNT_AFTER_FALLBACK)"
else
    log_fail "Fallback delete failed - expected 0 messages, got $COUNT_AFTER_FALLBACK"
fi
echo ""

# -----------------------------------------
# Test 8: Query recent messages
# -----------------------------------------
echo "--- Test 8: Recent messages ---"
log_info "Last 5 messages in database:"
curl -s -X POST "$DB_URL" \
    -H "Content-Type: application/json" \
    -d '{"statements": ["SELECT ulid, topic, payload FROM msg ORDER BY ulid DESC LIMIT 5"]}' | \
    jq -r '.[0].results.rows[] | "  \(.[1]): \(.[2])"'
echo ""

# -----------------------------------------
# Summary
# -----------------------------------------
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo "========================================"

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
exit 0
