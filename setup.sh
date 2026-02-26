#!/usr/bin/env bash
set -euo pipefail
# ---------------------------------------------------------------------------
# Script: setup.sh
#
# Purpose:
#   - Bring up docker-compose (mysql etc.)
#   - (Optionally) seed WSO2 AM databases
#   - Prepare distributed component folders by copying an updated WSO2AM 3.0.0 pack
#   - Run profileSetup.sh for each component and copy MySQL connector jar
#   - Merge per-component repository conf overlays from ./conf/<component>/repository/*
#
# Usage:
#   ./setup.sh [seed|skip] </path/to/updated/wso2am-3.0.0>
#
# Examples:
#   ./setup.sh seed /Users/venukshimendis/Downloads/wso2am-3.0.0
#   ./setup.sh skip /Users/venukshimendis/Downloads/wso2am-3.0.0
#
# Notes:
#   - seed/skip is only for DB seeding
# ---------------------------------------------------------------------------

SEED="${SEED:-skip}"     # seed | skip (this is for the db)

MYSQL_USER="${MYSQL_USER:-wso2carbon}"
MYSQL_PASSWORD="${MYSQL_PASSWORD:-wso2carbon}"
WSO2AM_SHARED_DB="${WSO2AM_SHARED_DB:-WSO2AM_SHARED_DB}"
WSO2AM_DB="${WSO2AM_DB:-WSO2AM_DB}"

MYSQL_JAR_NAME="${MYSQL_JAR_NAME:-mysql-connector-j-8.4.0.jar}"

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
COMPONENTS_DIR="$SCRIPT_DIR/components"
LOG_DIR="$SCRIPT_DIR/logs"

cd "$SCRIPT_DIR"

print_title() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

die() { echo "ERROR: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage:
  $0 [seed|skip] </path/to/updated/wso2am-3.0.0>

Examples:
  $0 seed /Users/venukshimendis/Downloads/wso2am-3.0.0
  $0 skip /Users/venukshimendis/Downloads/wso2am-3.0.0

Env overrides (optional):
  SEED=seed $0 /Users/venukshimendis/Downloads/wso2am-3.0.0

EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
#   - Optional 1st arg: seed|skip
#   - Required arg: UPDATED_PACK_SRC
# ---------------------------------------------------------------------------
if [ $# -ge 1 ]; then
  case "${1:-}" in
    seed|skip)
      SEED="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
  esac
fi

UPDATED_PACK_SRC="${1:-}"

# Validate required inputs and dirs
[ -n "$UPDATED_PACK_SRC" ] || { usage; die "Missing pack path"; }
[ -d "$UPDATED_PACK_SRC" ] || die "Pack folder not found: $UPDATED_PACK_SRC"
[ -d "$COMPONENTS_DIR" ] || die "Components dir not found: $COMPONENTS_DIR"

mkdir -p "$LOG_DIR"

BASE_NAME="$(basename "$UPDATED_PACK_SRC")"
BASE_DST="$COMPONENTS_DIR/$BASE_NAME"

# Component list
COMPONENTS="control_plane traffic_manager gateway"

# Map component name -> WSO2 profile
profile_for() {
  case "$1" in
    control_plane)    echo "control-plane" ;;
    traffic_manager)  echo "traffic-manager" ;;
    gateway)          echo "gateway-worker" ;;
    *) return 1 ;;
  esac
}


# ---------------------------------------------------------------------------
# 1) Delete existing component folders (if any)
# ---------------------------------------------------------------------------
print_title "1) Deleting existing component folders (if any)"

# Remove Finder metadata files (hidden junk) that can keep directories non-empty
find "$COMPONENTS_DIR" -name ".DS_Store" -delete 2>/dev/null || true

for name in $COMPONENTS; do
  target="$COMPONENTS_DIR/$name"
  if [ -d "$target" ]; then
    echo "Deleting: $target"
    rm -rf "$target"
  else
    echo "Not found (skip): $target"
  fi
done

# ---------------------------------------------------------------------------
# 2) Copy updated pack into components dir as a temporary base
# ---------------------------------------------------------------------------
print_title "2) Copying updated pack into components dir"
if [ -d "$BASE_DST" ]; then
  echo "Base pack already exists at destination. Deleting first: $BASE_DST"
  rm -rf "$BASE_DST"
fi
echo "Copying: $UPDATED_PACK_SRC -> $BASE_DST"
cp -a "$UPDATED_PACK_SRC" "$BASE_DST"

