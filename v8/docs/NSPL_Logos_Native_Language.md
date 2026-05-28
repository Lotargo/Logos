# NSPL + Logos: Native Machine Communication Protocol

> **Статус**: `[~]` концептуальное исследование
> **Дата**: 28.05.2026

---

## 1. Проблема: строковый IPC между модулями ИИ

Текущий пайплайн коммуникации Sonata → Logos:

```
Free Pascal (Sonata GPU)
  → tensor outputs (float32)
  → сериализация в JSON/строку
  → pipe/stdin
  → SBCL Lisp (Logos)
    → read-from-string (парсинг)
    → AST construction
    → cons cells allocation
    → GC
  → Prolog term generation
  → pipe назад
  → Pascal StrToFloat (парсинг)
  → float penalty
```

**Измеримые проблемы**:

- Каждый шаг — парсинг строки: `O(n)` по длине сообщения
- Аллокации cons cells → GC latency (SBCL generational GC ~1-3ms на сообщение)
- Формат (JSON, S-expressions) спроектирован для **человеческой читаемости**, не для машинной эффективности
- schema update = правка кода человеком

---

## 2. NSPL: бинарное кодирование смысла

NSPL — не язык, а **битовая упаковка семантики** в фиксированный record.

### Структура NeuroID

```
┌──────────────────────────────────────────────────────┐
│                   NeuroID (28 bytes)                  │
├────────────────┬──────────────────┬──────────────────┤
│ Semantic Core  │ Context Shell    │ Flags            │
│  (UInt64)      │   (UInt128)      │    (UInt32)      │
│  8 bytes       │   16 bytes       │    4 bytes       │
├────────────────┼──────────────────┼──────────────────┤
│ Идентификатор  │ Параметры        │ Битовые флаги    │
│ понятия в      │ контекста        │ (аффект,         │
│ таксономии     │ (интенсивность,  │  приоритет,      │
│                │  длительность)   │  режим)          │
└────────────────┴──────────────────┴──────────────────┘
```

### Битовая разметка

```pascal
type
  TNeuroID = packed record
    SemanticCore: UInt64;
      // bits 0-15:   категория (0x1F = state, 0x2A = action, 0x3B = relation)
      // bits 16-31:  подкатегория
      // bits 32-47:  уточнение
      // bits 48-63:  reserved для иерархии
    ContextShell: UInt128;
      // Intesity, Duration, Count, ...
    Flags: UInt32;
      // bit 0:    priority (high/low)
      // bit 1-3:  mode (query/command/report)
      // bit 4-7:  affect valence
  end;
```

### Пример

```pascal
// 0x2A01: действие:поиск, объект:ресурс, приоритет:высокий
NeuroID := TNeuroID(
  SemanticCore:  $2A01_0001_0000_0001,  // action:search:resource
  ContextShell:  $0000_0000_0000_0005,  // count=5, urgency=0.8
  Flags:         $80000001              // high priority, positive
);
```

В отличие от JSON, NeuroID:

- Не требует парсинга — `TNeuroID` читается как record
- Занимает 28 байт вместо ~200 для `{"action":"search","object":"resource"}`
- Проверяется компилятором на уровне типа, не runtime schema

---

## 3. Logos: что это такое на самом деле

Logos — **не** нейросеть и **не** LLM. Это комбинация:

1. **Genetic programming engine** (SBCL Common Lisp) — эволюционный поиск AST
2. **Formal verification layer** (SWI-Prolog) — проверка AST на математические аксиомы
3. **IPC bridge** (Free Pascal → pipe → SBCL)

### Что Logos проверяет (и не проверяет)

| Censor          | Что проверяет                         | Как                      | Формально?              |
| --------------- | ------------------------------------- | ------------------------ | ----------------------- |
| arithmetic      | Корректность арифметических выражений | simplify/2               | Да                      |
| quantum         | Унитарность: U·U^T = I                | is_unitary_ast/1         | Да                      |
| regression      | MSE формулы против CSV                | regression_censor/2      | Да                      |
| logic           | Тип boolean + таблица истинности      | logic_censor/2           | Да                      |
| hardware        | Gate count, propagation delay         | hardware_censor/2        | Да                      |
| curry_howard    | Proof type correctness                | curry_censor/2           | Да                      |
| **nlp**         | **Грамматика текста (DCG)**           | **phrase/2**             | **Нет (probabilistic)** |
| **adversarial** | **Edge-case выживаемость**            | **adversarial_censor/2** | **Нет (эвристика)**     |

