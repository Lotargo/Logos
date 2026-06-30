# 03 — Чеклист: Эксперимент «Потолок сложности» (Complexity Ceiling)

**Категория:** Эксперимент 2 — Иерархический поиск vs one-shot
**Аудит:** `01_v9_audit.md` §8
**Файлы:** `exp_complexity_ceiling.lisp`, `bench_persistence.py`
**Гипотеза:** Двухфазный поиск с ADF находит формулы с глубиной AST > 10, недоступные one-shot

---

## Содержание

1. [Target formula — исправление](#target-formula--исправление)
2. [Two-phase state transfer](#two-phase-state-transfer)
3. [Интеграция с БД](#интеграция-с-бд)
4. [Метрики и воспроизводимость](#метрики-и-воспроизводимость)
5. [Сводная таблица](#сводная-таблица)

---

## Target formula — исправление

### Проблема

Заявленная цель: `sin(x + sin(x + sin(x + sin(x + sin(x)))))` — глубина AST > 10.
Текущий код: Phase 1 = `(sin v1)`, Phase 2 = `(sin (add v1 v1))` — глубина 3.

### Исправления

- [ ] **P0** Заменить target на реальную вложенную структуру
  ```lisp
  ;; Target: sin(x + sin(x + sin(x)))
  ;; Это 3-level nesting, глубина AST = 7
  ;; Достаточно для demonstration, но не комбинаторный взрыв

  ;; Phase 1: Компоненты
  (run-engine-parallel '(sin v1) :regression 200 num-threads)     ; sin(x)
  (run-engine-parallel '(add v1 (sin v1)) :regression 200 num-threads) ; x + sin(x)

  ;; Phase 2: Сборка
  (run-engine-parallel '(sin (add v1 (sin v1))) :regression 500 num-threads) ; sin(x + sin(x))

  ;; Phase 3: Глубокая вложенность
  (run-engine-parallel '(sin (add v1 (sin (add v1 (sin v1))))) :regression 1000 num-threads)
  ```

- [ ] **P0** Создать CSV `v9/data/complex_formula.csv` с данными target-функции
  ```python
  # generate_complex_formula_data.py
  import numpy as np
  import pandas as pd

  x = np.linspace(-5, 5, 200)
  # Target: sin(x + sin(x + sin(x)))
  y = np.sin(x + np.sin(x + np.sin(x)))
  df = pd.DataFrame({'v1': x, 'target': y})
  df.to_csv('v9/data/complex_formula.csv', index=False)
  ```

- [ ] **P1** Добавить параметр `--target-depth` для конфигурирования глубины вложенности
  ```lisp
  (defun build-nested-target (depth)
    "Recursively builds sin(x + sin(x + ...)) with given depth."
    (if (<= depth 0)
        'v1
        `(sin (add v1 ,(build-nested-target (1- depth))))))
  ```

- [ ] **P2** Добавить проверку: один ли target для обоих режимов
  ```lisp
  (defun validate-target-consistency (target-ast)
    (format t "Target AST: ~A~%" target-ast)
    (format t "Target depth: ~D~%" (ast-depth target-ast))
    (assert (> (ast-depth target-ast) 5)))
  ```

---

## Two-phase state transfer

### Проблема

Phase 1 результаты теряются при начале Phase 2 из-за:
1. `(setf *discovered-axioms* nil)` в `run-engine-parallel`
2. Phase 2 стартует с нового base-ast, а не с best Phase 1
3. Нет flush результатов Phase 1 в БД

### Исправления

- [ ] **P0** Добавить параметр `:reset-state` в `run-engine-parallel`
  ```lisp
  (defun run-engine-parallel (base-ast domain iterations num-threads
                               &key (reset-state t))
    (when reset-state
      (setf *discovered-axioms* nil))
    (initialize-knowledge-base :keep-existing (not reset-state))
    ...)
  ```

- [ ] **P0** Использовать `:reset-state nil` для Phase 2
  ```lisp
  ;; Phase 1
  (run-engine-parallel '(sin v1) :regression 200 num-threads :reset-state t)

  ;; Phase 2 — НЕ сбрасываем state
  (run-engine-parallel '(add v1 (sin v1)) :regression 500 num-threads
                       :reset-state nil)
  ```

- [ ] **P0** Передавать best-ast из Phase 1 как base-ast для Phase 2
  ```lisp
  ;; Нужно чтобы run-engine-parallel возвращал best-ast
  ;; Сейчас возвращает (cons best-ast actual-iters) — уже есть!

  (let* ((result-phase1 (run-engine-parallel '(sin v1) :regression 200 num-threads))
         (best-phase1 (car result-phase1)))
    ;; best-phase1 теперь доступен как ADF
    (format t "Phase 1 winner: ~A~%" best-phase1)
    ;; Phase 2 использует ADF из Phase 1
    (run-engine-parallel `(sin ,best-phase1) :regression 500 num-threads
                         :reset-state nil))
  ```

- [ ] **P1** Добавить explicit ADF-регистрацию best-ast после каждой фазы
  ```lisp
  ;; После run-engine-parallel — явно注册 best как ADF
  (let ((adf-sym (intern (format nil "PHASE1-ADF-~D" (incf *adf-counter*)))))
    (push (cons adf-sym best-phase1) *adf-library*)
    (format t "Registered Phase 1 winner as ~A -> ~A~%" adf-sym best-phase1))
  ```

- [ ] **P1** Сохранять ADF library между фазами — НЕ очищать `*adf-library*`
  ```lisp
  ;; Убедиться что в run-engine-parallel НЕТ:
  ;; (setf *adf-library* nil)  ← этого быть не должно, и нет (проверено)
  ;; Но проверить что initialize-knowledge-base не затирает существующие ADF
  ```

---

## Интеграция с БД

### Проблема

Текущий эксперимент не использует Neon DB вообще. Гипотеза "persistent knowledge ускоряет" не проверяется.

### Исправления

- [ ] **P0** Добавить режим `--db-backed` в `exp_complexity_ceiling.lisp`
  ```lisp
  (defun run-complexity-experiment (&key (two-phase t) (db-backed nil))
    ;; ... setup ...
    (if two-phase
        (progn
          ;; Phase 1: search + save to DB
          (let ((result (run-engine-parallel '(sin v1) domain 200 num-threads
                                             :reset-state t)))
            ;; Flush best results to DB
            (when db-backed
              (flush-best-to-database (car result)))
            ;; Phase 2: load from DB + search
            (when db-backed
              (initialize-knowledge-base :min-fitness 0.9))
            (run-engine-parallel '(add v1 (sin v1)) domain iterations num-threads
                                 :reset-state nil)))
        ;; one-shot control
        (run-engine-parallel '(sin v1) domain (+ iterations 200) num-threads))))
  ```

- [ ] **P0** Реализовать `flush-best-to-database`
  ```lisp
  (defun flush-best-to-database (best-ast)
    "Saves the best AST to the persistent knowledge base."
    (log-fitness-telemetry "phase-winner" 1.0 '(nil) best-ast)
    ;; Вариант: вызвать Python flush
    (uiop:run-program '("python3" "v9/telemetry/telemetry_logger.py" "flush")
                      :ignore-error-status t))
  ```

- [ ] **P1** Добавить третий режим: `--db-pre-seeded` (БД заполнена заранее)
  ```lisp
  ;; Вариант A: Пустая БД → ищем → сохраняем → ищем снова (sequential)
  ;; Вариант B: БД заполнена из предыдущих запусков → ищем (warm start)
  ;; Вариант C: One-shot без БД (baseline)
  ```

- [ ] **P2** Записывать в БД metadata эксперимента (target formula, depth, mode)

---

## Метрики и воспроизводимость

### Воспроизводимость

- [ ] **P0** Добавить seed parameter
  ```lisp
  (defun run-complexity-experiment (&key (two-phase t) (db-backed nil) (seed 42))
    (setf *random-state* (make-random-state seed))
    ...)
  ```

- [ ] **P1** Записывать seed в экспериментальные результаты

### Метрики

- [ ] **P0** Считать глубину AST найденной формулы
  ```lisp
  (defun ast-depth (ast)
    (if (atom ast) 0
        (1+ (apply #'max (mapcar #'ast-depth (cdr ast))))))
  ```

- [ ] **P0** Считать количество уникальных ADF использованных
  ```lisp
  (defun count-adf-usage (ast)
    "Counts how many ADF symbols appear in the AST."
    (cond ((null ast) 0)
          ((atom ast) (if (and (symbolp ast)
                               (or (search "ADF" (symbol-name ast))
                                   (search "DB-ADF" (symbol-name ast))))
                          1 0))
          (t (+ (count-adf-usage (car ast))
                (count-adf-usage (cdr ast))))))
  ```

- [ ] **P1** Записывать в CSV: `mode,run_id,seed,phase1_depth,phase2_depth,total_iterations,time_sec,adfs_used`

- [ ] **P1** Добавить проверку что one-shot **не** нашёл формулу (для validation гипотезы)
  ```lisp
  ;; Если one-shot нашёл формулу за меньшее время — гипотеза отвергнута
  (when (and (= one-shot-penalty 0.0) (< one-shot-iters total-two-phase-iters))
    (format t "[WARNING] One-shot found solution faster! Hypothesis rejected.~%"))
  ```

---

## Сводная таблица

| Приоритет | Количество | Описание |
|-----------|-----------|----------|
| P0 | 7 | Target formula, state transfer, seed, DB integration, metrics |
| P1 | 6 | Target depth param, explicit ADF registration, CSV format |
| P2 | 2 | Target consistency check, DB metadata |
| **Итого** | **15** | |

### Критический путь

```
P0-1: Исправить target formula (sin(x+sin(x+sin(x))))
  ↓
P0-2: Создать complex_formula.csv
  ↓
P0-3: Добавить :reset-state в run-engine-parallel
  ↓
P0-4: Передавать best-phase1 как base-ast для Phase 2
  ↓
P0-5: Добавить --db-backed режим
  ↓
P0-6: Реализовать flush-best-to-database
  ↓
P0-7: Seed parameter для воспроизводимости
```

---

*Чеклист создан: 01.07.2026 | Источник: 01_v9_audit.md §8*
