#!/bin/bash
# Test script to periodically publish messages to MQTT broker
# Alternates between persistent (data/test) and non-persistent (cmd/test) messages

BROKER="${MQTT_BROKER:-localhost}"
PORT="${MQTT_PORT:-1883}"
USER="${MQTT_USER:-admin}"
PASS="${MQTT_PASS:-admin}"
TOPIC_DATA="data/test"
TOPIC_CMD="cmd/test"
INTERVAL="${INTERVAL:-2}"

echo "Publishing to $BROKER:$PORT as $USER"
echo "Persistent topic: $TOPIC_DATA (QoS 1, retain)"
echo "Non-persistent topic: $TOPIC_CMD (QoS 0)"
echo "Interval: ${INTERVAL}s"
echo "Press Ctrl+C to stop"
echo ""

COUNT=0
while true; do
    RANDOM_ID=$(head -c 4 /dev/urandom | xxd -p)
    
    if [ $((COUNT % 2)) -eq 0 ]; then
        # Persistent message (QoS 1, retained)
        MSG="msg-data-${RANDOM_ID}"
        mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_DATA" -m "$MSG" -q 1 -r
        echo "Published [persistent]: $TOPIC_DATA -> $MSG"
    else
        # Non-persistent message (QoS 0, not retained)
        MSG="msg-cmd-${RANDOM_ID}"
        mosquitto_pub -h "$BROKER" -p "$PORT" -u "$USER" -P "$PASS" -t "$TOPIC_CMD" -m "$MSG" -q 0
        echo "Published [transient]:  $TOPIC_CMD -> $MSG"
    fi
    
    COUNT=$((COUNT + 1))
    sleep "$INTERVAL"
done
