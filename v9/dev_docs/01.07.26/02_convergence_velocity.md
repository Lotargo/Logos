# 02 — Чеклист: Эксперимент «Ускорение сходимости» (Convergence Velocity)

**Категория:** Эксперимент 1 — A/B comparison с/без persistent knowledge
**Аудит:** `01_v9_audit.md` §7
**Файлы:** `bench_persistence.py`, `report_exp1.py`, `exp_complexity_ceiling.lisp`

---

## Содержание

1. [A/B Comparison: core](#ab-comparison-core)
2. [bench_persistence.py — Оркестратор](#bench_persistencepy--оркестратор)
3. [report_exp1.py — Генерация отчёта](#report_exppy--генерация-отчёта)
4. [exp_complexity_ceiling.lisp — Lisp-скрипт](#exp_complexity_ceilinglisp--lisp-скрипт)
5. [Сводная таблица](#сводная-таблица)

---

## A/B Comparison: core

### Реализация comparison

- [ ] **P0** Создать `v9/experiments/exp_convergence_ab.lisp` — единый скрипт с двумя режимами
  ```lisp
  ;; Режим 1: Baseline (без БД)
  ;; Режим 2: Persistent (с БД, pre-seeded ADF)
  ;;
  ;; Оба режима решают ОДНУ И ТУ ЖЕ задачу:
  ;;   target: f(x) = x^2 + sin(x)*cos(x)
  ;;   base-ast: (+ x 0)
  ;;   iterations: одинаковые для обоих
  ;;   domain: :regression
  ```

- [ ] **P0** Добавить параметр `--mode baseline|persistent` в Lisp-скрипт
  ```lisp
  (defun run-convergence-test (&key (mode :baseline))
    (let ((base-ast '(+ x 0))
          (dataset "v9/data/regression_data.csv")
          (iterations 5000))
      (when (eq mode :persistent)
        (initialize-knowledge-base :min-fitness 0.9))
      (run-engine-parallel base-ast :regression iterations (detect-cpu-cores))))
  ```

- [ ] **P0** Baseline-режим ДОЛЖЕН отключить `initialize-knowledge-base`
  ```lisp
  ;; В engine.lisp — добавить parameter:
  (defparameter *use-persistent-knowledge* t)

  (defun run-engine-parallel (base-ast domain iterations num-threads &key (reset-state t))
    (when reset-state
      (setf *discovered-axioms* nil))
    (when *use-persistent-knowledge*
      (initialize-knowledge-base))
    ...)
  ```

- [ ] **P0** Для baseline: `(let ((*use-persistent-knowledge* nil)) ...)` — снять БД

- [ ] **P1** Добавить seed для `*random-state*` чтобы A и B были сравнимы
  ```lisp
  (defun run-convergence-test (&key (mode :baseline) (seed 42))
    (setf *random-state* (make-random-state seed))
    ...)
  ```

- [ ] **P1** Оба режима должны писать результаты в CSV с колонками:
  ```
  mode,run_id,iterations,time_sec,converged,final_fitness,seed
  baseline,1,1234,45.2,true,0.9987,42
  persistent,1,567,22.1,true,0.9993,42
  ```

- [ ] **P2** Добавить `warmup` runs (3-5 без записи) перед основными замерами

### Метрики для сравнения

- [ ] **P0** Считать итерации до convergence (penalty = 0.0)
- [ ] **P0** Считать wall-clock time
- [ ] **P1** Считать throughput (ASTs/sec) — уже есть в engine dashboard
- [ ] **P2** Считать `knowledge_weights_used` — сколько ADF из БД были применены

---

## bench_persistence.py — Оркестратор

### Запуск A/B comparison

- [ ] **P0** Запускать НОВЫЙ `exp_convergence_ab.lisp` вместо `exp_complexity_ceiling.lisp`
  ```python
  # Было:
  results_two_phase = run_experiment_group("v9/experiments/exp_complexity_ceiling.lisp", ...)

  # Стало:
  results_baseline = run_experiment_group(
      "v9/experiments/exp_convergence_ab.lisp",
      "Convergence Velocity (Baseline)",
      iterations=5,  # ← 5 runs, не 1
      args=["--mode", "baseline"]
  )
  results_persistent = run_experiment_group(
      "v9/experiments/exp_convergence_ab.lisp",
      "Convergence Velocity (Persistent)",
      iterations=5,
      args=["--mode", "persistent"]
  )
  ```

- [ ] **P0** Увеличить `iterations` с 1 до **≥ 5**
  ```python
  # Было:
  iterations=1

  # Стало:
  iterations=5  # Минимум для статистики
  ```

- [ ] **P1** Добавить seed-трекинг: одинаковый seed для пар baseline/persistent
  ```python
  seeds = [42, 137, 256, 789, 1024]
  for seed in seeds:
      run_experiment_group(..., args=["--mode", "baseline", "--seed", str(seed)])
      run_experiment_group(..., args=["--mode", "persistent", "--seed", str(seed)])
  ```

### Парсинг метрик

- [ ] **P1** Заменить string parsing на JSON-вывод из Lisp
  ```lisp
  ;; В конце run-engine-parallel:
  (format t "~%METRICS_JSON: {\"iterations\": ~D, \"time_sec\": ~,4F, \"converged\": ~A}~%"
          total-iterations elapsed-seconds (if winners "true" "false"))
  ```

- [ ] **P1** Обновить `parse_metrics()` в bench_persistence.py
  ```python
  def parse_metrics(output):
      metrics = {'iterations': 0, 'elapsed_time': 0, 'converged': False}
      for line in output.split('\n'):
          if "METRICS_JSON:" in line:
              json_str = line.split("METRICS_JSON:", 1)[1].strip()
              parsed = json.loads(json_str)
              metrics.update(parsed)
      return metrics
  ```

- [ ] **P2** Добавить fallback на string parsing если JSON не найден

### Генерация CSV

- [ ] **P0** Генерировать CSV с результатами
  ```python
  def save_results_csv(results_baseline, results_persistent, output_path):
      rows = []
      for i, r in enumerate(results_baseline):
          rows.append({
              'mode': 'baseline',
              'run_id': i + 1,
              'iterations': r['iterations'],
              'time_sec': r['total_duration'],
              'converged': r.get('converged', False),
              'seed': seeds[i] if i < len(seeds) else None
          })
      for i, r in enumerate(results_persistent):
          rows.append({
              'mode': 'persistent',
              'run_id': i + 1,
              'iterations': r['iterations'],
              'time_sec': r['total_duration'],
              'converged': r.get('converged', False),
              'seed': seeds[i] if i < len(seeds) else None
          })
      pd.DataFrame(rows).to_csv(output_path, index=False)
  ```

- [ ] **P0** Сохранять CSV в `benchmarks_output/experiment_1/results.csv` (ожидается report_exp1.py)

---

## report_exp1.py — Генерация отчёта

### Исправление пути к данным

- [ ] **P0** Исправить `results_path`
  ```python
  # Было:
  results_path = "benchmarks_output/experiment_1/results.csv"

  # Стало (одно из):
  results_path = "benchmarks_output/results_convergence.csv"
  # ИЛИ создать директорию benchmarks_output/experiment_1/
  ```

- [ ] **P0** Убедиться что CSV генерируется до вызова report

### Статистический анализ

- [ ] **P1** Добавить t-test для сравнения baseline vs persistent
  ```python
  from scipy import stats

  t_stat, p_value = stats.ttest_ind(
      df[df['mode'] == 'baseline']['iterations'],
      df[df['mode'] == 'persistent']['iterations']
  )
  print(f"t-statistic: {t_stat:.4f}, p-value: {p_value:.6f}")
  ```

- [ ] **P1** Добавить confidence intervals для mean
  ```python
  from scipy.stats import t as t_dist

  def ci_95(data):
      n = len(data)
      mean = data.mean()
      se = data.std() / (n ** 0.5)
      h = se * t_dist.ppf(0.975, n - 1)
      return mean - h, mean + h
  ```

- [ ] **P2** Добавить effect size (Cohen's d)
  ```python
  def cohens_d(group1, group2):
      pooled_std = ((group1.std()**2 + group2.std()**2) / 2) ** 0.5
      return (group1.mean() - group2.mean()) / pooled_std
  ```

### Улучшение отчёта

- [ ] **P1** Добавить table с raw data
- [ ] **P2** Добавить boxplot с swarmplot для визуализации распределения
- [ ] **P2** Добавить percentage improvement: `((baseline - persistent) / baseline) * 100%`

---

## exp_complexity_ceiling.lisp — Lisp-скрипт

### Этот скрипт используется НЕ для Convergence Velocity

**Важно:** `exp_complexity_ceiling.lisp` — это **отдельный** эксперимент (Complexity Ceiling). Для Convergence Velocity нужен **новый** скрипт `exp_convergence_ab.lisp`.

- [ ] **P0** Создать `v9/experiments/exp_convergence_ab.lisp` (см. раздел "Реализация comparison" выше)

- [ ] **P2** Переименовать текущий `exp_complexity_ceiling.lisp` → `exp_complexity_ceiling_legacy.lisp` если он не используется корректно

---

## Сводная таблица

| Приоритет | Количество | Описание |
|-----------|-----------|----------|
| P0 | 8 | Создание A/B скрипта, фикс comparison, CSV, путь в report |
| P1 | 8 | Seed tracking, t-test, CI, JSON metrics, warmup |
| P2 | 5 | Fallback parsing, boxplot, effect size, legacy cleanup |
| **Итого** | **21** | |

### Критический путь

```
P0-1: Создать exp_convergence_ab.lisp
  ↓
P0-2: Обновить bench_persistence.py (iterations=5, вызов нового скрипта)
  ↓
P0-3: Генерация CSV в правильную директорию
  ↓
P0-4: Исправить report_exp1.py (путь к CSV)
  ↓
P1-1: Seed tracking для воспроизводимости
  ↓
P1-2: t-test и confidence intervals
```

---

*Чеклист создан: 01.07.2026 | Источник: 01_v9_audit.md §7*
