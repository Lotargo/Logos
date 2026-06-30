import os
import sys
import json
import argparse
import datetime
import time
import yaml
from git_utils import get_git_info
from db import LogosDB
from linear_client import LinearClient

class TelemetryLogger:
    def __init__(self, config_path="v9/telemetry/config.yaml"):
        self.config = self._load_config(config_path)
        self.cache_path = os.environ.get("LOGOS_TELEMETRY_CACHE_PATH") or \
                          self.config.get("telemetry", {}).get("cache_path", "v9/telemetry/cache/logos_memory.jsonl")
        self.last_flush_time = time.time()

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

        if self.config.get("git", {}).get("capture_commit_hash", True):
            event.update(get_git_info())

        return event

    def write_local(self, event_type, event_source, session_id, message, payload=None, metadata=None):
        event = self._get_base_event(event_type, event_source, session_id, message, payload, metadata)

        with open(self.cache_path, "a") as f:
            f.write(json.dumps(event) + "\n")

        self._check_linear_triggers(event)
        self._check_auto_flush()

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
                self.write_local("linear_issue_created", "telemetry_logger", event["session_id"],
                                 f"Created Linear issue {issue['url']}",
                                 payload={"linear_issue_id": issue["id"], "linear_issue_url": issue["url"], "reason": reason})

    def _check_auto_flush(self):
        batch_size = self.config.get('telemetry', {}).get('flush_batch_size', 100)
        if os.path.exists(self.cache_path) and os.path.getsize(self.cache_path) > batch_size * 1024:
            self.flush()
        if time.time() - self.last_flush_time > 3600:
            self.flush()

    def flush(self):
        if not os.path.exists(self.cache_path):
            print("No cache file found to flush.")
            return

        temp_path = self.cache_path + ".flushing"
        os.rename(self.cache_path, temp_path)

        events = []
        try:
            with open(temp_path, "r") as f:
                for line in f:
                    if line.strip():
                        events.append(json.loads(line))
        except Exception:
            os.remove(temp_path)
            return

        if not events:
            os.remove(temp_path)
            print("No events to flush.")
            return

        db = LogosDB()
        try:
            db.insert_events(events)
            print(f"Successfully flushed {len(events)} events to Neon.")
        except Exception as e:
            os.rename(temp_path, self.cache_path)
            print(f"Failed to flush events: {e}")
            return

        os.remove(temp_path)
        self.last_flush_time = time.time()

    def write_remote(self, event_type, event_source, session_id, message, payload=None, metadata=None):
        event = self._get_base_event(event_type, event_source, session_id, message, payload, metadata)
        db = LogosDB()
        try:
            db.insert_events([event])
            print("Successfully wrote event directly to Neon.")
        except Exception as e:
            print(f"Failed to write remote, falling back to local: {e}")
            self.write_local(event_type, event_source, session_id, message, payload, metadata)

    def fetch_knowledge(self, min_fitness=0.9):
        """Fetches best knowledge from the DB and outputs it in a format Lisp can easily parse."""
        db = LogosDB()
        try:
            knowledge = db.get_best_knowledge(min_fitness=min_fitness)
            axioms = db.get_discovered_axioms()

            output = {
                "status": "success",
                "asts": [k["ast"] for k in knowledge],
                "axioms": axioms
            }
            print(json.dumps(output))
        except Exception as e:
            fallback = db.get_best_knowledge_from_cache(self.cache_path, min_fitness)
            if fallback["asts"]:
                print(json.dumps({"status": "fallback", "asts": fallback["asts"], "axioms": fallback["axioms"]}))
            else:
                print(json.dumps({"status": "error", "message": str(e), "asts": [], "axioms": []}))

    def fetch_knowledge_lisp(self, min_fitness=0.9):
        """Fetch knowledge and output as Lisp sexps for direct parsing."""
        db = LogosDB()
        try:
            knowledge = db.get_best_knowledge(min_fitness=min_fitness)
            axioms = db.get_discovered_axioms()
        except Exception:
            fallback = db.get_best_knowledge_from_cache(self.cache_path, min_fitness)
            asts = fallback["asts"]
            axioms = fallback["axioms"]
        else:
            asts = [k["ast"] for k in knowledge]

        ast_strs = " ".join(f'"{str(x).replace(chr(34), chr(92) + chr(34))}"' for x in asts)
        axiom_strs = " ".join(f'"{str(x).replace(chr(34), chr(92) + chr(34))}"' for x in axioms)
        print(f"(:asts ({ast_strs}) :axioms ({axiom_strs}))")

def main():
    parser = argparse.ArgumentParser(description="Logos v9 Telemetry Logger")
    subparsers = parser.add_subparsers(dest="command")

    subparsers.add_parser("init-db")
    subparsers.add_parser("test-connection")

    write_local_parser = subparsers.add_parser("write-local")
    write_local_parser.add_argument("--event-type", required=True)
    write_local_parser.add_argument("--event-source", required=True)
    write_local_parser.add_argument("--session-id", required=True)
    write_local_parser.add_argument("--message", required=True)
    write_local_parser.add_argument("--payload", help="JSON string or path to JSON file")
    write_local_parser.add_argument("--metadata", help="JSON string")

    subparsers.add_parser("flush")

    write_remote_parser = subparsers.add_parser("write-remote")
    write_remote_parser.add_argument("--event-type", required=True)
    write_remote_parser.add_argument("--event-source", required=True)
    write_remote_parser.add_argument("--session-id", required=True)
    write_remote_parser.add_argument("--message", required=True)
    write_remote_parser.add_argument("--payload", help="JSON string or path to JSON file")

    fetch_parser = subparsers.add_parser("fetch-knowledge")
    fetch_parser.add_argument("--min-fitness", type=float, default=0.9)

    fetch_lisp_parser = subparsers.add_parser("fetch-knowledge-lisp")
    fetch_lisp_parser.add_argument("--min-fitness", type=float, default=0.9)

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
        else:
            logger.write_remote(args.event_type, args.event_source, args.session_id, args.message, payload, metadata)

    elif args.command == "flush":
        logger.flush()

    elif args.command == "fetch-knowledge":
        logger.fetch_knowledge(min_fitness=args.min_fitness)

    elif args.command == "fetch-knowledge-lisp":
        logger.fetch_knowledge_lisp(min_fitness=args.min_fitness)

    else:
        parser.print_help()

if __name__ == "__main__":
    main()
