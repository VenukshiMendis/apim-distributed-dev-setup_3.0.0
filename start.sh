#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# Script: start.sh
#
# Starts WSO2 AM 3.0.0 distributed components sequentially in this order:
#   1) api-key-manager
#   2) traffic-manager
#   3) api-publisher
#   4) api-devportal
#   5) gateway-worker
#
# Wait logic:
#   - Probes https://localhost:<port>/carbon/ until it responds
#   - Does NOT print curl errors
#   - Prints: "Waiting for <service> to start... (<counter>/<max_retries>)"
#
# Logs:
#   - Redirects each component output to ./logs/<component>.log
#   - DOES NOT append (overwrites each run)
#
# PIDs:
#   - Does NOT write PID files
#   - Prints PID to terminal
#
# Usage:
#   ./start.sh
#
# Optional env overrides:
#   START_TIMEOUT=60         # seconds to wait per component (default 60)
#   SLEEP_BETWEEN_CHECKS=2   # seconds between probes
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

START_TIMEOUT="${START_TIMEOUT:-60}"
SLEEP_BETWEEN_CHECKS="${SLEEP_BETWEEN_CHECKS:-2}"

print_title() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Start order you requested
COMPONENTS=("key_manager" "traffic_manager" "publisher" "devportal" "gateway")

profile_for() {
  case "$1" in
    key_manager)      echo "api-key-manager" ;;
    traffic_manager)  echo "traffic-manager" ;;
    publisher)        echo "api-publisher" ;;
    devportal)        echo "api-devportal" ;;
    gateway)          echo "gateway-worker" ;;
    *) return 1 ;;
  esac
}

# HTTPS ports from your offsets table
https_port_for() {
  case "$1" in
    traffic_manager)  echo "9443" ;;
    key_manager)      echo "9444" ;;
    publisher)        echo "9445" ;;
    gateway)          echo "9446" ;;
    devportal)        echo "9447" ;;
    *) return 1 ;;
  esac
}

# Probe "up" via HTTPS /carbon/
# Prints meaningful retry counter line (no curl spam).
wait_for_up() {
  local service_name="$1"
  local port="$2"
  local timeout="$3"

  local max_retries counter
  max_retries=$((timeout / SLEEP_BETWEEN_CHECKS))
  if [ "$max_retries" -lt 1 ]; then max_retries=1; fi

  counter=0
  while true; do
    if curl -k -sS -o /dev/null "https://localhost:${port}/carbon/" 2>/dev/null; then
      echo "UP: ${service_name} is responding on port ${port}"
      return 0
    fi

    counter=$((counter + 1))
    echo "Waiting for ${service_name} to start... (${counter}/${max_retries})"

    if [ "$counter" -ge "$max_retries" ]; then
      return 1
    fi

    sleep "$SLEEP_BETWEEN_CHECKS"
  done
}

start_component() {
  local name="$1"
  local profile port comp_home log_file pid

  profile="$(profile_for "$name")" || die "No profile mapping for: $name"
  port="$(https_port_for "$name")" || die "No HTTPS port mapping for: $name"

  comp_home="$COMPONENTS_DIR/$name"
  [ -d "$comp_home" ] || die "Component folder not found: $comp_home"
  [ -f "$comp_home/bin/wso2server.sh" ] || die "wso2server.sh not found: $comp_home/bin/wso2server.sh"

  log_file="$LOG_DIR/${name}.log"

  print_title "Starting ${name} -> sh wso2server.sh -Dprofile=${profile} (HTTPS=${port})"
  echo "Home : $comp_home"
  echo "Log  : $log_file (overwrite)"

  # Overwrite the log at each run (no append)
  : > "$log_file"

  (
    cd "$comp_home/bin"
    # Redirect output to log (overwrite is handled above). nohup keeps it running if terminal closes.
    nohup sh wso2server.sh "-Dprofile=${profile}" </dev/null >>"$log_file" 2>&1 &
    echo $!  # print PID to subshell stdout
  ) | {
    read -r pid
    [ -n "$pid" ] || die "Failed to capture PID for $name"
    echo "PID  : $pid"

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "---- last 200 lines of log: $log_file ----"
      tail -n 200 "$log_file" || true
      die "$name failed to start (process exited immediately)."
    fi

    if ! wait_for_up "$name" "$port" "$START_TIMEOUT"; then
      echo "---- timeout waiting for $name. last 200 lines of log: $log_file ----"
      tail -n 200 "$log_file" || true
      die "Timed out waiting for $name to start on port $port"
    fi

    echo "Started OK: $name (pid=$pid)"
  }
}

main() {
  [ -d "$COMPONENTS_DIR" ] || die "components dir not found: $COMPONENTS_DIR"

  print_title "Sequential start (your requested order)"
  echo "  1) api-key-manager   (9444)"
  echo "  2) traffic-manager   (9443)"
  echo "  3) api-publisher     (9445)"
  echo "  4) api-devportal     (9447)"
  echo "  5) gateway-worker    (9446)"
  echo
  echo "Timeout per component: ${START_TIMEOUT}s"
  echo "Probe interval        : ${SLEEP_BETWEEN_CHECKS}s"
  echo "Logs dir              : ${LOG_DIR}"
  echo

  for name in "${COMPONENTS[@]}"; do
    start_component "$name"
  done

  print_title "ALL components started"
  echo "Logs: $LOG_DIR"
}

main "$@"