Вывод: Logos силён в том, что **формализуемо** (математика, логика, типы). Он слаб в том, что формализовать нельзя (грамматика естественного языка, adversarial robustness).

---

## 4. Пересечение NSPL + Logos: что реально работает

### 4.1 NSPL как compressed pipe protocol (Low effort, high impact)

Замена строкового IPC на бинарный:

```pascal
type
  TNeuroIDMessage = packed record
    MsgType: UInt8;     // 0=Censor, 1=Reflect, 2=MetaQuery
    Domain: UInt8;      // 0=Arithmetic, 1=Quantum, 2=NLP, ...
    Mode: UInt8;        // 0=Target, 1=Novelty
    Reserved: UInt8;    // alignment
    Payload: TNeuroID;  // 28 bytes
  end; // = 32 bytes total
```

**Измеримый эффект**:

- ~200 байт строки → 32 байта packed record (6.25× сжатие)
- Парсинг: `read-from-string` (SBCL) → type punning (zero-cost)
- GC: аллокации строк + cons cells → stack-allocated record
- Валидация: runtime schema → compile-time type check

### 4.2 NeuroID как ключ для Prolog-верификации

Сейчас Logos получает AST строкой и парсит. С NSPL:

```prolog
%% Верификация NeuroID через существующие Prolog censors
verify_neuroid(NeuroID, Penalty) :-
    decode_core(NeuroID, Category, SubCategory, Spec),
    category_domain(Category, Domain),
    %% routing к существующему domain-specific censor
    censor(target, Domain, term(Category, SubCategory, Spec), Penalty).

%% mapping: NeuroID категория → Prolog domain
category_domain(0x01, arithmetic).
category_domain(0x02, quantum).
category_domain(0x03, logic).
category_domain(0x04, regression).
```

**Смысл**: NSPL не заменяет Prolog censors, а даёт им **бинарный ключ** вместо строки.

### 4.3 Logos meta_evolve как генератор новых NeuroID (исследование)

`meta_evolve.lisp` изобретает новые математические операторы. Аналогично — новые NeuroID:

```lisp
(defun nspl-mutate (proc-cell existing-codes)
  ;; 1. Случайная мутация битов существующего NeuroID
  (let ((new-code (bitwise-xor (random-existing) (random-mask))))
    ;; 2. Проверка через Prolog censor
    (multiple-value-bind (penalty axiom)
        (check-neuroid proc-cell new-code)
      ;; 3. Если penalty < threshold → добавляем в словарь
      (if (< penalty 1.0)
          (register-concept proc-cell new-code axiom)
          :invalid))))
```

**Ограничение**: Logos может генерировать новые коды, но **не может присвоить им семантику**. Semantics присваивается тем, **как код используется** в системе (частота, контекстные связи). Logos только проверяет, что код не коллизирует с существующими.

### 4.4 Sleep cycle как data-driven словарная оптимизация (исследование)

Logos уже реализует Day/Night cycle (Pattern C). NSPL добавляет структуру:

```
Night phase:
  1. Frequency analysis: какие NeuroID сколько раз встретились в dreams
  2. Pruning: NeuroID с count=0 → удаление из словаря
  3. Merging: NeuroID с близкой семантикой (Hamming distance < threshold) → объединение
  4. Splitting: NeuroID с высокой variance в контекстных параметрах → split на уточнения
  5. Validation: Prolog censors проверяют, что новый словарь не нарушает axioms
```

**Это не консолидация знаний в человеческом смысле**. Это data compression: удаление избыточности в словаре на основе статистики использования.

### 4.5 TNeuroID bridge Sonata ↔ Logos (long-term)

```
Float embedding (768 bytes) → Quantize → TNeuroID (28 bytes)
  → TBitLinear ternary matmul
  → TLogosBridge.WriteBinary(TNeuroIDMessage)
  → pipe
  → Logos: read record → censor
  → penalty pipe back
  → Adam optimizer
```

**Что это даёт**: единый формат данных от эмбеддинга до верификации, без конверсий.

