#!/bin/bash
set -e

# Function to handle shutdown
shutdown() {
    echo "Shutting down services..."
    kill $NGINX_PID $SQLD_PID $MOSQUITTO_PID 2>/dev/null || true
    exit 0
}

# Trap SIGTERM and SIGINT
trap shutdown SIGTERM SIGINT

# Check if we can write to /mosquitto/data
if [ ! -w /mosquitto/data ]; then
    echo "ERROR: Cannot write to /mosquitto/data directory"
    echo "Current user: $(id)"
    echo "Directory permissions:"
    ls -la /mosquitto/
    exit 1
fi

# Start nginx for serving admin interface
echo "Starting nginx..."
nginx &
NGINX_PID=$!

# Give nginx time to start
sleep 1

# Check if nginx is still running
if ! kill -0 $NGINX_PID 2>/dev/null; then
    echo "ERROR: nginx failed to start"
    echo "=== Nginx error log ==="
    cat /var/log/nginx/error.log 2>/dev/null || echo "No nginx error log available"
    echo "=== End of nginx error log ==="
    echo "Trying to test nginx config:"
    nginx -t
    exit 1
fi

# Start sqld
echo "Starting sqld..."
sqld -d /mosquitto/data --http-listen-addr=0.0.0.0:8000 --enable-http-console &
SQLD_PID=$!

# Give sqld time to start
sleep 2

# Check if sqld is still running
if ! kill -0 $SQLD_PID 2>/dev/null; then
    echo "ERROR: sqld failed to start"
    exit 1
fi

# Start mosquitto in foreground as the main process
echo "Starting mosquitto..."
# Fix permissions on mosquitto.db if it exists (prevent world-readable warning)
chmod 0700 /mosquitto/data/mosquitto.db 2>/dev/null || true
/usr/sbin/mosquitto -c /mosquitto/config/mosquitto.conf &
MOSQUITTO_PID=$!

# Monitor all processes - if any exit, shut down all
while true; do
    if ! kill -0 $NGINX_PID 2>/dev/null; then
        echo "ERROR: nginx died unexpectedly"
        shutdown
    fi
    if ! kill -0 $SQLD_PID 2>/dev/null; then
        echo "ERROR: sqld died unexpectedly"
        shutdown
    fi
    if ! kill -0 $MOSQUITTO_PID 2>/dev/null; then
        echo "ERROR: mosquitto died unexpectedly"
        shutdown
    fi
    sleep 5
done