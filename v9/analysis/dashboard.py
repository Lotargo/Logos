"""
Dashboard — Phase 4: Plotly interactive HTML dashboard for verification results.

Produces a single-file HTML dashboard at verification_report/dashboard.html
with a 2x3 grid of interactive plots + summary stats table.

All functions accept plain dicts/DataFrames — no DB connection needed.
"""
import os
import json
from typing import List, Dict, Any, Optional

import numpy as np

try:
    import plotly.graph_objects as go
    from plotly.subplots import make_subplots
    HAS_PLOTLY = True
except ImportError:
    HAS_PLOTLY = False

OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "..", "verification_report")


def build_fitness_trace(
    generations: List[int],
    fitness_values: List[float],
    ci_lower: Optional[List[float]] = None,
    ci_upper: Optional[List[float]] = None,
    title: str = "Fitness Evolution",
) -> "go.Figure":
    """Line plot of fitness over generations with optional 95% CI band."""
    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=generations, y=fitness_values,
        mode="lines+markers",
        name="Fitness",
        line=dict(color="#1f77b4", width=2),
        marker=dict(size=4),
    ))
    if ci_lower and ci_upper:
        fig.add_trace(go.Scatter(
            x=generations + generations[::-1],
            y=ci_upper + ci_lower[::-1],
            fill="toself",
            fillcolor="rgba(31,119,180,0.15)",
            line=dict(width=0),
            name="95% CI",
            showlegend=True,
        ))
    fig.update_layout(
        title=title,
        xaxis_title="Generation",
        yaxis_title="Fitness",
        template="plotly_white",
        height=400,
        margin=dict(l=50, r=30, t=50, b=40),
    )
    return fig


def build_diversity_trace(
    generations: List[int],
    edit_distances: List[float],
    entropies: List[float],
    title: str = "Population Diversity",
) -> "go.Figure":
    """Dual-axis line plot: edit distance (left) + Shannon entropy (right)."""
    fig = make_subplots(specs=[[{"secondary_y": True}]])
    fig.add_trace(go.Scatter(
        x=generations, y=edit_distances,
        mode="lines+markers",
        name="Edit Distance",
        line=dict(color="#ff7f0e", width=2),
        marker=dict(size=4),
    ), secondary_y=False)
    fig.add_trace(go.Scatter(
        x=generations, y=entropies,
        mode="lines+markers",
        name="Shannon Entropy",
        line=dict(color="#2ca02c", width=2, dash="dash"),
        marker=dict(size=4),
    ), secondary_y=True)
    fig.update_yaxes(title_text="Avg Pairwise Edit Distance", secondary_y=False)
    fig.update_yaxes(title_text="Shannon Entropy", secondary_y=True)
    fig.update_layout(
        title=title,
        xaxis_title="Generation",
        template="plotly_white",
        height=400,
        margin=dict(l=50, r=60, t=50, b=40),
    )
    return fig


def build_pareto_plot(
    records: List[Dict[str, Any]],
    title: str = "Pareto Frontier: Complexity vs Accuracy",
) -> "go.Figure":
    """Scatter of AST candidates, colored by Pareto status. Hover shows ast_expr."""
    complexities = [r.get("complexity", len(r.get("ast_expr", ""))) for r in records]
    mse_vals = [r.get("mse", 0) for r in records]
    r2_vals = [r.get("r2", 0) for r in records]
    ast_exprs = [r.get("ast_expr", "?") for r in records]
    is_pareto = [r.get("is_pareto", False) for r in records]

    colors = ["#2ca02c" if p else "#d62728" for p in is_pareto]
    symbols = ["diamond" if p else "circle" for p in is_pareto]

    fig = go.Figure()
    fig.add_trace(go.Scatter(
        x=complexities, y=mse_vals,
        mode="markers",
        text=ast_exprs,
        customdata=list(zip(r2_vals, is_pareto)),
        hovertemplate=(
            "<b>%{text}</b><br>"
            "Complexity: %{x}<br>"
            "MSE: %{y:.6f}<br>"
            "R2: %{customdata[0]:.6f}<br>"
            "Pareto: %{customdata[1]}"
            "<extra></extra>"
        ),
        marker=dict(color=colors, size=10, symbol=symbols, line=dict(width=1, color="white")),
        name="Candidates",
    ))
    fig.update_layout(
        title=title,
        xaxis_title="AST Complexity (depth / node count)",
        yaxis_title="MSE",
        template="plotly_white",
        height=400,
        margin=dict(l=50, r=30, t=50, b=40),
    )
    return fig


