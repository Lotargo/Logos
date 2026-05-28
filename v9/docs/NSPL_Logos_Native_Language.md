# NSPL + Logos: Native Machine Communication Protocol

> **Статус**: `[~]` концептуальное исследование
> **Дата**: 28.05.2026

---

## 1. Проблема: строковый IPC между агентами

Текущий пайплайн коммуникации между узлами/агентами (Logos A → Logos B):

```
Отправляющий узел (Lisp)
  → Сериализация AST в строку (S-expressions)
  → pipe/socket
  → Принимающий узел (Logos)
    → read-from-string (парсинг)
    → AST construction
    → cons cells allocation
    → GC
  → Prolog term generation
```

**Измеримые проблемы**:

- Каждый шаг — парсинг строки: `O(n)` по длине сообщения.
- Аллокации cons cells → GC latency (SBCL generational GC ~1-3ms на сообщение).
- Строковые форматы (S-expressions, JSON) спроектированы для **человеческой читаемости**, а не для машинной эффективности.
- Потеря строгой структуры и отсутствие быстрой бинарной семантической проверки.

---

## 2. NSPL: бинарное кодирование смысла

NSPL (Neuro-Symbolic Propositional Logic) — не просто язык программирования, а **битовая упаковка семантики** в бинарные пакеты. Коммуникация происходит через LTP (Lisp Transport Protocol) с использованием байтовых массивов.

### Структура NeuroID (Гибкий бинарный формат)

```
┌──────────────────────────────────────────────────────┐
│                   NeuroID (N bytes)                  │
├────────────────┬──────────────────┬──────────────────┤
│ Semantic Core  │ Context Shell    │ Payload/AST      │
│  (UInt64)      │   (UInt64)       │  (Variable len)  │
│  8 bytes       │   8 bytes        │  N - 16 bytes    │
├────────────────┼──────────────────┼──────────────────┤
│ Идентификатор  │ Параметры        │ Битовые флаги и  │
│ домена и типа  │ (длина, id, и др)│ закодированный   │
│ операции       │                  │ AST              │
└────────────────┴──────────────────┴──────────────────┘
```

### Пример разметки (в Lisp)

```lisp
;; 0x01: Домен :arithmetic, 0x2A: Операция :add
(defstruct nspl-packet
  (domain-id 0 :type (unsigned-byte 8))
  (op-id 0 :type (unsigned-byte 8))
  (payload-length 0 :type (unsigned-byte 16))
  (data (make-array 0 :element-type '(unsigned-byte 8))))
```

В отличие от S-expressions в виде строк, бинарный NSPL:

- Занимает минимальное количество байт в памяти и при передаче.
- Использует побайтовое чтение без вызова дорогостоящего строкового парсера `read-from-string`.
- Сразу перенаправляется на Prolog-демон для проверки осмысленности (защита от "абракадабры").

---

## 3. Logos: что это такое на самом деле

Logos — **не** нейросеть и **не** LLM. Это комбинация:

1. **Genetic programming engine** (SBCL Common Lisp) — эволюционный поиск AST
2. **Formal verification layer** (SWI-Prolog) — проверка AST на математические аксиомы
3. **IPC bridge** (NSPL Binary Protocol → LTP → Prolog)

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

### 4.1 NSPL как compressed binary protocol (Low effort, high impact)

Замена строкового IPC на бинарный:

```lisp
;; Байт 0: Тип сообщения (0=Censor, 1=Reflect)
;; Байт 1: Домен (0=Arithmetic, 1=Logic, ...)
;; Байт 2-3: Длина Payload
;; Байт 4+: Payload (кодированный AST)
```

**Измеримый эффект**:

- ~200 байт строки → ~16-32 байта (сжатие на порядок).
- Парсинг: `read-from-string` → побайтовое извлечение через смещения.
- GC: уменьшение аллокаций строк.

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

### 4.5 Узел ↔ Узел (LTP Communication)

Logos A может напрямую формировать знания и передавать их Logos B через LTP (Lisp Transport Protocol). Logos B валидирует сообщение, отсекая бессмыслицу через Prolog `nspl_invariants.pl`.

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

### Phase A: NSPL Serialization в Lisp

- Написать `v9/src/nspl.lisp` с функциями сериализации и десериализации AST в бинарные потоки байт.

### Phase B: Prolog Invariants

- Создать `v9/prolog/nspl_invariants.pl`, чтобы валидировать байтовые сообщения. Logos должен понимать, что ему прислали осмысленные данные (например, валидные операторы для указанного домена), а не просто случайный мусор.

### Phase C: LTP Node Communication

- Написать тесты/симуляцию двух агентов (Logos A и Logos B), которые обмениваются байтовыми сообщениями через LTP и используют `nspl_invariants.pl` для проверки валидности.

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
