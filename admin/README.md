# libSQL HTTP API - curl Commands

## Overview
The libSQL database (sqld) is accessible via HTTP API:
- **Direct access**: `http://127.0.0.1:8000` (sqld port)
- **Via nginx proxy**: `http://127.0.0.1:8080/db-admin` (recommended)

**Note**: Use `127.0.0.1` instead of `localhost` to avoid IPv6 connection issues. Alternatively, use `curl -4` to force IPv4.

**Important**: The API expects `"stmt"` as an **array** containing the SQL string: `{"stmt": ["SQL here"]}`

## 1. Query All Messages
Get all messages from the msg table:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT * FROM msg ORDER BY timestamp DESC LIMIT 10"]}' | jq .
```

## 2. Count Total Messages
Get the total number of messages:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT COUNT(*) as total_messages FROM msg"]}' | jq .
```

## 3. Query Messages by Topic
Get messages from a specific topic (exact match):

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT ulid, topic, payload, datetime(timestamp/1000, \"unixepoch\") as time FROM msg WHERE topic = \"cmd/test\" ORDER BY timestamp DESC LIMIT 10"]}' | jq .
```

Query messages matching a topic pattern:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT ulid, topic, payload, datetime(timestamp/1000, \"unixepoch\") as time FROM msg WHERE topic LIKE \"data/%\" ORDER BY timestamp DESC LIMIT 10"]}' | jq .
```

## 4. Query Messages by Time Range
Get messages from the last hour:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT ulid, topic, payload, datetime(timestamp/1000, \"unixepoch\") as time FROM msg WHERE timestamp > (strftime(\"%s\", \"now\") - 3600) * 1000 ORDER BY timestamp DESC"]}' | jq .
```

## 5. Query Latest Message per Topic
Get the most recent message for each topic:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT topic, payload, MAX(timestamp) as latest_timestamp, datetime(MAX(timestamp)/1000, \"unixepoch\") as time FROM msg GROUP BY topic ORDER BY latest_timestamp DESC"]}' | jq .
```

## 6. Search Messages by Payload Content
Search for messages containing specific text in payload:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT ulid, topic, payload, datetime(timestamp/1000, \"unixepoch\") as time FROM msg WHERE payload LIKE \"%temperature%\" ORDER BY timestamp DESC LIMIT 10"]}' | jq .
```

## 7. Get Database Statistics
Get statistics about the database:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT COUNT(*) as total_messages, COUNT(DISTINCT topic) as unique_topics, MIN(timestamp) as first_message, MAX(timestamp) as last_message FROM msg"]}' | jq .
```

## 8. Get Topics List
Get all unique topics:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT DISTINCT topic, COUNT(*) as message_count FROM msg GROUP BY topic ORDER BY message_count DESC"]}' | jq .
```

## 9. Query Specific Message by ULID
Get a specific message by its ULID:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT * FROM msg WHERE ulid = \"01JAQX7K8VXXXXXXXXXXXXX\""]}' | jq .
```

## 10. Delete Old Messages
Delete messages older than 30 days:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["DELETE FROM msg WHERE timestamp < (strftime(\"%s\", \"now\") - 2592000) * 1000"]}' | jq .
```

## 11. Check All Tables in Database
List all tables in the database:

```bash
curl -s -X POST http://127.0.0.1:8080/db-admin/v1/execute \
  -H "Content-Type: application/json" \
  -d '{"stmt": ["SELECT name FROM sqlite_master WHERE type=\"table\""]}' | jq .
```

## Example Response Format
```json
{
  "result": {
    "cols": [
      {"name": "ulid", "decltype": "TEXT"},
      {"name": "topic", "decltype": "TEXT"},
      {"name": "payload", "decltype": "TEXT"},
      {"name": "timestamp", "decltype": "INTEGER"}
    ],
    "rows": [
      [
        {"type": "text", "value": "01KBWFRSB884TWHGHTN7923K87"},
        {"type": "text", "value": "cmd/test"},
        {"type": "text", "value": "msg-cmd-f8f9e283"},
        {"type": "integer", "value": "1765113881"}
      ]
    ],
    "affected_row_count": 0,
    "last_insert_rowid": null,
    "replication_index": "2",
    "rows_read": 1,
    "rows_written": 0,
    "query_duration_ms": 0.091
  }
}
```
