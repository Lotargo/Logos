import os
import sys
import json
import argparse
import datetime
import yaml
from git_utils import get_git_info
from db import LogosDB
from linear_client import LinearClient

class TelemetryLogger:
    def __init__(self, config_path="v9/telemetry/config.yaml"):
        self.config = self._load_config(config_path)
        self.cache_path = os.environ.get("LOGOS_TELEMETRY_CACHE_PATH") or \
                          self.config.get("telemetry", {}).get("cache_path", "v9/telemetry/cache/logos_memory.jsonl")

        # Ensure cache directory exists
        os.makedirs(os.path.dirname(self.cache_path), exist_ok=True)

    def _load_config(self, path):
        if os.path.exists(path):
            with open(path, "r") as f:
                return yaml.safe_load(f)
        return {}

    def _get_base_event(self, event_type, event_source, session_id, message, payload=None, metadata=None):
        event = {
            "event_type": event_type,
            "event_source": event_source,
            "session_id": session_id,
            "message": message,
            "payload": payload or {},
            "metadata": metadata or {},
            "created_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        }

        # Add git info if enabled
        if self.config.get("git", {}).get("capture_commit_hash", True):
            event.update(get_git_info())

        return event

    def write_local(self, event_type, event_source, session_id, message, payload=None, metadata=None):
        event = self._get_base_event(event_type, event_source, session_id, message, payload, metadata)

        with open(self.cache_path, "a") as f:
            f.write(json.dumps(event) + "\n")

        # Optional: Check if we should create a Linear issue
        self._check_linear_triggers(event)

        return event

    def _check_linear_triggers(self, event):
        linear_cfg = self.config.get("linear", {})
        if not linear_cfg.get("enabled", False):
            return

        client = LinearClient()
        if not client.is_enabled():
            return

        should_create = False
        reason = ""

        if event["event_type"] == "fitness_evaluated":
            score = event["payload"].get("fitness_score", 0)
            if score >= linear_cfg.get("high_fitness_threshold", 0.95):
                should_create = True
                reason = f"High fitness detected: {score}"
            elif score <= linear_cfg.get("low_fitness_threshold", 0.10):
                should_create = True
                reason = f"Low fitness detected: {score}"

        if event["event_type"] == "error" and linear_cfg.get("create_issue_on_error", True):
            should_create = True
            reason = f"Critical error: {event['message']}"

        if should_create:
            title = f"Logos v9: {reason} ({event['session_id']})"
            description = f"Event Type: {event['event_type']}\nSource: {event['event_source']}\nMessage: {event['message']}\nPayload: {json.dumps(event['payload'], indent=2)}"
            issue = client.create_issue(title, description)
            if issue:
                # Log that we created an issue
                self.write_local("linear_issue_created", "telemetry_logger", event["session_id"],
                                 f"Created Linear issue {issue['url']}",
                                 payload={"linear_issue_id": issue["id"], "linear_issue_url": issue["url"], "reason": reason})

    def flush(self):
        if not os.path.exists(self.cache_path):
            print("No cache file found to flush.")
            return

        events = []
        with open(self.cache_path, "r") as f:
            for line in f:
                if line.strip():
                    events.append(json.loads(line))

        if not events:
            print("No events to flush.")
            return

        db = LogosDB()
        try:
            db.insert_events(events)
            print(f"Successfully flushed {len(events)} events to Neon.")
            # Clear cache after successful flush
            open(self.cache_path, "w").close()
        except Exception as e:
            print(f"Failed to flush events: {e}")

    def write_remote(self, event_type, event_source, session_id, message, payload=None, metadata=None):
        event = self._get_base_event(event_type, event_source, session_id, message, payload, metadata)
        db = LogosDB()
        try:
            db.insert_events([event])
            print("Successfully wrote event directly to Neon.")
        except Exception as e:
            print(f"Failed to write remote, falling back to local: {e}")
            self.write_local(event_type, event_source, session_id, message, payload, metadata)

def main():
    parser = argparse.ArgumentParser(description="Logos v9 Telemetry Logger")
    subparsers = parser.add_subparsers(dest="command")

    # init-db
    subparsers.add_parser("init-db")

    # test-connection
    subparsers.add_parser("test-connection")

    # write-local
    write_local_parser = subparsers.add_parser("write-local")
    write_local_parser.add_argument("--event-type", required=True)
    write_local_parser.add_argument("--event-source", required=True)
    write_local_parser.add_argument("--session-id", required=True)
    write_local_parser.add_argument("--message", required=True)
    write_local_parser.add_argument("--payload", help="JSON string or path to JSON file")
    write_local_parser.add_argument("--metadata", help="JSON string")

    # flush
    subparsers.add_parser("flush")

    # write-remote
    write_remote_parser = subparsers.add_parser("write-remote")
    write_remote_parser.add_argument("--event-type", required=True)
    write_remote_parser.add_argument("--event-source", required=True)
    write_remote_parser.add_argument("--session-id", required=True)
    write_remote_parser.add_argument("--message", required=True)
    write_remote_parser.add_argument("--payload", help="JSON string or path to JSON file")

    args = parser.parse_args()

    logger = TelemetryLogger()

    if args.command == "init-db":
        db = LogosDB()
        db.init_db("v9/telemetry/schema.sql")
        print("Database initialized with schema.")

    elif args.command == "test-connection":
        db = LogosDB()
        db.connect()
        print("Connection successful.")
        db.close()

    elif args.command == "write-local" or args.command == "write-remote":
        payload = {}
        if args.payload:
            if os.path.exists(args.payload):
                with open(args.payload, "r") as f:
                    payload = json.load(f)
            else:
                payload = json.loads(args.payload)

        metadata = json.loads(args.metadata) if args.metadata else {}

        if args.command == "write-local":
            logger.write_local(args.event_type, args.event_source, args.session_id, args.message, payload, metadata)
            print("Event logged locally.")
        else:
            logger.write_remote(args.event_type, args.event_source, args.session_id, args.message, payload, metadata)

    elif args.command == "flush":
        logger.flush()

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