def build_operator_heatmap(
    operators: List[str],
    domains: List[str],
    usage_matrix: List[List[float]],
    title: str = "Operator Usage by Domain",
) -> "go.Figure":
    """Heatmap of operator success rates across domains."""
    fig = go.Figure(data=go.Heatmap(
        z=usage_matrix,
        x=domains,
        y=operators,
        colorscale="YlOrRd",
        text=[[f"{v:.1%}" for v in row] for row in usage_matrix],
        texttemplate="%{text}",
        hovertemplate="Operator: %{y}<br>Domain: %{x}<br>Rate: %{z:.1%}<extra></extra>",
    ))
    fig.update_layout(
        title=title,
        xaxis_title="Domain",
        yaxis_title="Operator",
        template="plotly_white",
        height=max(300, len(operators) * 30 + 100),
        margin=dict(l=100, r=30, t=50, b=40),
    )
    return fig


def build_stat_table(
    metrics: List[Dict[str, Any]],
    title: str = "Statistical Comparison Results",
) -> "go.Figure":
    """Table of statistical test results with p-values and effect sizes."""
    headers = ["Comparison", "Test", "Statistic", "p-value", "Effect Size", "Significant"]
    cells = [[], [], [], [], [], []]
    for m in metrics:
        cells[0].append(m.get("comparison", "?"))
        cells[1].append(m.get("test_used", "?"))
        cells[2].append(f"{m.get('test_statistic', 0):.4f}")
        p = m.get("p_value", 1.0)
        cells[3].append(f"{p:.4e}" if p < 0.001 else f"{p:.4f}")
        es = m.get("effect_size", 0)
        es_name = m.get("effect_size_name", "")
        cells[4].append(f"{es:.3f} ({es_name})" if es_name else f"{es:.3f}")
        cells[5].append("Yes" if m.get("significant", False) else "No")

    fig = go.Figure(data=[go.Table(
        header=dict(
            values=[f"<b>{h}</b>" for h in headers],
            fill_color="#1f77b4",
            font=dict(color="white", size=12),
            align="left",
        ),
        cells=dict(
            values=cells,
            fill_color=[["#f0f4f8", "white"] * (len(cells[0]) // 2 + 1)],
            font=dict(size=11),
            align="left",
            height=28,
        ),
    )])
    fig.update_layout(
        title=title,
        height=max(300, len(metrics) * 35 + 80),
        margin=dict(l=20, r=20, t=50, b=20),
    )
    return fig


def assemble_dashboard(
    fitness_fig: Optional["go.Figure"] = None,
    diversity_fig: Optional["go.Figure"] = None,
    pareto_fig: Optional["go.Figure"] = None,
    heatmap_fig: Optional["go.Figure"] = None,
    stat_table_fig: Optional["go.Figure"] = None,
    output_path: Optional[str] = None,
    title: str = "Logos V9 Verification Dashboard",
) -> str:
    """Assemble all figures into a single HTML file (2x3 grid)."""
    if not HAS_PLOTLY:
        raise ImportError("plotly is required: pip install plotly")

    figs = [
        ("fitness", fitness_fig),
        ("diversity", diversity_fig),
        ("pareto", pareto_fig),
        ("heatmap", heatmap_fig),
        ("stats", stat_table_fig),
    ]

    if output_path is None:
        output_path = os.path.join(OUTPUT_DIR, "dashboard.html")
    os.makedirs(os.path.dirname(output_path), exist_ok=True)

    plotly_js_cdn = '<script src="https://cdn.plot.ly/plotly-2.35.0.min.js"></script>'

    html_parts = [
        "<!DOCTYPE html>",
        "<html lang='en'>",
        "<head>",
        "<meta charset='UTF-8'>",
        f"<title>{title}</title>",
        plotly_js_cdn,
        "<style>",
        "body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; margin: 0; padding: 20px; background: #fafafa; }",
        "h1 { text-align: center; color: #1a1a2e; margin-bottom: 8px; }",
        ".subtitle { text-align: center; color: #666; font-size: 14px; margin-bottom: 24px; }",
        ".grid { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; max-width: 1400px; margin: 0 auto; }",
        ".card { background: white; border-radius: 8px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); padding: 8px; }",
        ".full-width { grid-column: 1 / -1; }",
        "@media (max-width: 800px) { .grid { grid-template-columns: 1fr; } }",
        "</style>",
        "</head>",
        "<body>",
        f"<h1>{title}</h1>",
        "<div class='subtitle'>Generated by Logos V9 Verification Suite</div>",
        "<div class='grid'>",
    ]

    active_figs = [(n, f) for n, f in figs if f is not None]
    n_active = len(active_figs)

    for i, (name, fig) in enumerate(active_figs):
        div_html = fig.to_html(full_html=False, include_plotlyjs=False, div_id=f"div-{name}")
        is_last = (i == n_active - 1)
        is_odd_last = (n_active % 2 == 1) and is_last
        cls = "card full-width" if is_odd_last else "card"
        html_parts.append(f"<div class='{cls}'>{div_html}</div>")

    html_parts.extend([
        "</div>",
        "</body>",
        "</html>",
    ])

    html_content = "\n".join(html_parts)

    with open(output_path, "w", encoding="utf-8") as f:
        f.write(html_content)

    return output_path
