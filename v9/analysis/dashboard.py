"""
Phase 4 — Verification Dashboard
===================================
Plotly interactive HTML dashboard for experiment analysis.
Output: verification_report/dashboard.html (self-contained)

Provides:
  build_fitness_trace          fitness evolution + CI band
  build_diversity_trace        dual-axis: edit distance + entropy
  build_pareto_plot            interactive Pareto scatter
  build_operator_heatmap       operators × domains heatmap
  build_stat_table             metrics summary table
  assemble_dashboard           2×3 grid → HTML export
"""


def build_fitness_trace(fitness_history):
    """Plotly scatter+line: iteration vs fitness_score + rolling mean + 95% CI."""
    raise NotImplementedError("Phase 4 — TODO")


def build_diversity_trace(snapshots):
    """Dual-axis Plotly: mean edit distance + operator entropy over iterations."""
    raise NotImplementedError("Phase 4 — TODO")


def build_pareto_plot(pareto_data):
    """Plotly scatter: complexity vs error, Pareto front highlighted, hover with ast."""
    raise NotImplementedError("Phase 4 — TODO")


def build_operator_heatmap(operator_stats):
    """Plotly imshow: operators × domains, color=success_rate, annotation=usage_count."""
    raise NotImplementedError("Phase 4 — TODO")


def build_stat_table(stat_results):
    """Plotly Table: metric | group_A | group_B | p_value | effect_size | significant."""
    raise NotImplementedError("Phase 4 — TODO")


def assemble_dashboard(traces, output_path):
    """Plotly make_subplots 2×3 → dark theme → self-contained HTML."""
    raise NotImplementedError("Phase 4 — TODO")
