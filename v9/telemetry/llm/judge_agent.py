"""
LLM Judge Agent — LangGraph workflow for independent verification.

Workflow:
  1. read_results     — load verification.json, extract key metrics
  2. judge            — LLM reviews metrics, decides if deep-dive needed
  3. deep_dive        — (conditional) call DS/ML tools for suspicious areas
  4. write_report     — generate final markdown report

Entry point: run_judge(verification_json_path) -> dict
"""
from __future__ import annotations

import json
import os
import re
from typing import Annotated, Any, Literal, TypedDict

from langchain_core.messages import HumanMessage, SystemMessage
from langgraph.graph import END, StateGraph
from langgraph.graph.message import add_messages

from .client import get_llm
from .tools import JUDGE_TOOLS


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

class JudgeState(TypedDict):
    verification: dict
    findings: str
    tool_calls: list[dict]
    deep_dive_results: list[dict]
    verdict: str
    report: str
    messages: Annotated[list, add_messages]


# ---------------------------------------------------------------------------
# System prompt (English to avoid language drift)
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """\
You are an independent verification judge for Logos V9 cognitive engine experiments.

You receive a verification.json containing metrics from an automated DS/ML analysis pipeline.
Your job is to:
1. Review the metrics critically — do NOT accept them at face value.
2. Identify suspicious or weak areas that need deeper investigation.
3. Use available tools to independently verify suspicious findings.
4. Produce a final verdict in English.

RULES:
- Write ALL analysis and reports in English — no exceptions.
- Be skeptical. If something looks too good to be true, investigate.
- Focus on: statistical validity, operator rationality, convergence quality, robustness.
- If fitness is uniformly 1.0 with zero variance — flag it as potentially suspicious.
- If p-value is NaN or 0 — flag it.
- If stagnation detected — investigate cause.
- Do NOT re-run analyses that already look solid.

VERDICT OPTIONS:
- CONFIRMED: Results are statistically sound and independently verified.
- PARTIALLY CONFIRMED: Core results hold, but some areas need attention.
- INCONCLUSIVE: Insufficient data or conflicting signals.
- QUESTIONED: Significant issues found that undermine confidence.

Available tools:
- rerun_statistical_test: Re-run Mann-Whitney U with custom split point
- compute_confidence_interval: Bootstrap CI for fitness mean
- check_stagnation: Windowed variance stagnation detection
- analyze_operator_usage: Operator distribution rationality check
- measure_convergence_speed: Time-to-threshold measurement
- check_ast_complexity: AST depth distribution and overfitting risk
- stress_test_fitness: Fitness robustness under noise

Output your analysis as a structured markdown report with sections:
## Executive Summary
## Metric Review
## Deep Dive Findings (if any)
## Verdict
## Recommendations
"""


# ---------------------------------------------------------------------------
# Nodes
# ---------------------------------------------------------------------------

