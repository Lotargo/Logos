import os
import json
import time
import psycopg2
from psycopg2.pool import ThreadedConnectionPool
from psycopg2.extras import execute_values

class LogosDB:
    _pool = None

    def __init__(self, db_url=None):
        self.db_url = db_url or os.environ.get("NEON_DATABASE_URL")

    def connect(self):
        if not self.db_url:
            raise ValueError("NEON_DATABASE_URL environment variable not set")
        if not LogosDB._pool:
            clean_url = self.db_url.replace('-pooler', '')
            LogosDB._pool = ThreadedConnectionPool(1, 5, clean_url,
                                                   connect_timeout=5)
        conn = LogosDB._pool.getconn()
        with conn.cursor() as cur:
            cur.execute("SET statement_timeout = 10000")
        return conn

    def return_connection(self, conn):
        if LogosDB._pool:
            LogosDB._pool.putconn(conn)

    def close(self):
        if LogosDB._pool:
            LogosDB._pool.closeall()
            LogosDB._pool = None

    def is_connected(self):
        try:
            conn = self.connect()
            ok = conn and not conn.closed
            self.return_connection(conn)
            return ok
        except Exception:
            return False

    def init_db(self, schema_path):
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                with open(schema_path, "r") as f:
                    cur.execute(f.read())
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            self.return_connection(conn)

    def apply_migration(self, migration_path):
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                with open(migration_path, "r") as f:
                    cur.execute(f.read())
                name = os.path.splitext(os.path.basename(migration_path))[0]
                cur.execute("""
                    INSERT INTO schema_migrations (version, description)
                    VALUES ((SELECT COALESCE(MAX(version), 0) + 1 FROM schema_migrations), %s)
                """, (name,))
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            self.return_connection(conn)

    def get_best_knowledge(self, min_fitness=0.9, limit=100):
        conn = self.connect()
        results = []
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT output_ast, fitness_score
                    FROM logos_fitness_results
                    WHERE fitness_score >= %s
                    ORDER BY fitness_score DESC, created_at DESC
                    LIMIT %s
                """, (min_fitness, limit))
                for row in cur.fetchall():
                    results.append({
                        "ast": row[0],
                        "fitness": row[1]
                    })
        except Exception:
            conn.rollback()
            raise
        finally:
            self.return_connection(conn)
        return results

    def get_discovered_axioms(self, limit=100):
        conn = self.connect()
        axioms = []
        try:
            with conn.cursor() as cur:
                cur.execute("""
                    SELECT payload->>'axiom'
                    FROM logos_events
                    WHERE event_type = 'axiom_discovered'
                    ORDER BY created_at DESC
                    LIMIT %s
                """, (limit,))
                for row in cur.fetchall():
                    if row[0]:
                        axioms.append(row[0])
        except Exception:
            conn.rollback()
            raise
        finally:
            self.return_connection(conn)
        return axioms

    def insert_events(self, events):
        conn = self.connect()
        try:
            with conn.cursor() as cur:
                general_events = []
                fitness_results = []
                runs = []

                for event in events:
                    event_type = event.get("event_type")
                    payload = event.get("payload", {})

                    if event_type in ["experiment_started", "experiment_finished"]:
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

                    general_events.append((
                        event.get("session_id"),
                        event.get("event_type"),
                        event.get("event_source"),
                        event.get("created_at"),
                        event.get("severity", "info"),
                        event.get("message"),
                        json.dumps(payload),
                        json.dumps(event.get("metadata", {}))
                    ))

                    if event_type == "fitness_evaluated":
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

                if runs:
                    execute_values(cur, """
                        INSERT INTO logos_runs (session_id, experiment_id, run_type, started_at, status, model_id, logos_version, git_commit_hash, git_branch, dirty_worktree, metadata)
                        VALUES %s
                    """, runs)

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
        except Exception:
            conn.rollback()
            raise
        finally:
            self.return_connection(conn)

    def insert_events_with_retry(self, events, max_retries=3):
        for attempt in range(max_retries):
            try:
                self.insert_events(events)
                return
            except Exception as e:
                if attempt == max_retries - 1:
                    raise
                time.sleep(2 ** attempt)

    def get_best_knowledge_from_cache(self, cache_path, min_fitness=0.9):
        if not os.path.exists(cache_path):
            return {"asts": [], "axioms": []}
        asts = []
        with open(cache_path, "r") as f:
            for line in f:
                if line.strip():
                    event = json.loads(line)
                    if event.get("event_type") == "fitness_evaluated":
                        score = event.get("payload", {}).get("fitness_score", 0)
                        if score >= min_fitness:
                            asts.append(event["payload"].get("output_ast"))
        return {"asts": asts, "axioms": []}

if __name__ == "__main__":
    db = LogosDB()
    try:
        db.connect()
        print("Successfully connected to Neon PostgreSQL")
        db.close()
    except Exception as e:
        print(f"Failed to connect: {e}")
