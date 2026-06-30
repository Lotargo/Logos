# 01 — Полный аудит v9: Neon Integration + 3 Эксперимента

**Дата:** 01.07.2026
**Объём аудита:** Весь v9/ (engine, telemetry, experiments, prolog, docs)
**Цель:** Оценка качества реализации Neon-интеграции и трёх экспериментов

---

## Содержание

1. [Архитектура v9 — Обзор](#1-архитектура-v9--обзор)
2. [Neon PostgreSQL: Схема данных](#2-neon-postgresql-схема-данных)
3. [Neon PostgreSQL: Db-класс (db.py)](#3-neon-postgresql-db-класс-dbpy)
4. [Neon PostgreSQL: Offline-first архитектура](#4-neon-postgresql-offline-first-архитектура)
5. [Lisp ↔ Python мост (telemetry_helper.lisp)](#5-lisp--python-мост-telemetry_helperlisp)
6. [ADF-интеграция (knowledge_loader.lisp)](#6-adf-интеграция-knowledge_loaderlisp)
7. [Эксперимент 1: Convergence Velocity](#7-эксперимент-1-convergence-velocity)
8. [Эксперимент 2: Complexity Ceiling](#8-эксперимент-2-complexity-ceiling)
9. [Эксперимент 3: Cross-Domain Transfer](#9-эксперимент-3-cross-domain-transfer)
10. [Системный дефект: run-engine-parallel](#10-системный-дефект-run-engine-parallel)
11. [Сводная таблица](#11-сводная-таблица)
12. [Рекомендации по исправлению](#12-рекомендации-по-исправлению)

---

## 1. Архитектура v9 — Обзор

v9 — третья major-версия AGI-lite. Эволюция: v7 (domain-specific Prolog censor) → v8 (unified first-principle) → v9 (unified + persistent memory + NSPL networking).

**Стек:** Common Lisp (SBCL) + SWI-Prolog + Python telemetry + Neon PostgreSQL

**Ключевые компоненты v9:**

```
v9/
├── src/engine.lisp              — Главный движок (549 строк)
├── src/knowledge_loader.lisp    — Загрузка знаний из БД (40 строк)
├── src/meta_evolve.lisp         — Динамическое изобретение операторов (127 строк)
├── src/nspl.lisp                — Binary-протокол для межузловой связи (189 строк)
├── prolog/root_axioms.pl        — Унифицированные Prolog-аксиомы (266 строк)
├── prolog/daemon.pl             — Prolog IPC daemon (31 строк)
├── prolog/nspl_invariants.pl    — Валидация NSPL-пакетов (80 строк)
├── telemetry/                   — Весь pipeline сбора телеметрии
│   ├── schema.sql               — PostgreSQL-схема
│   ├── db.py                    — Db-класс
│   ├── telemetry_logger.py      — Python-логгер
│   ├── telemetry_helper.lisp    — Lisp-интерфейс к логгеру
│   ├── config.yaml              — Конфигурация
│   └── telemetry_client.py      — Утилита для Python-скриптов
└── experiments/                 — 17 Lisp + 12 Python файлов
```

**Подключённые подсистемы из v8:** meta_evolve (динамические операторы), ontology_generator (LaTeX), verilog_emitter (hardware lowering), curry_howard (proof terms).

---

## 2. Neon PostgreSQL: Схема данных

**Файл:** `v9/telemetry/schema.sql` (75 строк)

### Таблицы

| Таблица | Назначение | Ключевые колонки |
|---------|-----------|------------------|
| `logos_runs` | Метаданные запусков | `session_id`, `experiment_id`, `run_type`, `git_commit_hash` |
| `logos_events` | Поток событий | `event_type`, `severity`, `message`, `payload JSONB` |
| `logos_fitness_results` | Fitness каждого кандидата | `input_ast JSONB`, `output_ast JSONB`, `fitness_score` |
| `logos_ab_tests` | Результаты A/B тестов | `variant_a`, `variant_b`, `winner`, `metrics JSONB` |
| `logos_linear_issues` | Linear.app интеграция | `linear_issue_id`, `linear_issue_url` |

### Что хорошо

- UUID-первичные ключи через `gen_random_uuid()` — корректно для распределённой системы
- JSONB для `payload`, `metadata`, `fitness_metrics` — гибкость для полуструктурированных данных
- FK-связи: `logos_events.run_id → logos_runs.id`, `logos_fitness_results.run_id → logos_runs.id`
- `TIMESTAMPTZ DEFAULT now()` — timezone-aware по умолчанию

### Проблемы

#### 2.1. Нет индексов

**Серьёзность: Высокая**

Все запросы работают через full table scan:

```sql
-- db.py:36-42 — запрос get_best_knowledge
SELECT output_ast, fitness_score
FROM logos_fitness_results
WHERE fitness_score >= 0.9    -- ← full scan
ORDER BY fitness_score DESC   -- ← full scan + sort
LIMIT 100;

-- db.py:55-63 — запрос get_discovered_axioms
SELECT payload->>'axiom'
FROM logos_events
WHERE event_type = 'axiom_discovered'  -- ← full scan
ORDER BY created_at DESC               -- ← full scan + sort
LIMIT 100;
```

**Необходимые индексы:**
```sql
CREATE INDEX idx_fitness_score ON logos_fitness_results (fitness_score DESC);
CREATE INDEX idx_fitness_output_ast ON logos_fitness_results (output_ast);
CREATE INDEX idx_events_type ON logos_events (event_type);
CREATE INDEX idx_events_created ON logos_events (created_at DESC);
CREATE INDEX idx_events_run_id ON logos_events (run_id);
CREATE INDEX idx_runs_session ON logos_runs (session_id);
```

#### 2.2. Нет миграционной системы

**Серьёзность: Средняя**

`CREATE TABLE IF NOT EXISTS` не обновляет схему при изменениях. Если добавить колонку — старые таблицы не обновятся. Нет versioning-механизма.

#### 2.3. Нет обработки ошибок в insert_events

**Серьёзность: Высокая**

```python
# db.py:127-145
if runs:
    execute_values(cur, ...)  # ← если упадёт здесь
# general_events и fitness_results не вставятся
# нет rollback

conn.commit()  # ← если упадёт execute_values выше, conn в неопределённом состоянии
```

**Нужно:**
```python
try:
    # ... execute_values ...
    conn.commit()
except Exception:
    conn.rollback()
    raise
```

---

## 3. Neon PostgreSQL: Db-класс (db.py)

**Файл:** `v9/telemetry/db.py` (154 строки)

### Что хорошо

- `get_best_knowledge(min_fitness)` — правильная сортировка по fitness DESC + limit
- `get_discovered_axioms()` — извлечение аксиом из JSONB payload
- `insert_events()` — batch-вставка через `execute_values` с маршрутизацией по типам
- Простой и чистый API

### Проблемы

#### 3.1. Нет connection pooling

**Серьёзность: Средняя**

```python
def __init__(self, db_url=None):
    self.db_url = db_url or os.environ.get("NEON_DATABASE_URL")
    self.conn = None  # ← создаётся при каждом вызове connect()
```

Каждый `LogosDB()` создаёт новое соединение. При частых вызовах из telemetry_helper.lisp (каждые 50 итераций) — это overhead на TLS handshake к Neon.

**Решение:** Singleton или `psycopg2.pool.ThreadedConnectionPool`.

#### 3.2. Нет таймаута соединения

**Серьёзность: Средняя**

`psycopg2.connect(self.db_url)` без `connect_timeout`. Если Neon недоступен — блокирует нить бесконечно.

**Решение:** `psycopg2.connect(self.db_url, connect_timeout=5, options='-c statement_timeout=10000')`.

#### 3.3. Нет graceful degradation при недоступности БД

**Серьёзность: Средняя**

`knowledge_loader.lisp` вызывает `fetch-telemetry-knowledge`, который запускает `telemetry_logger.py fetch-knowledge`. Если БД недоступна — Python ловит исключение и возвращает `{"status": "error", ...}`. Lisp-парсер получает nil и пишет "No persistent knowledge found".

Это **работает**, но:
- Нет fallback на локальный JSONL кэш
- Нет retry с exponential backoff
- Пользователь не различает "БД пуста" и "БД недоступна"

#### 3.4. Дублирование в telemetry_client.py

**Серьёзность: Низкая**

`telemetry_client.py` дублирует functionality `TelemetryLogger` — можно импортировать напрямую:
```python
from telemetry_logger import TelemetryLogger
logger = TelemetryLogger()
logger.write_local(...)
```

Вместо этого — subprocess call через `python3 v9/telemetry/telemetry_logger.py write-local ...`.

---

## 4. Neon PostgreSQL: Offline-first архитектура

**Файлы:** `config.yaml`, `telemetry_logger.py`, `cache/logos_memory.jsonl`

### Поток данных

```
Lisp Engine
  → telemetry_helper.lisp (log-telemetry, log-fitness-telemetry)
    → python3 telemetry_logger.py write-local
      → logos_memory.jsonl (append JSON)

[Опционально, по cron/manual]
  → python3 telemetry_logger.py flush
    → db.py LogosDB.insert_events()
      → Neon PostgreSQL
```

### Что хорошо

- Write-local-first — работает без сети
- Flush batch-ми (100 событий по умолчанию)
- Git-информация в каждом событии (commit, branch, dirty state)
- Linear.app интеграция через триггеры (high/low fitness, errors)

### Проблемы

#### 4.1. Нет flush по времени

**Серьёзность: Низкая**

`flush()` только ручной. Если забыть — кэш растёт бесконечно. Нет automatic flush по размеру или времени.

#### 4.2. `flush()` не原子性

**Серьёзность: Средняя**

```python
# telemetry_logger.py:106-109
db.insert_events(events)
# ← если insert прошёл успешно
open(self.cache_path, "w").close()  # ← очищаем кэш
# ← но если процесс упадёт между insert и clear — данные дублируются при следующем flush
```

**Решение:** Использовать файл-флаг или rename перед очисткой.

---

## 5. Lisp ↔ Python мост (telemetry_helper.lisp)

**Файл:** `v9/telemetry/telemetry_helper.lisp` (67 строки)

### Что хорошо

- `log-telemetry` — корректная сериализация plist → JSON через ручной loop
- `log-fitness-telemetry` — специализированный helper для fitness events
- `fetch-telemetry-knowledge` — вызов Python → JSON → Lisp sexp через промежуточный Python-скрипт
- `%escape-json-string` — обработка спецсимволов

### Проблемы

#### 5.1. Fragile JSON serialization

**Серьёзность: Средняя**

Ручная сериализация plist → JSON:
```lisp
(loop for (key val) on payload-plist by #'cddr
      do (format s "\"~A\": " (string-downcase (symbol-name key)))
         (cond
           ((numberp val) (format s "~A" val))
           ...))
```

Если `val` — список или вложенный plist — будет сломанный JSON. Нет вложенной сериализации.

#### 5.2. `fetch-telemetry-knowledge` — двойной subprocess

**Серьёзность: Средняя**

```lisp
;; Шаг 1: Запускаем Python для получения JSON
(let ((output (uiop:run-program cmd :output :string)))
  ;; Шаг 2: Запускаем ещё один Python для конвертации JSON → Lisp sexp
  (let ((lisp-str (uiop:run-program lisp-format-cmd :input (make-string-input-stream output))))
    (read-from-string lisp-str)))
```

Два subprocess-вызова для одного запроса. Можно делать конвертацию в Lisp или в одном Python-скрипте.

#### 5.3. Нет таймаута на fetch-knowledge

**Серьёзность: Средняя**

`uiop:run-program` без таймаута. Если Python зависает на `psycopg2.connect` — Lisp нить зависает.

---

## 6. ADF-интеграция (knowledge_loader.lisp)

**Файл:** `v9/src/knowledge_loader.lisp` (40 строки)

### Поток

```
initialize-knowledge-base
  → fetch-telemetry-knowledge (Lisp → Python → Neon DB)
  → парсим JSON → (:asts ("(mul x x)" "(sin x)") :axioms ("ax1" "ax2"))
  → каждый AST → read-from-string → intern "DB-ADF-N" → push *adf-library*
  → каждый axiom → push *discovered-axioms*
  → log-telemetry "knowledge_base_initialized"
```

### Что хорошо

- Дедупликация через `(member ast *adf-library* :key #'cdr :test #'equal)`
- `read-from-string` с `handler-case` — graceful обработка невалидных AST
- Прогресс-логирование

### Проблемы

#### 6.1. Вызывается при каждом `run-engine-parallel`

**Серьёзность: Средняя**

```engine.lisp:353-355
(defun run-engine-parallel (base-ast domain iterations num-threads)
  (log-telemetry "experiment_started" ...)
  (setf *discovered-axioms* nil)  ; ← сброс всех аксиом!
  (initialize-knowledge-base)     ; ← перезагрузка из БД
```

Каждый вызов `run-engine-parallel` сбрасывает `*discovered-axioms*` и перезагружает из БД. Если запускать 3 домена последовательно (как в `exp_cross_domain.lisp`) — Phase 1 знания теряются при начале Phase 2.

#### 6.2. `*adf-library*` не сбрасывается

**Серьёзность: Низкая (в контексте knowledge_loader)**

`*adf-library*` не обнуляется в `run-engine-parallel` — ADF накапливаются. Но `*discovered-axioms*` обнуляется. Это создаёт асимметрию: ADF-и живут, аксиомы — нет.

#### 6.3. ADF-символы конфликтуют

**Серьёзность: Средняя**

```lisp
;; knowledge_loader.lisp:17
(let ((adf-sym (intern (format nil "DB-ADF-~D" (1+ (length *adf-library*))))))
;; engine.lisp:377
(let ((adf-sym (intern (format nil "ADF-~D" (1+ (length *adf-library*))))))
```

DB-ADF и ADF — разные пространства имён. Но `(1+ (length *adf-library*))` может дать одинаковые индексы если *adf-library* не менялся. Нет уникальности guaranteed.

---

## 7. Эксперимент 1: Convergence Velocity

**Файлы:**
- `v9/experiments/bench_persistence.py` — оркестратор (85 строк)
- `v9/experiments/report_exp1.py` — генерация отчёта (95 строк)
- `v9/experiments/exp_complexity_ceiling.lisp` — Lisp-скрипт (32 строки)

### Цель (из описания)

> Сравнить время и количество итераций, необходимых для повторного открытия сложной формулы.
> Этап А: Чистый v9 без БД.
> Этап Б: v9 с подключённой БД.
> Ожидаемый результат: Сокращение итераций на 40-70%.

### Что реализовано

**bench_persistence.py:**
```python
# Запускает:
results_two_phase = run_experiment_group("v9/experiments/exp_complexity_ceiling.lisp", ...)
results_one_shot = run_experiment_group("v9/experiments/exp_complexity_ceiling.lisp", ..., args=["--one-shot"])
results_cross_domain = run_experiment_group("v9/experiments/exp_cross_domain.lisp", ...)
```

**report_exp1.py:**
- Ожидает `benchmarks_output/experiment_1/results.csv`
- Группирует по `mode` (baseline vs persistent)
- Строит barplot и boxplot
- Конвертирует в HTML через Pandoc

### Проблемы

#### 7.1. Нет comparison "с БД vs без БД"

**Серьёзность: Критическая**

Оркестратор запускает `exp_complexity_ceiling.lisp` в two-phase и one-shot режимах. Но **оба варианта используют одну и ту же БД**. Нет:
- Варианта "чистый v9 без БД" (удалить/env не задан)
- Варианта "v9 с БД, предзаполненной ADF"
- Автоматического A/B сравнения

**Гипотеза эксперимента формально не проверена.**

#### 7.2. `report_exp1.py` ссылается на несуществующий CSV

**Серьёзность: Критическая**

```python
results_path = "benchmarks_output/experiment_1/results.csv"
```

Но `bench_persistence.py` генерирует `benchmarks_output/summary_metrics.json` в корне benchmarks_output, а не в `experiment_1/`. Маршруты не совпадают.

#### 7.3. `iterations=1` по умолчанию

**Серьёзность: Высокая**

```python
results_two_phase = run_experiment_group(..., iterations=1)
results_one_shot = run_experiment_group(..., iterations=1)
```

Одна итерация — статистически незначимо. Нет std, нет confidence intervals, нет p-value.

#### 7.4. Метрики парсятся по строкам

**Серьёзность: Средняя**

```python
def parse_metrics(output):
    for line in output.split('\n'):
        if "Total ASTs Evaluated" in line:
            metrics['iterations'] = int(line.split(':')[-1].strip())
```

Хрупко: любое изменение формата вывода engine.lisp ломает парсинг. Нет JSON-вывода из engine.

#### 7.5. Нет seed для воспроизводимости

**Серьёзность: Средняя**

`*random-state*` не seed-ится. Каждый запуск даёт разные результаты. Невозможно воспроизвести.

### Оценка: 4/10

Инфраструктура бенчмаркинга есть (subprocess runner + metrics parser + plotting), но **ключевой A/B comparison не реализован**. Отчёт генерируется из несуществующего CSV.

---

## 8. Эксперимент 2: Complexity Ceiling

**Файл:** `v9/experiments/exp_complexity_ceiling.lisp` (32 строки)

### Цель (из описания)

> Проверить, может ли v9 найти сверхсложную формулу, которую невозможно найти за один запуск.
> Мы разбиваем задачу на подзадачи. Сначала находим базовые закономерности, сохраняем их в «память».
> Затем запускаем поиск финальной формулы, используя эти закономерности как ADF.
> Ожидаемый результат: Открытие формул с глубиной AST > 10.

### Что реализовано

```lisp
(defun run-complexity-experiment (&key (two-phase t))
  (let ((domain :regression) (dataset "v9/data/complex_formula.csv") (iterations 100))
    (setf *current-dataset* dataset)
    (setf *regression-vars* '(v1))
    (if two-phase
        (progn
          ;; Phase 1: Ищем базовые компоненты
          (run-engine-parallel '(sin v1) domain 100 num-threads)
          ;; Phase 2: Собираем финальную формулу
          (run-engine-parallel '(sin (add v1 v1)) domain iterations num-threads))
        ;; Control: One-shot
        (run-engine-parallel '(sin v1) domain (+ iterations 100) num-threads)))))
```

### Проблемы

#### 8.1. Target formula ≠ заявленной

**Серьёзность: Критическая**

Заявлено: `sin(x + sin(x + sin(x + sin(x + sin(x)))))` (глубина AST > 10)

Код ищет:
- Phase 1: `(sin v1)` — sin от переменной
- Phase 2: `(sin (add v1 v1))` — sin(2x)

Это **sin(x)** и **sin(2x)**, а не вложенная структура. Глубина AST Phase 2 = 3, а не > 10.

#### 8.2. Phase 2 не использует результаты Phase 1

**Серьёзность: Критическая**

```lisp
(run-engine-parallel '(sin v1) domain 100 num-threads)       ; Phase 1
(run-engine-parallel '(sin (add v1 v1)) domain iterations num-threads)  ; Phase 2
```

`run-engine-parallel` внутри делает:
```lisp
(setf *discovered-axioms* nil)      ; ← сброс аксиом
(initialize-knowledge-base)         ; ← загрузка из БД (если есть)
```

Phase 1 результаты **не передаются** в Phase 2. ADF-и из Phase 1 живут в `*adf-library*` (не сбрасываются), но:
1. Нет записи Phase 1 результатов в БД (нет `flush`)
2. `initialize-knowledge-base` загружает из БД, а не из памяти
3. Phase 2 стартует с нового base-ast `(sin (add v1 v1))`, а не с best Phase 1

**Two-phase separation фактически не работает.**

#### 8.3. Нет DB-backed variant

**Серьёзность: Критическая**

Эксперимент не тестирует:
- "Сохранить Phase 1 результат в БД"
- "Загрузить Phase 2 с БД"
- Сравнить с "без БД"

Интеграция с Neon **не используется**.

#### 8.4. Маленький iteration budget

**Серьёзность: Средняя**

`iterations=100` для каждой фазы. Для сложных AST этого может быть недостаточно, но главная проблема не в budget, а в отсутствии передачи state.

### Оценка: 3/10

Инфраструктура двухфазного поиска написана, но **гипотеза эксперимента не проверяется**: target formula упрощена, state не передаётся между фазами, БД не используется.

---

## 9. Эксперимент 3: Cross-Domain Transfer

**Файлы:**
- `v9/experiments/exp_cross_domain.lisp` — простой вариант (20 строк)
- `v9/experiments/experiment_nspl_cross_domain.lisp` — NSPL вариант (135 строк)

### Цель (из описания)

> Проверить гипотезу о том, что математические структуры универсальны.
> Накопить опыт в домене :arithmetic и посмотреть, поможет ли это в домене :quantum или :logic.
> Ожидаемый результат: Обнаружение изоморфизмов.

### Простой вариант (exp_cross_domain.lisp)

```lisp
(defun run-cross-domain-experiment ()
  (let ((num-threads (detect-cpu-cores)))
    ;; Phase 1: Arithmetic
    (run-engine-parallel '(mul x (sub 1 x)) :arithmetic 100 num-threads)
    ;; Phase 2: Logic
    (run-engine-parallel '(and p q) :logic 100 num-threads)
    ;; Phase 3: Quantum
    (run-engine-parallel '(seq (h q1) (h q2)) :quantum 100 num-threads)))
```

#### Проблемы простого варианта

##### 9.1. ADF-библиотека не передаётся между фазами

**Серьёзность: Критическая**

Как описано в п.10 — `run-engine-parallel` сбрасывает `*discovered-axioms*`. Но `*adf-library*` **не сбрасывается**. Это значит:
- ADF из Phase 1 (arithmetic) **остаются** в `*adf-library*`
- Но Phase 2 (logic) стартует с `(and p q)` и **не знает**, что ADF-и из arithmetic доступны

Нет вызова `(initialize-knowledge-base)` с сохранением state. Transfer не происходит.

##### 9.2. Нет метрик transfer

**Серьёзность: Высокая**

Нет подсчёта: использовал ли engine ADF-и из предыдущего домена, улучшился ли fitness, были ли isomorphisms.

### NSPL вариант (experiment_nspl_cross_domain.lisp)

Это **наиболее зрелая** часть v9.

#### Архитектура

```
Node A (Quantum)                Node B (Electro)
  │                                │
  │ worker-loop :quantum           │ worker-loop :electro
  │ → unitary-pattern              │ → masked-ast (quantum ops → unknown_op)
  │ → ast-to-nspl                  │ → evolve masked-ast в electro-пространстве
  │ → serialize-nspl               │
  │ → ltp-send ──────────────────→ │ ltp-receive
  │                                │ → если lc_resonance + magnetic_flux → success!
  │                                │ → иначе → negative_transfer
```

#### Что хорошо

- **Binary serialization** — NSPL-пакеты: `ast-to-nspl`, `serialize-nspl`, `deserialize-nspl`
- **Domain masking** — замена доменных операторов на `unknown_op`, потом эволюция заполняет placeholders
- **Collision resolution** — `resolve-collision` для выбора среди кандидатов
- **Метрики** — `translation_attempts`, `valid_functors`, `hit_rate_percent`, `negative_transfers`
- **Multi-threaded** — `sb-thread:make-thread` с `join-thread`
- **Prolog invariants** — `nspl_invariants.pl` валидирует пакеты через `verify_nspl_packet/3`

#### Проблемы NSPL варианта

##### 9.3. Mock network pipe — in-memory queue

**Серьёзность: Средняя**

```lisp
(defvar *ltp-queue* nil)  ; ← in-memory

(defun ltp-send (byte-vector)
  (sb-thread:with-mutex (*ltp-mutex*)
    (push byte-vector *ltp-queue*)))
```

Не реальная сеть. Для proof-of-concept допустимо, но не для production.

##### 9.4. `node-a-quantum` — бесконечный цикл без timeout

**Серьёзность: Высокая**

```lisp
(loop while (not *cross-domain-solved*) do
  ... (sleep 0.5))
```

Если `*cross-domain-solved*` никогда не станет `t` — Node A зависнет. Нет timeout.

##### 9.5. Hardcoded operators

**Серьёзность: Средняя**

```lisp
(cognitive-engine::*current-operators* '(lc_resonance inductive_shift magnetic_flux hall_effect capacitive_load seq))
```

Эти операторы **не в `*unified-operators*`** engine.lisp. NSPL-эксперимент использует свой пул операторов, изолированный от основного движка.

##### 9.6. `resolve-collision` — random choice

**Серьёзность: Низкая**

```lisp
(defun resolve-collision (candidates)
  (let ((idx (random (length candidates))))
    (nth idx candidates)))
```

Заявлено "probabilistically based on historical fitness weights", но реализовано как uniform random. Fitness-based weighting не реализован.

### Оценка: 5/10

NSPL-архитектура **концептуально зрелая**: binary protocol, domain masking, collision resolution. Но simple variant **broken** (transfer не работает из-за сброса discovered axioms), NSPL в mock-режиме, Node A может зависнуть.

---

## 10. Системный дефект: run-engine-parallel

**Файл:** `v9/src/engine.lisp:352-355`

```lisp
(defun run-engine-parallel (base-ast domain iterations num-threads)
  (log-telemetry "experiment_started" ...)
  (setf *discovered-axioms* nil)   ; ← ОБНУЛЕНИЕ ВСЕХ АКСИОМ
  (initialize-knowledge-base)       ; ← ПЕРЕЗАГРУЗКА ИЗ БД
  ...)
```

### Суть проблемы

При каждом вызове `run-engine-parallel`:
1. `*discovered-axioms*` обнуляется — аксиомы из предыдущих запусков теряются
2. `initialize-knowledge-base` перезагружает из БД — но если БД пуста или результаты не были flush'нуты, ничего не загружается
3. `*adf-library*` **не обнуляется** — ADF-и накапливаются, но аксиомы нет

### Влияние на эксперименты

| Эксперимент | Влияние |
|-------------|---------|
| Convergence Velocity | Формально не затронут (comparison не реализован) |
| Complexity Ceiling | Phase 1 результаты **теряются** при начале Phase 2 |
| Cross-Domain (simple) | Phase 1 arithmetic-аксиомы **теряются** при начале Phase 2 |
| Cross-Domain (NSPL) | Затронут меньше — NSPL использует свой пул операторов |

### Корневая причина

`run-engine-parallel` спроектирован как **изолированный запуск**. Он не предназначен для последовательных multi-phase/multi-domain запусков с shared state.

---

## 11. Сводная таблица

| Компонент | Оценка | Основные проблемы |
|-----------|--------|-------------------|
| Neon Schema | 6/10 | Нет индексов, нет миграций |
| db.py | 6.5/10 | Нет pooling, нет error handling |
| Offline-first | 7/10 | Хороший паттерн, нет auto-flush |
| telemetry_helper.lisp | 6/10 | Fragile JSON, double subprocess |
| knowledge_loader.lisp | 6/10 | Вызывается при каждом run, ADF-конфликты |
| **Convergence Velocity** | **4/10** | Нет A/B comparison, broken report |
| **Complexity Ceiling** | **3/10** | Target ≠ заявленной, state не передаётся |
| **Cross-Domain Transfer** | **5/10** | NSPL зрелый, simple broken, mock network |
| **run-engine-parallel** | **Системный баг** | Сброс discovered-axioms ломает transfer |
| **СРЕДНЯЯ** | **4.6/10** | Хорошая архитектурная заделка, эксперименты не замкнуты |

---

## 12. Рекомендации по исправлению

### Приоритет 1 (Критический)

1. **Исправить `run-engine-parallel`** — вынести `(setf *discovered-axioms* nil)` за пределы функции или сделать параметром `:reset-state t/nil`
2. **Добавить индексы в schema.sql** — `fitness_score`, `event_type`, `created_at`
3. **Добавить `try/except` + rollback** в `db.py:insert_events`
4. **Исправить `bench_persistence.py`** — реальный A/B comparison с/without DB, `iterations ≥ 5`
5. **Исправить `report_exp1.py`** — указать правильный путь к данным или генерировать CSV

### Приоритет 2 (Высокий)

6. **Сделать `Complexity Ceiling` с реальным target** — `sin(x+sin(x+sin(x+...)))` с depth > 10
7. **Передавать state между фазами** — не сбрасывать `*adf-library*`, вызывать `initialize-knowledge-base` с флагом `:keep-existing`
8. **Connection pooling** в db.py
9. **Таймауты** на subprocess calls в telemetry_helper.lisp
10. **Seed random state** для воспроизводимости экспериментов

### Приоритет 3 (Средний)

11. **Auto-flush** по времени/размеру в telemetry_logger
12. **Fallback на JSONL** если БД недоступна
13. **JSON-вывод** из engine.lisp вместо парсинга строк
14. **Timeout для Node A** в NSPL cross-domain
15. **Fitness-based collision resolution** вместо random choice

---

*Документ создан: 01.07.2026 | Аудит проводил: opencode | Версия движка: v9*