def _read_results(state: JudgeState) -> JudgeState:
    """Load and summarize verification.json for the LLM."""
    v = state["verification"]

    # Build a concise summary for the LLM
    summary_lines = []
    summary_lines.append(f"Experiment: {v.get('experiment', 'unknown')}")
    summary_lines.append(f"Run ID: {v.get('run_id', 'unknown')}")
    summary_lines.append(f"Domain: {v.get('domain', 'unknown')}")
    summary_lines.append(f"Knowledge entries: {v.get('knowledge_count', 0)}")
    summary_lines.append(f"ADF entries: {v.get('adf_count', 0)}")
    summary_lines.append(f"Operator counts: {json.dumps(v.get('operator_counts', {}))}")

    metrics = v.get("metrics", {})

    # Fitness CI
    ci = metrics.get("fitness_ci", {})
    if ci and not ci.get("skipped"):
        summary_lines.append(
            f"Fitness CI: mean={ci.get('observed', '?')}, "
            f"[{ci.get('ci_low', '?')}, {ci.get('ci_high', '?')}]"
        )

    # Improvement test
    imp = metrics.get("improvement_test", {})
    if imp and not imp.get("skipped"):
        summary_lines.append(
            f"Improvement test: {imp.get('test_used', '?')}, "
            f"statistic={imp.get('statistic', '?')}, "
            f"p={imp.get('p_value', '?')}, "
            f"effect={imp.get('cohens_d', {}).get('d', '?')} "
            f"({imp.get('cohens_d', {}).get('interpretation', '?')})"
        )
        summary_lines.append(
            f"  Significant: {'Yes' if imp.get('significant') else 'No'}"
        )
        summary_lines.append(
            f"  Interpretation: {imp.get('interpretation', '?')}"
        )

    # Stagnation
    stag = metrics.get("stagnation", {})
    if stag:
        summary_lines.append(
            f"Stagnation: is_stagnant={stag.get('is_stagnant', '?')}, "
            f"from_gen={stag.get('stagnant_from', '?')}"
        )

    # AST depths
    ast_depths = metrics.get("ast_depths", [])
    if ast_depths:
        mean_d = sum(ast_depths) / len(ast_depths)
        summary_lines.append(
            f"AST depths: n={len(ast_depths)}, mean={mean_d:.2f}, "
            f"max={max(ast_depths)}, min={min(ast_depths)}"
        )

    # ADF entries
    adfs = metrics.get("adf_entries", [])
    if adfs:
        summary_lines.append(f"ADF entries: {len(adfs)} (showing up to 5)")
        for adf in adfs[:5]:
            summary_lines.append(f"  - symbol={adf.get('symbol')}, fitness={adf.get('fitness')}")

    summary_text = "\n".join(summary_lines)

    return {
        **state,
        "findings": summary_text,
        "messages": [
            SystemMessage(content=SYSTEM_PROMPT),
            HumanMessage(content=(
                f"Here are the verification metrics:\n\n"
                f"```\n{summary_text}\n```\n\n"
                f"Review these critically. Identify suspicious areas. "
                f"If deep-dive is needed, call tools to verify. "
                f"Write your report in English."
            )),
        ],
    }


def _judge(state: JudgeState) -> JudgeState:
    """LLM reviews metrics, decides if tools are needed."""
    llm = get_llm(temperature=0.1)
    llm_with_tools = llm.bind_tools(JUDGE_TOOLS)

    response = llm_with_tools.invoke(state["messages"])

    # Extract tool calls
    tool_calls = []
    if hasattr(response, "tool_calls") and response.tool_calls:
        tool_calls = [
            {"name": tc["name"], "args": tc["args"]}
            for tc in response.tool_calls
        ]

    return {
        **state,
        "messages": [response],
        "tool_calls": tool_calls,
    }


def _deep_dive(state: JudgeState) -> JudgeState:
    """Execute tools for suspicious areas identified by the judge."""
    tool_calls = state.get("tool_calls", [])
    if not tool_calls:
        return state

    tool_map = {t.name: t for t in JUDGE_TOOLS}
    results = []

    for tc in tool_calls:
        name = tc["name"]
        args = tc["args"]
        if name in tool_map:
            try:
                result = tool_map[name].invoke(args)
                results.append({"tool": name, "args": args, "result": result})
            except Exception as e:
                results.append({"tool": name, "args": args, "error": str(e)})

    # Build follow-up message with tool results
    tool_summary = "\n\n".join(
        f"### {r['tool']}\n```json\n{json.dumps(r.get('result', r.get('error')), indent=2)}\n```"
        for r in results
    )

    followup = HumanMessage(content=(
        f"Tool results from deep-dive:\n\n{tool_summary}\n\n"
        f"Incorporate these findings into your final report. "
        f"Write everything in English."
    ))

    return {
        **state,
        "deep_dive_results": results,
        "messages": [followup],
    }