# ---------------------------------------------------------------------------
# 3) Create 3 copies (one per component)
# ---------------------------------------------------------------------------
print_title "3) Creating 3 copies and renaming"
for name in $COMPONENTS; do
  dst="$COMPONENTS_DIR/$name"
  echo "Creating: $dst"
  cp -a "$BASE_DST" "$dst"
done

print_title "Cleaning up base copied folder"
rm -rf "$BASE_DST" || true

# ---------------------------------------------------------------------------
# 4) Start docker-compose + wait for MySQL to be ready
# ---------------------------------------------------------------------------
print_title "Starting docker containers"
docker-compose up -d

echo "Waiting for mysql to start..."
docker-compose exec mysql mysqladmin --silent --wait=60 -uroot -proot -h127.0.0.1 ping
if [ $? -ne 0 ]; then
    echo "Error: mysql did not start within the expected time"
    exit $?
fi

sleep 10

# ---------------------------------------------------------------------------
# Optional: seed databases
# ---------------------------------------------------------------------------
if [ "$SEED" = "seed" ]; then
  echo "Seeding $WSO2AM_DB..."
  docker-compose exec -T mysql sh -lc \
    'mysql -u"'"$MYSQL_USER"'" -p"'"$MYSQL_PASSWORD"'" -h127.0.0.1 "'"$WSO2AM_DB"'" < /home/dbScripts/apimgt/mysql.sql' \
    || die "Failed seeding $WSO2AM_DB"
  sleep 10

  echo "Seeding $WSO2AM_SHARED_DB..."
  docker-compose exec -T mysql sh -lc \
    'mysql -u"'"$MYSQL_USER"'" -p"'"$MYSQL_PASSWORD"'" -h127.0.0.1 "'"$WSO2AM_SHARED_DB"'" < /home/dbScripts/mysql.sql' \
    || die "Failed seeding $WSO2AM_SHARED_DB"
  sleep 10


else
  print_title "Skipping DB seeding (SEED=$SEED)"
fi

# ---------------------------------------------------------------------------
# 5) Run profileSetup.sh + copy MySQL connector jar
# ---------------------------------------------------------------------------
print_title "4) Running profileSetup.sh + copying MySQL connector jar for each component"

SRC_JAR="$SCRIPT_DIR/lib/$MYSQL_JAR_NAME"
[ -f "$SRC_JAR" ] || die "MySQL jar not found at: $SRC_JAR"

for name in $COMPONENTS; do
  profile="$(profile_for "$name")" || die "No profile mapping found for: $name"

  comp_home="$COMPONENTS_DIR/$name"
  bin_dir="$comp_home/bin"
  [ -d "$bin_dir" ] || die "bin directory not found for $name: $bin_dir"

  print_title "Component: $name | Profile: $profile"
  echo "Running profile setup..."
  ( cd "$bin_dir" && sh profileSetup.sh "-Dprofile=$profile" )

  dest_dir="$comp_home/repository/components/lib"
  mkdir -p "$dest_dir"

  echo "Copying $MYSQL_JAR_NAME -> $dest_dir/"
  cp -f "$SRC_JAR" "$dest_dir/"
done

# ---------------------------------------------------------------------------
# 6) Merge overlay conf into repository (no deletes)
# ---------------------------------------------------------------------------
print_title "5) Merging ./conf/<component>/repository/* into each component's repository/ (no deletes)"

for name in $COMPONENTS; do
  SRC_CONF_DIR="$SCRIPT_DIR/conf/$name/repository"
  DEST_REPO_DIR="$COMPONENTS_DIR/$name/repository"

  if [ -d "$SRC_CONF_DIR" ]; then
    print_title "Merging conf for: $name"
    echo "From: $SRC_CONF_DIR/"
    echo "To  : $DEST_REPO_DIR/"

    mkdir -p "$DEST_REPO_DIR"

    if ls "$SRC_CONF_DIR" >/dev/null 2>&1; then
      cp -R "$SRC_CONF_DIR/"* "$DEST_REPO_DIR/" 2>/dev/null || true
    fi

    for f in "$SRC_CONF_DIR"/.[!.]* "$SRC_CONF_DIR"/..?*; do
      [ -e "$f" ] || continue
      cp -R "$f" "$DEST_REPO_DIR/" 2>/dev/null || true
    done
  else
    echo "No conf folder for $name (skip): $SRC_CONF_DIR"
  fi
done

print_title "Distributed component folders are ready under:"
echo "  $COMPONENTS_DIR"