---

## 5. Что НЕ входит в NSPL + Logos (и почему)

| Концепция                   | Почему исключена                                                                                                                     |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| **Trust levels**            | Числа 0.85, 0.92 не выводимы ни из чего. Нельзя формально обосновать, почему trust=0.84 недостаточно, а 0.85 — достаточно.           |
| **Ethical axioms**          | Этика неформализуема: меняется со временем, зависит от культуры, содержит неразрешимые парадоксы. Prolog не может доказать "этично". |
| **Consciousness / qualia**  | Не определено, не измеряемо, не верифицируемо.                                                                                       |
| **Audit ledger**            | Решение в поиске проблемы. Кто читает журнал? Зачем?                                                                                 |
| **DPO-like grammar reward** | NLP censor уже есть, но его penalty — эвристика, не формальная гарантия. Не стоит переоценивать.                                     |

### Что можно проверять формально

| Свойство               | Пример                                          | Инструмент                |
| ---------------------- | ----------------------------------------------- | ------------------------- |
| **Type safety**        | `TModuleID` ≠ `TOrdinaryInt`                    | Pascal type system        |
| **Invariants**         | `module_count ≤ max_modules`                    | Prolog invariant/1        |
| **Bounds**             | `targets < total`                               | Prolog bound_check/2      |
| **Domain consistency** | `action ∈ valid_actions`                        | Prolog domain_check/2     |
| **No collisions**      | `NeuroID₁ ≠ NeuroID₂ → semantics₁ ≠ semantics₂` | Prolog uniqueness_check/1 |

---

## 6. Сравнение: JSON vs NSPL + Logos

| Критерий             | JSON                             | NSPL + Logos                      |
| -------------------- | -------------------------------- | --------------------------------- |
| **Размер на wire**   | ~200-500 байт                    | 32 байта                          |
| **Парсинг**          | `read-from-string`, `json.parse` | type punning (zero-copy)          |
| **GC overhead**      | Да (строки, cons cells)          | Нет (record на стеке)             |
| **Валидация**        | Schema validator (синтаксис)     | Prolog censor (семантика)         |
| **Эволюция**         | Human edits schema               | meta_evolve генерирует новые коды |
| **Типобезопасность** | Runtime                          | Compile-time (Pascal record)      |
| **Вывод**            | Писать вручную                   | Prolog inference                  |
| **Инварианты**       | Нет                              | Prolog invariant/1                |

---

## 7. Практический план

### Phase A: NSPL pipe protocol — сейчас (Low, ~120 строк)

- `sonata_logos.pas`: `TNeuroIDMessage` packed record, `WriteBinary`/`ReadBinary`
- `engine.lisp`: `bridge-loop` — бинарное чтение + dispatch
- `rules.pl`: `verify_neuroid/2` routing predicate

### Phase B: Formal verification via NeuroID — после Phase A (Medium, ~150 строк)

- Prolog `nspl_invariants.pl`: декларация инвариантов системы
- `meta_evolve.lisp`: `nspl-mutate` для генерации новых кодов
- Sleep cycle: pruning + merging по статистике использования

### Phase C: TNeuroID bridge — исследование (High, ~300 строк)

- `TEmbedding` → опциональный выход в TNeuroID
- `TBitLinear` × TNeuroID
- End-to-end: forward → NeuroID → pipe → censor → penalty → backward

---

## 8. Резюме

**NSPL + Logos** — это не новая парадигма ИИ и не шаг к AGI.

Это **инженерное улучшение** существующей архитектуры:

| До                        | После                          |
| ------------------------- | ------------------------------ |
| Строковый IPC (200+ байт) | Бинарный IPC (32 байта)        |
| Ручная валидация schema   | Prolog-верификация инвариантов |
| Человек правит формат     | meta_evolve генерирует коды    |
| Типы — в документации     | Типы — в компиляторе           |

Всё, что формализуемо (типы, границы, инварианты, axioms) — Logos проверяет.
Всё, что неформализуемо (этика, trust, сознание) — вынесено за скобки.

NSPL без Logos — просто бинарный протокол (как Protobuf, но компактнее).
Logos без NSPL — мощный verifier на медленных pipe.
Только вместе: компактный, верифицируемый, эволюционирующий IPC.