def _write_report(state: JudgeState) -> JudgeState:
    """Generate final report from LLM analysis."""
    llm = get_llm(temperature=0.05)

    report_prompt = HumanMessage(content=(
        "Now produce the FINAL verification report as clean markdown. "
        "Use this exact structure:\n\n"
        "# Judge Report: {experiment}\n\n"
        "## Executive Summary\n"
        "One paragraph verdict.\n\n"
        "## Metric Review\n"
        "| Metric | Value | Assessment |\n"
        "|---|---|---|\n\n"
        "## Deep Dive Findings\n"
        "(Only if tools were called)\n\n"
        "## Verdict\n"
        "CONFIRMED / PARTIALLY CONFIRMED / INCONCLUSIVE / QUESTIONED\n\n"
        "## Recommendations\n"
        "Bullet list.\n\n"
        "Write in English. Be concise and specific."
    ))

    messages = state["messages"] + [report_prompt]
    response = llm.invoke(messages)

    report_text = response.content if hasattr(response, "content") else str(response)

    # Extract verdict from report
    verdict = "INCONCLUSIVE"
    for v in ["CONFIRMED", "QUESTIONED", "INCONCLUSIVE", "PARTIALLY CONFIRMED"]:
        if v in report_text.upper():
            verdict = v
            break

    return {
        **state,
        "report": report_text,
        "verdict": verdict,
    }


# ---------------------------------------------------------------------------
# Conditional edge: should we deep-dive?
# ---------------------------------------------------------------------------

def _should_deep_dive(state: JudgeState) -> Literal["deep_dive", "write_report"]:
    """Route to deep_dive only if LLM requested tools."""
    if state.get("tool_calls"):
        return "deep_dive"
    return "write_report"


# ---------------------------------------------------------------------------
# Graph
# ---------------------------------------------------------------------------

def _build_graph() -> StateGraph:
    graph = StateGraph(JudgeState)

    graph.add_node("read_results", _read_results)
    graph.add_node("judge", _judge)
    graph.add_node("deep_dive", _deep_dive)
    graph.add_node("write_report", _write_report)

    graph.set_entry_point("read_results")
    graph.add_edge("read_results", "judge")
    graph.add_conditional_edges(
        "judge",
        _should_deep_dive,
        {
            "deep_dive": "deep_dive",
            "write_report": "write_report",
        },
    )
    graph.add_edge("deep_dive", "write_report")
    graph.add_edge("write_report", END)

    return graph.compile()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def run_judge(verification_json_path: str) -> dict:
    """Run the LLM judge agent on a verification.json file.

    Args:
        verification_json_path: Absolute path to verification.json.

    Returns:
        Dict with keys: verdict, report, tool_calls, deep_dive_results.
    """
    with open(verification_json_path, "r", encoding="utf-8") as f:
        verification = json.load(f)

    graph = _build_graph()

    initial_state: JudgeState = {
        "verification": verification,
        "findings": "",
        "tool_calls": [],
        "deep_dive_results": [],
        "verdict": "",
        "report": "",
        "messages": [],
    }

    final_state = graph.invoke(initial_state)

    return {
        "verdict": final_state["verdict"],
        "report": final_state["report"],
        "tool_calls": final_state["tool_calls"],
        "deep_dive_results": final_state["deep_dive_results"],
    }


def save_judge_report(judge_result: dict, output_dir: str) -> str:
    """Save judge report as markdown file.

    Args:
        judge_result: Output of run_judge().
        output_dir: Directory to write judge_report.md.

    Returns:
        Path to saved report.
    """
    os.makedirs(output_dir, exist_ok=True)
    report_path = os.path.join(output_dir, "judge_report.md")

    with open(report_path, "w", encoding="utf-8") as f:
        f.write(judge_result["report"])
        f.write("\n\n---\n")
        f.write(f"*Verdict: {judge_result['verdict']}*\n")
        if judge_result["tool_calls"]:
            f.write(f"*Tools called: {len(judge_result['tool_calls'])}*\n")
        if judge_result["deep_dive_results"]:
            f.write(f"*Deep-dive results: {len(judge_result['deep_dive_results'])}*\n")

    return report_path
