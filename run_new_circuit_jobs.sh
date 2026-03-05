#!/bin/sh

# Run predefined circuit build commands sequentially in background with per-step logs.
# Steps:
# 1) ./start_new_circuit.sh 6-3-3-125
# 2) ./start_new_circuit_step2.sh 6-3-3-125
# 3) ./start_new_circuit.sh 9-4-3-125
# 4) ./start_new_circuit_step2.sh 9-4-3-125

set -eu

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
LOG_ROOT="$ROOT_DIR/logs/new_circuit_jobs"

timestamp() {
  date '+%Y-%m-%d %H:%M:%S'
}

usage() {
  cat <<EOF
Usage:
  $0 start
  $0 status [run_id]
  $0 logs [run_id]

Notes:
  - "start" launches a detached background worker.
  - "status" shows current status (defaults to latest run).
  - "logs" prints log paths (defaults to latest run).
EOF
}

ensure_run_dir() {
  run_id="$1"
  run_dir="$LOG_ROOT/$run_id"
  if [ ! -d "$run_dir" ]; then
    echo "Run not found: $run_id" >&2
    exit 1
  fi
}

latest_run_id() {
  if [ -L "$LOG_ROOT/latest" ]; then
    basename "$(readlink "$LOG_ROOT/latest")"
    return 0
  fi

  latest="$(ls -1 "$LOG_ROOT" 2>/dev/null | grep -v '^latest$' | tail -n 1 || true)"
  if [ -z "$latest" ]; then
    echo "No runs found in $LOG_ROOT" >&2
    exit 1
  fi
  echo "$latest"
}

run_step() {
  run_dir="$1"
  step_name="$2"
  shift 2

  step_log="$run_dir/$step_name.log"
  main_log="$run_dir/main.log"

  echo "[$(timestamp)] START $step_name: $*" >> "$main_log"
  if "$@" >"$step_log" 2>&1; then
    echo "[$(timestamp)] DONE  $step_name (log: $step_log)" >> "$main_log"
    return 0
  fi

  code=$?
  echo "[$(timestamp)] FAIL  $step_name (exit: $code, log: $step_log)" >> "$main_log"
  return "$code"
}

run_worker() {
  run_id="$1"
  run_dir="$LOG_ROOT/$run_id"
  main_log="$run_dir/main.log"
  status_file="$run_dir/status.txt"

  echo "running" > "$status_file"
  echo "[$(timestamp)] Worker started (run_id=$run_id)" >> "$main_log"

  if ! run_step "$run_dir" "01_start_new_circuit_6-3-3-125" "$ROOT_DIR/start_new_circuit.sh" "6-3-3-125"; then
    echo "failed:01_start_new_circuit_6-3-3-125" > "$status_file"
    exit 1
  fi

  if ! run_step "$run_dir" "02_start_new_circuit_step2_6-3-3-125" "$ROOT_DIR/start_new_circuit_step2.sh" "6-3-3-125"; then
    echo "failed:02_start_new_circuit_step2_6-3-3-125" > "$status_file"
    exit 1
  fi

  if ! run_step "$run_dir" "03_start_new_circuit_9-4-3-125" "$ROOT_DIR/start_new_circuit.sh" "9-4-3-125"; then
    echo "failed:03_start_new_circuit_9-4-3-125" > "$status_file"
    exit 1
  fi

  if ! run_step "$run_dir" "04_start_new_circuit_step2_9-4-3-125" "$ROOT_DIR/start_new_circuit_step2.sh" "9-4-3-125"; then
    echo "failed:04_start_new_circuit_step2_9-4-3-125" > "$status_file"
    exit 1
  fi

  echo "completed" > "$status_file"
  echo "[$(timestamp)] All steps completed" >> "$main_log"
}

start_run() {
  mkdir -p "$LOG_ROOT"
  run_id="$(date '+%Y%m%d_%H%M%S')"
  run_dir="$LOG_ROOT/$run_id"

  mkdir -p "$run_dir"
  : > "$run_dir/main.log"
  : > "$run_dir/launcher.log"
  echo "starting" > "$run_dir/status.txt"

  ln -sfn "$run_dir" "$LOG_ROOT/latest"

  nohup "$0" --worker "$run_id" >>"$run_dir/launcher.log" 2>&1 &
  worker_pid="$!"
  echo "$worker_pid" > "$run_dir/pid"

  cat <<EOF
Started background run.
run_id: $run_id
pid: $worker_pid
status: $run_dir/status.txt
main log: $run_dir/main.log
step logs:
  $run_dir/01_start_new_circuit_6-3-3-125.log
  $run_dir/02_start_new_circuit_step2_6-3-3-125.log
  $run_dir/03_start_new_circuit_9-4-3-125.log
  $run_dir/04_start_new_circuit_step2_9-4-3-125.log
EOF
}

show_status() {
  run_id="${1:-$(latest_run_id)}"
  ensure_run_dir "$run_id"
  run_dir="$LOG_ROOT/$run_id"

  echo "run_id: $run_id"
  if [ -f "$run_dir/pid" ]; then
    echo "pid: $(cat "$run_dir/pid")"
  fi
  if [ -f "$run_dir/status.txt" ]; then
    echo "status: $(cat "$run_dir/status.txt")"
  fi
  echo "main log: $run_dir/main.log"
}

show_logs() {
  run_id="${1:-$(latest_run_id)}"
  ensure_run_dir "$run_id"
  run_dir="$LOG_ROOT/$run_id"

  cat <<EOF
main log:
  $run_dir/main.log
launcher log:
  $run_dir/launcher.log
step logs:
  $run_dir/01_start_new_circuit_6-3-3-125.log
  $run_dir/02_start_new_circuit_step2_6-3-3-125.log
  $run_dir/03_start_new_circuit_9-4-3-125.log
  $run_dir/04_start_new_circuit_step2_9-4-3-125.log
EOF
}

if [ "${1:-}" = "--worker" ]; then
  if [ -z "${2:-}" ]; then
    echo "Missing run_id for --worker" >&2
    exit 1
  fi
  run_worker "$2"
  exit 0
fi

cmd="${1:-start}"
case "$cmd" in
  start)
    start_run
    ;;
  status)
    show_status "${2:-}"
    ;;
  logs)
    show_logs "${2:-}"
    ;;
  *)
    usage
    exit 1
    ;;
esac

