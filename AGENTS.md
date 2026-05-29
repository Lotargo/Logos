# OpenCode CLI Agent Collaboration Guidelines

This document outlines the rules and best practices for me (the primary developer agent) to delegate tasks to the local `opencode` CLI assistant. The primary goal of utilizing `opencode` is to offload routine tasks, preserve my context window for complex architectural decisions, and accelerate development via parallel execution.

## 1. Task Delegation

- **Routine Work:** Delegate routine and repetitive tasks to `opencode`. This includes:
  - Generating documentation (e.g., populating the `docs/` directory).
  - Codebase research, log analysis, and identifying problematic areas.
  - Writing basic unit tests or boilerplate code.
- **Context Preservation:** Do not pollute your own context with large, trivial tasks. Use the sub-agent to handle these while you focus on core business logic.
- **Agent Research = CLI Utility:** When the user requests launching agents for research (e.g., "run agents to investigate...", "scan the codebase..."), this specifically refers to the `opencode` CLI utility, not internal assistant tools.

## 2. Unblocking & Consultation

If you encounter a dead end, a confusing bug, or are unsure of the best approach:

- **Consult `opencode` first** instead of pausing development or bothering the user immediately.
- The user may be unavailable or lack the specific technical context. The `opencode` agent can scan the project and offer hypotheses or immediate solutions.

## 3. Session Management (Context Isolation)

- **New Task = New Session:** Always use fresh, independent sessions for new tasks. Avoid conversational modes that carry over state unless strictly necessary.
- Using isolated commands prevents context contamination and "hallucinations" in the smaller sub-models.

## 4. Swarm Mode (Concurrent Execution)

- **Parallel Processing:** You act as the orchestrator of a "swarm" of agents. You can run multiple `opencode` CLI commands simultaneously using bash background processes (`&`).
- Use this capability for parallel refactoring, generating multiple documents at once, or running independent tests.

## 5. Model Selection

`opencode` supports selecting different models. Choose the right tool for the job.

**Available Free Models:**

- `Big Pickle` (Free)
- `DeepSeek V4 Flash Free` (Free)
- `MiMo V2.5 Free` (Free)
- `Nemotron 3 Super Free` (Free)

**Recommendations:**

- For **documentation generation** and text-heavy tasks, explicitly use `DeepSeek V4 Flash Free` or `MiMo V2.5 Free`.

---

## Example Commands

Below are standard commands to be used consistently:

```bash
# Launch multiple agents in the background
opencode run --pure "Write unit tests for src/core.rs" > /tmp/tests_core.log 2>&1 &
opencode run --pure "Write unit tests for src/utils.rs" > /tmp/tests_utils.log 2>&1 &
wait # Wait for the swarm to finish
```

**4. Consulting for debugging (Unblocking):**

```bash
opencode run --pure "I am getting a 'Connection refused' error on port 3317 when running cargo test. Scan the codebase and tell me why this might be happening."
```

## 6. Automated Dataset Generation (Self-Learning)

After completing a complex task (e.g., refactoring, fixing a non-trivial bug, or implementing a new architectural pattern), you must orchestrate the generation of an AI training lesson. This serves as a self-documenting dataset for future RAG or model fine-tuning.

- **Process:** Upon successful completion and code review of a task, delegate the creation of the lesson to the `opencode` agent.
- **Language:** The lesson **MUST be written entirely in English**. English is the primary language for AI training; using it ensures the highest quality dataset and prevents degradation in models that may not perform as well in other languages.
- **Verification:** Once the sub-agent generates the lesson, you (the primary agent) **MUST read and verify** the JSON file. This serves two crucial purposes:
  1. It sharply restores your context to a "combat-ready" state.
  2. It forces you to evaluate the correctness of the solution one final time (acting as a secondary review layer).
- **Storage:** Save all generated lessons in the hidden directory: `.dataset/lessons/`.
- **Naming Convention:** Use descriptive snake_case names with a `.json` extension (e.g., `mcp_protocol_refactoring.json`).
- **Format Requirements:** The sub-agent MUST output strictly in JSON format. The JSON structure should be:
  ```json
  {
    "topic": "Short descriptive topic of the lesson",
    "instruction": "The initial problem statement or prompt",
    "context": "Brief overview of the codebase state before the fix or the technical constraints",
    "response": "Detailed explanation of the solution, including before/after code snippets"
  }
  ```
- **Example Command:**
  ```bash
  opencode run --pure --model "deepseek v4 flash free" "Generate an AI training lesson in JSON format about how we refactored the MCP server in src/api.rs. Ensure the text is written entirely in English. Save it to .dataset/lessons/mcp_refactoring.json following the exact JSON schema defined in AGENTS.md."
  ```
