# libSQL Mosquitto Plugin

A Mosquitto MQTT broker plugin that persists messages to a libSQL/SQLite database with ULID-based identifiers.

## Features

- **ULID Generation**: Each message receives a unique, time-sortable ULID (Universally Unique Lexicographically Sortable Identifier)
- **Batch Processing**: Messages are queued and written in batches for optimal performance
- **Topic Exclusion**: Configure topics to exclude from persistence
- **Header Storage**: Store MQTT v5 user properties as headers (with exclusion support)
- **Data Retention**: Automatic cleanup of messages older than configured days
- **Retained Message Deletion**: Properly handles MQTT retained message deletion

## Files

- `libsql_plugin.c` - Main plugin source code
- `Makefile` - Build configuration

## Building

The plugin is built automatically as part of the Docker image build process. See `docker/Dockerfile` for the complete build setup.

### Manual Build

If building manually (outside Docker):

```bash
# From the mosquitto source directory with this plugin in plugins/sql/
make -C plugins/sql
```

## Debug Logging

The plugin includes conditional debug logging that is **disabled by default** for optimal performance in production.

### Enabling Debug Logging

To enable verbose debug output, add `-DDEBUG_LOGGING` to the CFLAGS when building the plugin.

#### Option 1: Modify the Dockerfile (Recommended for Development)

Edit `docker/Dockerfile` and add `-DDEBUG_LOGGING` to the CFLAGS line:

```dockerfile
# Before (production):
CFLAGS="-Wall -O2 -I/build/lws/include -I/build" \

# After (debug):
CFLAGS="-Wall -O2 -I/build/lws/include -I/build -DDEBUG_LOGGING" \
```

Then rebuild the Docker image:
```bash
./docker/build.sh
```

#### Option 2: Set Environment Variable (Alternative)

You can also set CFLAGS as an environment variable before building:

```bash
export CFLAGS="-Wall -O2 -DDEBUG_LOGGING"
make -C plugins/sql
```

### Debug Log Messages

When enabled, the following debug messages are logged:

| Message | Description |
|---------|-------------|
| `Batch: N inserts, M deletes committed` | Batch processing statistics |
| `Excluded topic from persistence: <topic>` | Topic matched exclusion pattern |
| `Found ULID in properties: <ulid>` | ULID extracted from message properties |
| `Enqueued delete: topic=<topic> ulid=<ulid>` | Delete operation queued |
| `Enqueued fallback delete: topic=<topic>` | Delete without specific ULID |
| `Enqueued: topic=<topic> retain=<0/1> qos=<0/1/2> headers=<headers>` | Message queued for insert |

### Viewing Logs

Debug logs appear in the Mosquitto broker logs:

```bash
# Docker Swarm
docker service logs msa_mqtt-sql-admin -f

# Docker container
docker logs -f <container_id>
```

## Configuration Options

Configure the plugin in `mosquitto.conf`:

```conf
plugin /usr/lib/libsql_plugin.so

# Exclude topics from persistence (comma-separated, supports + and # wildcards)
plugin_opt_exclude_topics $SYS/#,test/#

# Batch insert size (default: 100)
plugin_opt_batch_size 100

# Flush interval in milliseconds (default: 50)
plugin_opt_flush_interval 50

# Data retention in days (0 = disabled, default: 0)
plugin_opt_retention_days 30

# Exclude specific headers/user properties from storage (comma-separated)
# Use '#' to disable all header storage
plugin_opt_exclude_headers timestamp,trace-id
```

## Database Schema

```sql
CREATE TABLE msg (
    ulid TEXT PRIMARY KEY,
    topic TEXT NOT NULL,
    payload TEXT NOT NULL,
    retain INTEGER NOT NULL DEFAULT 0,
    qos INTEGER NOT NULL DEFAULT 0,
    headers TEXT
);

-- Indexes for performance
CREATE INDEX idx_msg_topic ON msg(topic);
CREATE INDEX idx_msg_topic_ulid ON msg(topic, ulid DESC);
```

## Performance Notes

- **WAL Mode**: The plugin enables SQLite WAL mode for better concurrent read/write performance
- **Batch Inserts**: Messages are batched to reduce transaction overhead
- **Queue Limit**: Maximum queue size is 15,000 entries to prevent unbounded memory growth
- **Prepared Statements**: All SQL operations use prepared statements for efficiency and security
