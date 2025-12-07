# MQTT SQL Admin

MQTT SQL Admin is based on [Mosquitto](https://github.com/eclipse-mosquitto/mosquitto) MQTT broker and [libSQL](https://github.com/tursodatabase/libsql) database and features:
 - MQTT v5.0 protocol (plain MQTT, over TLS or WebSocket)
 - Authentication and authorization based on Access Control List
 - Message persistency in local libSQL database with remote HTTP access
 - Admin web user interface (served by internal Nginx)

## Development
To build Docker image run from the project's root directory
```bash
docker build --no-cache --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t mqtt-sql-admin:0.1.0 -f ./docker/Dockerfile .
```

To start the MQTT SQL Admin as Docker Swarm service
```bash
docker secret create dynsec.json mosquitto/config/dynsec.json
docker secret create msa.secrets msa.secrets
docker stack deploy -c compose.yml msa
```

To enable TLS termination inside the Mosquitto broker, mount your TLS certificate and key to `/mosquitto/security/` (e.g., `server.crt` and `server.key`) and uncomment the `certfile`/`keyfile` lines in [`mosquitto/config/mosquitto.conf`](mosquitto/config/mosquitto.conf). For mutual TLS (mTLS) with client certificates, also configure the `cafile` and `require_certificate` options.
