# 01 — Чеклист: Neon PostgreSQL Инфраструктура

**Категория:** Инфраструктура БД + telemetry pipeline
**Аудит:** `01_v9_audit.md` §2-§6
**Приоритеты:** P0 = критический, P1 = высокий, P2 = средний, P3 = низкий

---

## Содержание

1. [schema.sql — Индексы и миграции](#schemasql--индексы-и-миграции)
2. [db.py — Connection management и error handling](#dbpy--connection-management-и-error-handling)
3. [Offline-first архитектура](#offline-first-архитектура)
4. [telemetry_helper.lisp — Lisp ↔ Python мост](#telemetry_helperlisp--lisp--python-мост)
5. [knowledge_loader.lisp — ADF-интеграция](#knowledge_loaderlisp--adf-интеграция)
6. [Сводная таблица](#сводная-таблица)

---

## schema.sql — Индексы и миграции

### Индексы

- [ ] **P0** Добавить индекс на `logos_fitness_results.fitness_score DESC`
  ```sql
  CREATE INDEX idx_fitness_score ON logos_fitness_results (fitness_score DESC);
  ```
  *Причина: `get_best_knowledge()` делает full scan + sort на каждом запросе*

- [ ] **P0** Добавить индекс на `logos_events.event_type`
  ```sql
  CREATE INDEX idx_events_type ON logos_events (event_type);
  ```
  *Причина: `get_discovered_axioms()` фильтрует по event_type без индекса*

- [ ] **P0** Добавить индекс на `logos_events.created_at DESC`
  ```sql
  CREATE INDEX idx_events_created ON logos_events (created_at DESC);
  ```
  *Причина: ORDER BY created_at DESC в двух запросах*

- [ ] **P1** Добавить индекс на `logos_events.run_id`
  ```sql
  CREATE INDEX idx_events_run_id ON logos_events (run_id);
  ```

- [ ] **P1** Добавить индекс на `logos_fitness_results.created_at DESC`
  ```sql
  CREATE INDEX idx_fitness_created ON logos_fitness_results (created_at DESC);
  ```

- [ ] **P2** Добавить индекс на `logos_runs.session_id`
  ```sql
  CREATE INDEX idx_runs_session ON logos_runs (session_id);
  ```

- [ ] **P2** Добавить частичный индекс для high-fitness результатов
  ```sql
  CREATE INDEX idx_fitness_high ON logos_fitness_results (fitness_score DESC, created_at DESC)
    WHERE fitness_score >= 0.9;
  ```

### Миграции

- [ ] **P1** Создать файл `v9/telemetry/migrations/` с нумерацией
  ```
  migrations/
  ├── 001_initial_schema.sql
  ├── 002_add_indexes.sql
  └── ...
  ```

- [ ] **P1** Добавить таблицу `schema_migrations` для tracking
  ```sql
  CREATE TABLE IF NOT EXISTS schema_migrations (
      version INTEGER PRIMARY KEY,
      applied_at TIMESTAMPTZ DEFAULT now(),
      description TEXT
  );
  ```

- [ ] **P2** Добавить функцию `apply_migration()` в db.py
  ```python
  def apply_migration(self, migration_path):
      """Reads and executes a migration file, records in schema_migrations."""
  ```

---

## db.py — Connection management и error handling

### Connection pooling

- [ ] **P1** Заменить одиночное соединение на pool
  ```python
  from psycopg2.pool import ThreadedConnectionPool

  class LogosDB:
      _pool = None

      def __init__(self, db_url=None):
          self.db_url = db_url or os.environ.get("NEON_DATABASE_URL")

      def connect(self):
          if not LogosDB._pool:
              LogosDB._pool = ThreadedConnectionPool(1, 5, self.db_url)
          return LogosDB._pool.getconn()
  ```

- [ ] **P2** Добавить `return_connection()` после использования
  ```python
  def return_connection(self, conn):
      LogosDB._pool.putconn(conn)
  ```

### Timeouts

- [ ] **P1** Добавить `connect_timeout` в psycopg2.connect
  ```python
  self.conn = psycopg2.connect(self.db_url, connect_timeout=5)
  ```

- [ ] **P2** Добавить `options='-c statement_timeout=10000'` для query timeout
  ```python
  self.conn = psycopg2.connect(self.db_url, connect_timeout=5,
                                options='-c statement_timeout=10000')
  ```

### Error handling в insert_events

- [ ] **P0** Обернуть в try/except с rollback
  ```python
  def insert_events(self, events):
      conn = self.connect()
      try:
          with conn.cursor() as cur:
              # ... execute_values ...
          conn.commit()
      except Exception:
          conn.rollback()
          raise
  ```

- [ ] **P2** Добавить retry с exponential backoff
  ```python
  import time

  def insert_events_with_retry(self, events, max_retries=3):
      for attempt in range(max_retries):
          try:
              self.insert_events(events)
              return
          except Exception as e:
              if attempt == max_retries - 1:
                  raise
              time.sleep(2 ** attempt)
  ```

### Graceful degradation

- [ ] **P1** Добавить метод `is_connected()`
  ```python
  def is_connected(self):
      try:
          conn = self.connect()
          return conn and not conn.closed
      except Exception:
          return False
  ```

- [ ] **P2** Добавить fallback-чтение из JSONL если БД недоступна
  ```python
  def get_best_knowledge_from_cache(self, cache_path, min_fitness=0.9):
      """Reads high-fitness ASTs from local JSONL cache as fallback."""
  ```

---

## Offline-first архитектура

### Автоматический flush

- [ ] **P2** Добавить auto-flush по размеру кэша
  ```python
  def _check_auto_flush(self):
      if os.path.getsize(self.cache_path) > self.config['telemetry']['flush_batch_size'] * 1024:
          self.flush()
  ```

- [ ] **P3** Добавить auto-flush по времени (в telemetry_logger.py)
  ```python
  def _check_time_flush(self):
      last_flush = self.config.get('last_flush_time', 0)
      if time.time() - last_flush > 3600:  # 1 hour
          self.flush()
  ```

### Атомарность flush

- [ ] **P1** Использовать rename перед очисткой
  ```python
  def flush(self):
      # 1. Rename current cache to .flushing
      temp_path = self.cache_path + ".flushing"
      os.rename(self.cache_path, temp_path)
      # 2. Process temp file
      events = self._read_events(temp_path)
      db.insert_events(events)
      # 3. Delete temp file
      os.remove(temp_path)
  ```

---

## telemetry_helper.lisp — Lisp ↔ Python мост

### Таймауты

- [ ] **P1** Добавить таймаут на `log-telemetry`
  ```lisp
  (defun log-telemetry (event-type message &key (source "lisp_engine") (payload-plist nil))
    (let ((cmd ...))
      (handler-case
          (sb-ext:with-timeout 5.0  ; ← 5 second timeout
            (uiop:run-program cmd :ignore-error-status t))
        (sb-ext:timeout ()
          (format t "[TELEMETRY TIMEOUT] Failed to log ~A within 5s~%" event-type))
        (error (e)
          (format t "[TELEMETRY ERROR] ~A~%" e)))))
  ```

- [ ] **P1** Добавить таймаут на `fetch-telemetry-knowledge`
  ```lisp
  (sb-ext:with-timeout 10.0
    (uiop:run-program cmd :output :string :ignore-error-status t))
  ```

### Упрощение JSON-сериализации

- [ ] **P2** Заменить ручную сериализацию на вызов Python one-liner
  ```lisp
  (defun plist-to-json (plist)
    "Converts a plist to JSON string via Python."
    (let ((python-expr
            (format nil "import json; print(json.dumps({~{~{\"~A\": ~A}~^, ~}}))"
                    (plist-to-alist-strings plist))))
      (string-trim '(#\Newline)
        (uiop:run-program `("python3" "-c" ,python-expr) :output :string))))
  ```

- [ ] **P3** Или написать чистый Lisp JSON serializer для простых plist

### Устранение двойного subprocess

- [ ] **P1** Объединить fetch + конвертацию в один Python-скрипт
  ```python
  # telemetry_logger.py — новый subcommand:
  elif args.command == "fetch-knowledge-lisp":
      # Fetch from DB + output Lisp sexp directly
      print(format_as_lisp_sexps(knowledge))
  ```

---

## knowledge_loader.lisp — ADF-интеграция

### State management

- [ ] **P0** Сделать `initialize-knowledge-base` параметрическим
  ```lisp
  (defun initialize-knowledge-base (&key (min-fitness 0.9) (keep-existing nil))
    "If keep-existing is true, does not clear existing ADFs/axioms."
    (unless keep-existing
      (setf *discovered-axioms* nil))
    ...)
  ```

- [ ] **P0** Добавить flag в `run-engine-parallel`
  ```lisp
  (defun run-engine-parallel (base-ast domain iterations num-threads
                               &key (reset-state t))
    (when reset-state
      (setf *discovered-axioms* nil))
    (initialize-knowledge-base :keep-existing (not reset-state))
    ...)
  ```

### Уникальность ADF-символов

- [ ] **P1** Использовать глобальный счётчик вместо `(length *adf-library*)`
  ```lisp
  (defvar *adf-counter* 0)

  (defun next-adf-symbol (prefix)
    (intern (format nil "~A-~D" prefix (incf *adf-counter*))))
  ```

### Дедупликация по hash

- [ ] **P2** Добавить hash-based dedup вместо `equal`
  ```lisp
  (defun ast-hash (ast)
    (sxhash (format nil "~A" ast)))

  (defun initialize-knowledge-base (&key (min-fitness 0.9) (keep-existing nil))
    (let ((seen-hashes (if keep-existing
                           (mapcar #'ast-hash (mapcar #'cdr *adf-library*))
                           nil)))
      (dolist (ast-str asts)
        (let ((ast (read-from-string ast-str))
              (hash (ast-hash ast)))
          (unless (member hash seen-hashes)
            (push hash seen-hashes)
            (push (cons (next-adf-symbol "DB-ADF") ast) *adf-library*))))))
  ```

---

## Сводная таблица

| Приоритет | Количество | Описание |
|-----------|-----------|----------|
| P0 | 5 | Индексы в schema.sql, error handling в db.py, state management в knowledge_loader |
| P1 | 11 | Pooling, timeouts, миграции, auto-flush, упрощение bridge |
| P2 | 9 | Fallback на cache, retry, hash dedup, time flush |
| P3 | 3 | Time-based flush, Lisp JSON serializer, fitness-based collision |
| **Итого** | **28** | |

---

*Чеклист создан: 01.07.2026 | Источник: 01_v9_audit.md §2-§6*
