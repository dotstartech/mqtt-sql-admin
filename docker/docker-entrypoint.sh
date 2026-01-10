#!/bin/bash
set -e

# =============================================================================
# Credential Loading Functions
# =============================================================================
# Multi-source credential loading with fallback priority:
#   1. Docker secrets file (/run/secrets/mqbase.secrets)
#   2. Environment variables (MQBASE_USER, MQBASE_MQTT_USER)
#   3. Mounted config file (/mosquitto/config/secrets.conf)
#   4. Auto-generate random credentials (with warning)
# =============================================================================

# Generate a random password (16 alphanumeric characters)
generate_password() {
	tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16
}

# Load credentials from a secrets file (key=value format)
# Usage: load_from_file <filepath>
# Sets: MQBASE_USER, MQBASE_MQTT_USER (if found and not already set)
load_from_file() {
	local file="$1"
	if [ -f "$file" ]; then
		# Only set if not already defined
		if [ -z "$MQBASE_USER" ]; then
			MQBASE_USER=$(grep "^MQBASE_USER=" "$file" 2>/dev/null | cut -d'=' -f2-)
		fi
		if [ -z "$MQBASE_MQTT_USER" ]; then
			MQBASE_MQTT_USER=$(grep "^MQBASE_MQTT_USER=" "$file" 2>/dev/null | cut -d'=' -f2-)
		fi
		return 0
	fi
	return 1
}

# Load credentials with fallback priority
load_credentials() {
	local source=""
	
	# Priority 1: Docker secrets file (Swarm/Compose secrets)
	if [ -f /run/secrets/mqbase.secrets ]; then
		load_from_file /run/secrets/mqbase.secrets
		source="Docker secrets (/run/secrets/mqbase.secrets)"
	fi
	
	# Priority 2: Environment variables (already in env, check if set)
	# These are already available if passed via docker run -e or compose environment:
	# Nothing to do here - just note the source if values are set
	if [ -n "$MQBASE_USER" ] || [ -n "$MQBASE_MQTT_USER" ]; then
		if [ -z "$source" ]; then
			source="environment variables"
		fi
	fi
	
	# Priority 3: Mounted config file
	if [ -z "$MQBASE_USER" ] || [ -z "$MQBASE_MQTT_USER" ]; then
		if [ -f /mosquitto/config/secrets.conf ]; then
			load_from_file /mosquitto/config/secrets.conf
			if [ -n "$MQBASE_USER" ] || [ -n "$MQBASE_MQTT_USER" ]; then
				source="${source:+$source + }mounted config (/mosquitto/config/secrets.conf)"
			fi
		fi
	fi
	
	# Priority 4: Auto-generate if still missing
	if [ -z "$MQBASE_USER" ]; then
		local gen_pass=$(generate_password)
		MQBASE_USER="admin:${gen_pass}"
		echo "=============================================="
		echo "WARNING: No MQBASE_USER credentials found!"
		echo "Auto-generated credentials for HTTP Basic Auth:"
		echo "  Username: admin"
		echo "  Password: ${gen_pass}"
		echo "=============================================="
		source="${source:+$source + }auto-generated (MQBASE_USER)"
	fi
	
	if [ -z "$MQBASE_MQTT_USER" ]; then
		local gen_pass=$(generate_password)
		MQBASE_MQTT_USER="admin:${gen_pass}"
		echo "=============================================="
		echo "WARNING: No MQBASE_MQTT_USER credentials found!"
		echo "Auto-generated credentials for MQTT:"
		echo "  Username: admin"
		echo "  Password: ${gen_pass}"
		echo "=============================================="
		source="${source:+$source + }auto-generated (MQBASE_MQTT_USER)"
	fi
	
	echo "Credentials loaded from: $source"
}

# Create credential files for nginx and web UI
setup_credential_files() {
	# Parse MQBASE_MQTT_USER (format: username:password) for web client JSON
	local mqtt_username=$(echo "$MQBASE_MQTT_USER" | cut -d':' -f1)
	local mqtt_password=$(echo "$MQBASE_MQTT_USER" | cut -d':' -f2-)
	echo "{\"username\":\"$mqtt_username\",\"password\":\"$mqtt_password\"}" > /tmp/mqtt-credentials.json
	chown admin:admin /tmp/mqtt-credentials.json
	chmod 644 /tmp/mqtt-credentials.json
	
	# Parse MQBASE_USER (format: username:password) for HTTP Basic Auth htpasswd
	local db_username=$(echo "$MQBASE_USER" | cut -d':' -f1)
	local db_password=$(echo "$MQBASE_USER" | cut -d':' -f2-)
	echo "$db_username:$(echo -n "$db_password" | openssl passwd -apr1 -stdin)" > /tmp/htpasswd
	chown admin:admin /tmp/htpasswd
	chmod 644 /tmp/htpasswd
}

# =============================================================================
# Main Entrypoint
# =============================================================================

user="$(id -u)"
if [ "$user" = '0' ]; then
	# Ensure mosquitto directories exist
	mkdir -p /mosquitto/data /mosquitto/log /mosquitto/config
	
	# Set ownership for writable directories only (skip read-only mounted files like TLS certs)
	chown -R admin:admin /mosquitto/data /mosquitto/log /mosquitto/config 2>/dev/null || true
	
	# Ensure proper permissions for data directory (sqld needs write access)
	chmod -R 755 /mosquitto/data
	
	# Create nginx temp directories and set permissions
	mkdir -p /tmp/nginx_client_body /tmp/nginx_proxy /tmp/nginx_fastcgi /tmp/nginx_uwsgi /tmp/nginx_scgi
	chown -R admin:admin /tmp/nginx_* /var/log/nginx
	chmod -R 755 /tmp/nginx_* /var/log/nginx
	
	# Load credentials from multiple sources with fallback
	load_credentials
	
	# Create credential files for nginx and web UI
	setup_credential_files
	
	# Create app config JSON from environment variables
	# These come from mqbase.properties via env_file in compose.yml
	app_version="${version:-}"
	app_title="${title:-}"
	app_logo="${logo:-}"
	app_favicon="${favicon:-}"
	
	# Create JSON file with version, title, logo, and favicon (empty values if not set)
	echo "{\"version\":\"${app_version}\",\"title\":\"${app_title}\",\"logo\":\"${app_logo}\",\"favicon\":\"${app_favicon}\"}" > /tmp/app-config.json
	chown admin:admin /tmp/app-config.json
	chmod 644 /tmp/app-config.json
	
	# Switch to admin user and execute the command
	exec su-exec admin "$@"
else
	# If not running as root, just execute the command
	exec "$@"
fi