#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# Script: stop.sh
#
# Purpose:
#   Stop all running WSO2 profiles (distributed components) created under ./components
#
# Usage:
#   ./stop.sh
#   ./stop.sh --clean
#
# Behavior:
#   - Default:
#       * Stops WSO2 servers for all components (best-effort)
#   - --clean:
#       * Stops WSO2 servers for all components (best-effort)
#       * Stops docker-compose (mysql etc.)
#       * Removes docker containers/volumes (clean slate)
#
# Notes:
#   - Uses each component's bin/api-manager.sh stop to shutdown gracefully.
#   - If a graceful stop fails, it will try to kill leftover java processes
#     belonging to that component home (based on process command line).
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"

CLEAN="false"
if [ "${1:-}" = "--clean" ]; then
  CLEAN="true"
fi

print_title() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

die() { echo "ERROR: $*" >&2; exit 1; }

# Components we manage
COMPONENTS=("traffic_manager" "control_plane" "gateway")

stop_one() {
  local name="$1"
  local comp_home="$COMPONENTS_DIR/$name"
  local bin_dir="$comp_home/bin"

  if [ ! -d "$comp_home" ]; then
    echo "Not found (skip): $comp_home"
    return 0
  fi

  if [ ! -f "$bin_dir/api-manager.sh" ]; then
    echo "api-manager.sh not found (skip): $bin_dir/api-manager.sh"
    return 0
  fi

  print_title "Stopping: $name"
  (
    cd "$bin_dir"
    # Graceful stop (best effort)
    sh api-manager.sh stop >/dev/null 2>&1 || true
  )

  # Give it a moment
  sleep 3

  # If still running, kill leftover processes tied to this component home
  # (macOS/Linux compatible: ps + grep)
  local pids
  pids="$(ps -ax -o pid= -o command= | grep -F "$comp_home" | grep -v grep | awk '{print $1}' || true)"
  if [ -n "$pids" ]; then
    echo "Found leftover processes for $name. Killing: $pids"
    # Try TERM first, then KILL
    kill $pids 2>/dev/null || true
    sleep 2
    kill -9 $pids 2>/dev/null || true
  else
    echo "No leftover processes for $name"
  fi
}

main() {
  [ -d "$COMPONENTS_DIR" ] || die "components dir not found: $COMPONENTS_DIR"

  print_title "Stopping all WSO2 components"
  for name in "${COMPONENTS[@]}"; do
    stop_one "$name"
  done

  if [ "$CLEAN" = "true" ]; then
    print_title "Cleaning docker-compose (down -v)"
    ( cd "$SCRIPT_DIR" && docker-compose down -v || true )
    print_title "DONE (--clean)"
  else
    print_title "DONE (stop only)"
    echo "Tip: run './stop.sh --clean' to also stop & remove docker containers/volumes"
  fi
}

main "$@"
