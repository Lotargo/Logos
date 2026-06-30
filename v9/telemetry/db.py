import os
import json
import psycopg2
from psycopg2.extras import execute_values

class LogosDB:
    def __init__(self, db_url=None):
        self.db_url = db_url or os.environ.get("NEON_DATABASE_URL")
        self.conn = None

    def connect(self):
        if not self.db_url:
            raise ValueError("NEON_DATABASE_URL environment variable not set")
        if not self.conn or self.conn.closed:
            self.conn = psycopg2.connect(self.db_url)
        return self.conn

    def close(self):
        if self.conn and not self.conn.closed:
            self.conn.close()

    def init_db(self, schema_path):
        conn = self.connect()
        with conn.cursor() as cur:
            with open(schema_path, "r") as f:
                cur.execute(f.read())
        conn.commit()

    def insert_events(self, events):
        """
        Batch inserts events into the database.
        Handles mapping different event types to appropriate tables.
        """
        conn = self.connect()
        with conn.cursor() as cur:
            # First, separate events by category if needed
            # For MVP, we'll mostly use logos_events and logos_fitness_results

            general_events = []
            fitness_results = []
            runs = []

            for event in events:
                event_type = event.get("event_type")
                if event_type == "experiment_started" or event_type == "experiment_finished":
                    # Map to logos_runs if it looks like a run event
                    payload = event.get("payload", {})
                    runs.append((
                        event.get("session_id"),
                        event.get("experiment_id"),
                        event.get("run_type"),
                        event.get("created_at"),
                        event.get("status"),
                        payload.get("model_id"),
                        payload.get("logos_version"),
                        event.get("git_commit_hash"),
                        event.get("git_branch"),
                        event.get("dirty_worktree"),
                        json.dumps(payload.get("metadata", {}))
                    ))

                # All events go to logos_events
                general_events.append((
                    event.get("session_id"),
                    event.get("event_type"),
                    event.get("event_source"),
                    event.get("created_at"),
                    event.get("severity", "info"),
                    event.get("message"),
                    json.dumps(event.get("payload", {})),
                    json.dumps(event.get("metadata", {}))
                ))

                if event_type == "fitness_evaluated":
                    payload = event.get("payload", {})
                    fitness_results.append((
                        event.get("session_id"),
                        payload.get("candidate_id"),
                        payload.get("fitness_score"),
                        json.dumps(payload.get("fitness_metrics", {})),
                        json.dumps(payload.get("input_ast")),
                        json.dumps(payload.get("output_ast")),
                        payload.get("input_ast_hash"),
                        payload.get("output_ast_hash"),
                        payload.get("execution_time_ms"),
                        payload.get("error_rate"),
                        payload.get("tokens_used"),
                        event.get("created_at"),
                        json.dumps(event.get("metadata", {}))
                    ))

            # Execute insertions
            if runs:
                # Simplified run insertion for now
                pass

            if general_events:
                execute_values(cur, """
                    INSERT INTO logos_events (session_id, event_type, event_source, created_at, severity, message, payload, metadata)
                    VALUES %s
                """, general_events)

            if fitness_results:
                execute_values(cur, """
                    INSERT INTO logos_fitness_results (session_id, candidate_id, fitness_score, fitness_metrics, input_ast, output_ast, input_ast_hash, output_ast_hash, execution_time_ms, error_rate, tokens_used, created_at, metadata)
                    VALUES %s
                """, fitness_results)

        conn.commit()

if __name__ == "__main__":
    # Test connection
    db = LogosDB()
    try:
        db.connect()
        print("Successfully connected to Neon PostgreSQL")
        db.close()
    except Exception as e:
        print(f"Failed to connect: {e}")
