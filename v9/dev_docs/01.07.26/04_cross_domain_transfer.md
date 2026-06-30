# 04 — Чеклист: Эксперимент «Перекрестное обучение» (Cross-Domain Transfer)

**Категория:** Эксперимент 3 — Transfer между доменами
**Аудит:** `01_v9_audit.md` §9 + §10 (системный дефект)
**Файлы:** `exp_cross_domain.lisp`, `experiment_nspl_cross_domain.lisp`
**Гипотиза:** Математические структуры универсальны, ADF из одного домена ускоряют поиск в другом

---

## Содержание

1. [Системный дефект: run-engine-parallel](#системный-дефект-run-engine-parallel)
2. [Simple variant: exp_cross_domain.lisp](#simple-variant-exp_cross_domainlisp)
3. [NSPL variant: experiment_nspl_cross_domain.lisp](#nspl-variant-experiment_nspl_cross_domainlisp)
4. [Метрики transfer](#метрики-transfer)
5. [Сводная таблица](#сводная-таблица)

---

## Системный дефект: run-engine-parallel

### Корневая причина

**Файл:** `v9/src/engine.lisp:352-355`

```lisp
(defun run-engine-parallel (base-ast domain iterations num-threads)
  (log-telemetry "experiment_started" ...)
  (setf *discovered-axioms* nil)    ; ← СБРОС
  (initialize-knowledge-base)        ; ← ПЕРЕЗАГРУЗКА ИЗ БД
  ...)
```

При каждом вызове `run-engine-parallel`:
- `*discovered-axioms*` обнуляется
- `initialize-knowledge-base` перезагружает из БД (если есть)

**Влияние на cross-domain:** Phase 1 (arithmetic) аксиомы теряются при начале Phase 2 (logic).

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

- [ ] **P0** Добавить `:keep-existing` параметр в `initialize-knowledge-base`
  ```lisp
  (defun initialize-knowledge-base (&key (min-fitness 0.9) (keep-existing nil))
    (let ((knowledge (fetch-telemetry-knowledge :min-fitness min-fitness)))
      (when knowledge
        ;; ADF
        (dolist (ast-str (getf knowledge :asts))
          (let ((ast (handler-case (read-from-string ast-str) (error () nil))))
            (when ast
              (unless (member ast *adf-library* :key #'cdr :test #'equal)
                (let ((adf-sym (intern (format nil "DB-ADF-~D" (1+ (length *adf-library*))))))
                  (push (cons adf-sym ast) *adf-library*)))))))
        ;; Axioms — только если НЕ keep-existing
        (unless keep-existing
          (setf *discovered-axioms* nil))
        (dolist (axiom (getf knowledge :axioms))
          (unless (member axiom *discovered-axioms* :test #'string-equal)
            (push axiom *discovered-axioms*)))))))
  ```

- [ ] **P1** Добавить `--cross-domain` режим в engine CLI для автоматического multi-domain run
  ```lisp
  (defun run-cross-domain-sequence (domains base-asts iterations num-threads)
    "Runs multiple domains sequentially, preserving state between them."
    (loop for domain in domains
          for base-ast in base-asts
          for i from 0
          do (format t "~%--- Phase ~D: ~A ---~%" (1+ i) domain)
             (run-engine-parallel base-ast domain iterations num-threads
                                  :reset-state (= i 0))))
  ```

---

## Simple variant: exp_cross_domain.lisp

### Текущий код

```lisp
(defun run-cross-domain-experiment ()
  (let ((num-threads (detect-cpu-cores)))
    (run-engine-parallel '(mul x (sub 1 x)) :arithmetic 100 num-threads)
    (run-engine-parallel '(and p q) :logic 100 num-threads)
    (run-engine-parallel '(seq (h q1) (h q2)) :quantum 100 num-threads)))
```

### Исправления

- [ ] **P0** Использовать `:reset-state nil` для Phase 2 и Phase 3
  ```lisp
  (defun run-cross-domain-experiment ()
    (let ((num-threads (detect-cpu-cores)))
      ;; Phase 1: Accumulate knowledge (reset state)
      (run-engine-parallel '(mul x (sub 1 x)) :arithmetic 200 num-threads
                           :reset-state t)
      ;; Phase 2: Transfer to logic (keep state)
      (run-engine-parallel '(and p q) :logic 200 num-threads
                           :reset-state nil)
      ;; Phase 3: Transfer to quantum (keep state)
      (run-engine-parallel '(seq (h q1) (h q2)) :quantum 200 num-threads
                           :reset-state nil)))
  ```

- [ ] **P0** Увеличить итерации: `100` → `200-500` (100 мало для meaningful transfer)

- [ ] **P1** Добавить явную передачу best-ast между фазами
  ```lisp
  (defun run-cross-domain-experiment ()
    (let* ((num-threads (detect-cpu-cores))
           ;; Phase 1
           (result1 (run-engine-parallel '(mul x (sub 1 x)) :arithmetic 200 num-threads))
           (best1 (car result1)))
      (format t "Phase 1 winner: ~A~%" best1)
      ;; Phase 2 — seed с best из Phase 1
      (let* ((result2 (run-engine-parallel best1 :logic 200 num-threads
                                           :reset-state nil))
             (best2 (car result2)))
        (format t "Phase 2 winner: ~A~%" best2)
        ;; Phase 3 — seed с best из Phase 2
        (let* ((result3 (run-engine-parallel best2 :quantum 200 num-threads
                                             :reset-state nil)))
          (format t "Phase 3 winner: ~A~%" (car result3))))))
  ```

- [ ] **P1** Добавить метрики: сколько ADF из Phase 1 использованы в Phase 2
  ```lisp
  (defun count-adf-usage (ast)
    (cond ((null ast) 0)
          ((atom ast) (if (and (symbolp ast)
                               (search "ADF" (symbol-name ast)))
                          1 0))
          (t (+ (count-adf-usage (car ast))
                (count-adf-usage (cdr ast))))))
  ```

- [ ] **P2** Добавить `--target-domains` parameter для конфигурирования доменной последовательности

---

## NSPL variant: experiment_nspl_cross_domain.lisp

### Что хорошо (не требует исправлений)

- [x] Binary serialization (ast-to-nspl, serialize-nspl, deserialize-nspl)
- [x] Domain masking (quantum ops → unknown_op → electro operators)
- [x] Collision resolution (resolve-collision)
- [x] Multi-threaded (sb-thread)
- [x] Prolog invariants (nspl_invariants.pl)
- [x] Метрики (translation_attempts, valid_functors, hit_rate_percent)

### Проблемы и исправления

#### Mock network pipe

- [ ] **P1** Добавить flag `--real-network` для TCP-соединения
  ```lisp
  (defvar *use-real-network* nil)

  (defun ltp-send (byte-vector)
    (if *use-real-network*
        (tcp-send byte-vector)
        (sb-thread:with-mutex (*ltp-mutex*)
          (push byte-vector *ltp-queue*))))

  (defun ltp-receive ()
    (if *use-real-network*
        (tcp-receive)
        (sb-thread:with-mutex (*ltp-mutex*)
          (pop *ltp-queue*))))
  ```

- [ ] **P3** Реализовать TCP-сервер на Lisp для реального network test

#### Node A: бесконечный цикл

- [ ] **P0** Добавить timeout
  ```lisp
  (defun node-a-quantum ()
    (let ((start-time (get-internal-real-time))
          (timeout-seconds 30))
      (loop while (not *cross-domain-solved*) do
        (when (> (/ (- (get-internal-real-time) start-time)
                     internal-time-units-per-second)
                 timeout-seconds)
          (format t "[Node A] Timeout after ~Ds. Halting.~%" timeout-seconds)
          (return))
        ;; ... existing code ...
        )))
  ```

- [ ] **P1** Добавить max-attempts вместо time-based timeout
  ```lisp
  (defvar *max-broadcasts* 20)

  (defun node-a-quantum ()
    (let ((broadcast-count 0))
      (loop while (and (not *cross-domain-solved*)
                       (< broadcast-count *max-broadcasts*))
            do (incf broadcast-count)
               ;; ... broadcast ...
            finally (when (not *cross-domain-solved*)
                      (format t "[Node A] Max broadcasts reached.~%")))))
  ```

#### Hardcoded operators

- [ ] **P1** Вынести electro-операторы в конфигурацию
  ```lisp
  ;; В начале файла или в конфиге:
  (defvar *electro-operators*
    '(lc_resonance inductive_shift magnetic_flux hall_effect capacitive_load seq))

  ;; В node-b-electro:
  (cognitive-engine::*current-operators* *electro-operators*)
  ```

- [ ] **P2** Добавить electro-операторы в `*unified-operators*` в engine.lisp
  ```lisp
  ;; В engine.lisp — добавить:
  (defvar *unified-operators* '(+ - * / add sub mul div deriv int sin cos
    seq matrix row matmul transpose cross dot scale norm gamma add_vel carnot
    delta_s entropy info_bound and or implies not
    lc_resonance inductive_shift magnetic_flux hall_effect capacitive_load))
  ```

#### resolve-collision: random → fitness-based

- [ ] **P2** Реализовать fitness-weighted выбор
  ```lisp
  (defvar *operator-fitness* (make-hash-table))

  (defun resolve-collision (candidates)
    "Picks candidate probabilistically based on historical fitness."
    (let* ((weights (mapcar (lambda (c)
                              (gethash c *operator-fitness* 1.0))
                            candidates))
           (total (apply #'+ weights))
           (r (random total)))
      (loop for candidate in candidates
            for w in weights
            do (decf r w)
               (when (<= r 0) (return candidate)))))

  (defun update-fitness! (operator fitness)
    "Updates fitness weight for an operator."
    (let ((current (gethash operator *operator-fitness* 1.0)))
      (setf (gethash operator *operator-fitness*)
            (+ current (* 0.1 (- fitness current))))))
  ```

- [ ] **P3** Записывать collision resolution decisions в telemetry

---

## Метрики transfer

### Текущие метрики (NSPL)

- [x] `translation_attempts` — количество попыток transfer
- [x] `valid_functors` — успешные transfers
- [x] `hit_rate_percent` — `valid_functors / translation_attempts`
- [x] `negative_transfers` — transfers, которые ухудшили penalty

### Дополнительные метрики

- [ ] **P1** Добавить `adf_reuse_count` — сколько ADF из source domain использованы в target
  ```lisp
  ;; В node-b-electro, после map:
  (let ((adf-count (count-adf-usage mapped-ast)))
    (incf *total-adf-reuse* adf-count)
    (format t "[Metrics] ADFs reused: ~D~%" adf-count))
  ```

- [ ] **P1** Добавить `transfer_time_ms` — время на transfer (serialization + deserialization + masking)
- [ ] **P2** Добавить `structural_similarity` — similarity между source и target AST
  ```lisp
  (defun ast-structural-distance (ast1 ast2)
    "Computes edit distance between two ASTs."
    ...)
  ```

- [ ] **P2** Записывать все метрики в CSV для анализа
  ```
  domain_from,domain_to,translation_attempts,valid_functors,hit_rate_percent,
  negative_transfers,adf_reuse_count,transfer_time_ms
  ```

---

## Сводная таблица

| Приоритет | Количество | Описание |
|-----------|-----------|----------|
| P0 | 5 | :reset-state в engine, timeout для Node A, увеличение итераций |
| P1 | 8 | Explicit best-ast transfer, metrics, electro config, TCP flag |
| P2 | 5 | Unified operators, structural similarity, CSV, fitness-based collision |
| P3 | 2 | TCP server, collision telemetry |
| **Итого** | **20** | |

### Критический путь

```
P0-1: Добавить :reset-state в run-engine-parallel (engine.lisp)
  ↓
P0-2: Исправить exp_cross_domain.lisp (:reset-state nil для Phase 2-3)
  ↓
P0-3: Добавить timeout в node-a-quantum (experiment_nspl_cross_domain.lisp)
  ↓
P0-4: Увеличить iterations до 200+
  ↓
P0-5: Протестировать transfer — убедиться что ADF из Phase 1 используются в Phase 2
  ↓
P1-1: Добавить explicit best-ast transfer между фазами
  ↓
P1-2: Добавить adf_reuse_count и transfer_time_ms
```

### Зависимость от документа 01

P0-1 и P0-2 **требуют** исправления `run-engine-parallel` (§10 аудита). Это общий fix для всех экспериментов — см. `01_neon_infra.md`, секция "knowledge_loader.lisp".

---

*Чеклист создан: 01.07.2026 | Источник: 01_v9_audit.md §9-§10*
