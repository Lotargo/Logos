#!/bin/bash

EXPERIMENTS_DIR="/app/v9/experiments"
LOGS_DIR="/app/v9/experiments/logs"
RESULTS_DIR="/tmp/experiment_results"
mkdir -p "$LOGS_DIR" "$RESULTS_DIR"
rm -f "$RESULTS_DIR"/*

declare -A EXPERIMENTS
EXPERIMENTS["run_cold_fusion.lisp"]=90
EXPERIMENTS["run_millennium_poincare.lisp"]=90
EXPERIMENTS["experiment_nspl_gan.lisp"]=180
EXPERIMENTS["experiment_nspl_coop.lisp"]=180
EXPERIMENTS["experiment_nspl_cross_domain.lisp"]=180
EXPERIMENTS["run_adversarial_lenr.lisp"]=90
EXPERIMENTS["run_adversarial_singularity.lisp"]=180
EXPERIMENTS["run_healing_lenr.lisp"]=90
EXPERIMENTS["run_hslg_experiment.lisp"]=180
EXPERIMENTS["run_hslg_part2_experiment.lisp"]=180
EXPERIMENTS["run_warp_drive.lisp"]=180
EXPERIMENTS["run_new_experiments.lisp"]=180
EXPERIMENTS["run_experiments.lisp"]=180
EXPERIMENTS["grand_experiment.lisp"]=300

echo "========================================"
echo " Running all v9 experiments in parallel..."
echo "========================================"
echo ""

for file in "${!EXPERIMENTS[@]}"; do
  timeout_sec="${EXPERIMENTS[$file]}"
  name="${file%.lisp}"
  logfile="$LOGS_DIR/${name}.log"

  echo "[$(date +%H:%M:%S)] Launching: $file (timeout: ${timeout_sec}s)"
  ( timeout "$timeout_sec" sbcl --script "$EXPERIMENTS_DIR/$file" > "$logfile" 2>&1; echo "$?:$file" > "$RESULTS_DIR/${name}.result" ) &
done

echo ""
echo "Waiting for all experiments to finish..."
wait
echo ""

echo "========================================"
echo " Results:"
echo "========================================"
for file in "${!EXPERIMENTS[@]}"; do
  name="${file%.lisp}"
  logfile="$LOGS_DIR/${name}.log"
  result_file="$RESULTS_DIR/${name}.result"
  if [ -f "$result_file" ]; then
    code=$(cat "$result_file" | cut -d: -f1)
    if [ "$code" = "124" ]; then
      echo "  $file -> TIMED OUT (${EXPERIMENTS[$file]}s)"
    elif [ "$code" != "0" ]; then
      echo "  $file -> CRASHED (exit $code)"
    else
      # Check for obvious errors in log
      if grep -qi "unhandled\|fatal error\|CANCELED\|sb-impl::run-program\|broken pipe" "$logfile" 2>/dev/null; then
        echo "  $file -> COMPLETED (with errors in log)"
      else
        echo "  $file -> COMPLETED OK"
      fi
    fi
  else
    echo "  $file -> UNKNOWN (no result file)"
  fi
done

echo ""
echo "========================================"
echo " Logs: $LOGS_DIR"
echo "========================================"
