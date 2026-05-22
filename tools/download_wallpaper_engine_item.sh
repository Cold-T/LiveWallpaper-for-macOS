#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Cold-T
set -euo pipefail

APP_ID="${STEAM_APP_ID:-431960}"
DEFAULT_ITEM_URL="https://steamcommunity.com/sharedfiles/filedetails/?id=3660962877"
ITEM_INPUT="${1:-$DEFAULT_ITEM_URL}"
DOWNLOAD_DIR="${LIVEWALLPAPER_STEAM_WORKSHOP_DIR:-$HOME/Library/Application Support/LiveWallpaper/SteamWorkshop}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

DOWNLOAD_DIR="${LIVEWALLPAPER_STEAM_WORKSHOP_DIR:-$DOWNLOAD_DIR}"
CHILD_PIDS=()

remove_child_pid() {
  local removed_pid="$1"
  local remaining=()
  local child_pid

  for child_pid in "${CHILD_PIDS[@]}"; do
    if [[ "$child_pid" != "$removed_pid" ]]; then
      remaining+=("$child_pid")
    fi
  done

  CHILD_PIDS=("${remaining[@]}")
}

cleanup_children() {
  local status=$?
  trap - INT TERM

  if [[ "${#CHILD_PIDS[@]}" -gt 0 ]]; then
    kill "${CHILD_PIDS[@]}" >/dev/null 2>&1 || true
    wait "${CHILD_PIDS[@]}" >/dev/null 2>&1 || true
  fi

  exit "$status"
}

trap cleanup_children INT TERM

usage() {
  cat <<'USAGE'
Usage:
  STEAM_USERNAME=<username> tools/download_wallpaper_engine_item.sh [workshop_url_or_item_id]

The input may be a single Wallpaper Engine Workshop item or a Steam Workshop
collection/list URL. Collections are expanded through Steam's public Web API
and each child item is downloaded.

Environment:
  STEAM_USERNAME                         Steam account name. If omitted, the script tries anonymous login.
  STEAMCMD                               Optional path to steamcmd or steamcmd.sh.
  STEAM_APP_ID                           Defaults to 431960 (Wallpaper Engine).
  LIVEWALLPAPER_STEAM_WORKSHOP_DIR       Download root directory.
  LIVEWALLPAPER_SHOW_DOWNLOAD_PROGRESS   Set to 0 to hide completed/remaining progress lines.
  LIVEWALLPAPER_SKIP_COLLECTION_RESOLVE  Set to 1 when passing a known child item id.

Example:
  STEAM_USERNAME=myname tools/download_wallpaper_engine_item.sh \
    "https://steamcommunity.com/sharedfiles/filedetails/?id=3660962877"
USAGE
}

extract_item_id() {
  local input="$1"
  if [[ "$input" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$input"
    return 0
  fi

  if [[ "$input" =~ [\?\&]id=([0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

resolve_workshop_item_ids() {
  local item_id="$1"
  python3 - "$item_id" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

item_id = sys.argv[1]
url = "https://api.steampowered.com/ISteamRemoteStorage/GetCollectionDetails/v1/"
payload = urllib.parse.urlencode({
    "collectioncount": "1",
    "publishedfileids[0]": item_id,
}).encode("utf-8")
request = urllib.request.Request(
    url,
    data=payload,
    headers={"Content-Type": "application/x-www-form-urlencoded"},
    method="POST",
)

try:
    with urllib.request.urlopen(request, timeout=30) as response:
        body = json.load(response)
except Exception:
    print(item_id)
    raise SystemExit(0)

details = body.get("response", {}).get("collectiondetails", [])
children = details[0].get("children", []) if details else []
ids = [
    str(child.get("publishedfileid"))
    for child in children
    if child.get("publishedfileid")
]

if ids:
    print("\n".join(ids))
else:
    print(item_id)
PY
}

item_has_downloaded_files() {
  local item_id="$1"
  local item_dir="$DOWNLOAD_DIR/steamapps/workshop/content/$APP_ID/$item_id"

  [[ -d "$item_dir" ]] || return 1
  [[ -n "$(find "$item_dir" -type f -print -quit 2>/dev/null)" ]]
}

downloaded_item_count() {
  local completed=0
  local item_id

  for item_id in "${WORKSHOP_ITEM_IDS[@]}"; do
    if item_has_downloaded_files "$item_id"; then
      completed=$((completed + 1))
    fi
  done

  printf '%s\n' "$completed"
}

download_progress_line() {
  local total="${#WORKSHOP_ITEM_IDS[@]}"
  local completed
  local remaining

  completed="$(downloaded_item_count)"
  remaining=$((total - completed))
  if [[ "$remaining" -lt 0 ]]; then
    remaining=0
  fi

  printf 'Download progress: completed=%s remaining=%s total=%s\n' \
    "$completed" "$remaining" "$total"
}

emit_download_progress() {
  download_progress_line
}

monitor_download_progress() {
  local steamcmd_pid="$1"
  local last_progress_line=""
  local current_progress_line=""

  while kill -0 "$steamcmd_pid" >/dev/null 2>&1; do
    current_progress_line="$(download_progress_line)"
    if [[ "$current_progress_line" != "$last_progress_line" ]]; then
      echo "$current_progress_line"
      last_progress_line="$current_progress_line"
    fi
    sleep 1
  done
}

run_steamcmd() {
  "$STEAMCMD_PATH" "${STEAMCMD_ARGS[@]}" &
  local steamcmd_pid=$!
  local monitor_pid=""

  CHILD_PIDS+=("$steamcmd_pid")

  if [[ "${LIVEWALLPAPER_SHOW_DOWNLOAD_PROGRESS:-1}" != "0" ]]; then
    monitor_download_progress "$steamcmd_pid" &
    monitor_pid=$!
    CHILD_PIDS+=("$monitor_pid")
  fi

  local status=0
  wait "$steamcmd_pid" || status=$?
  remove_child_pid "$steamcmd_pid"

  if [[ -n "$monitor_pid" ]]; then
    kill "$monitor_pid" >/dev/null 2>&1 || true
    wait "$monitor_pid" >/dev/null 2>&1 || true
    remove_child_pid "$monitor_pid"
    emit_download_progress
  fi

  return "$status"
}

find_steamcmd() {
  if [[ -n "${STEAMCMD:-}" ]]; then
    printf '%s\n' "$STEAMCMD"
    return 0
  fi

  if command -v steamcmd >/dev/null 2>&1; then
    command -v steamcmd
    return 0
  fi

  local candidates=(
    "$HOME/steamcmd/steamcmd.sh"
    "/opt/homebrew/bin/steamcmd"
    "/usr/local/bin/steamcmd"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ITEM_ID="$(extract_item_id "$ITEM_INPUT")" || {
  echo "Could not parse a Steam Workshop item id from: $ITEM_INPUT" >&2
  exit 2
}

WORKSHOP_ITEM_IDS=()
if [[ "${LIVEWALLPAPER_SKIP_COLLECTION_RESOLVE:-0}" == "1" ]]; then
  WORKSHOP_ITEM_IDS=("$ITEM_ID")
else
  while IFS= read -r item_id; do
    if [[ -n "$item_id" ]]; then
      WORKSHOP_ITEM_IDS+=("$item_id")
    fi
  done < <(resolve_workshop_item_ids "$ITEM_ID")
  if [[ "${#WORKSHOP_ITEM_IDS[@]}" -eq 0 ]]; then
    WORKSHOP_ITEM_IDS=("$ITEM_ID")
  fi
fi

STEAMCMD_PATH="$(find_steamcmd)" || {
  echo "steamcmd was not found." >&2
  echo "Install it first, or set STEAMCMD=/path/to/steamcmd.sh." >&2
  echo "Valve macOS install: https://developer.valvesoftware.com/wiki/SteamCMD#macOS" >&2
  exit 127
}

mkdir -p "$DOWNLOAD_DIR"

LOGIN_ARGS=(+login anonymous)
if [[ -n "${STEAM_USERNAME:-}" ]]; then
  LOGIN_ARGS=(+login "$STEAM_USERNAME")
fi

echo "SteamCMD: $STEAMCMD_PATH"
echo "App ID: $APP_ID"
if [[ "${#WORKSHOP_ITEM_IDS[@]}" -gt 1 || "${WORKSHOP_ITEM_IDS[0]}" != "$ITEM_ID" ]]; then
  echo "Workshop collection: $ITEM_ID"
  echo "Collection items: ${#WORKSHOP_ITEM_IDS[@]}"
else
  echo "Workshop item: ${WORKSHOP_ITEM_IDS[0]}"
fi
echo "Download root: $DOWNLOAD_DIR"
echo

STEAMCMD_ARGS=(
  +force_install_dir "$DOWNLOAD_DIR"
  +@bSiteLicenseAllowCachedClientCredentials 1
  "${LOGIN_ARGS[@]}"
)

for item_id in "${WORKSHOP_ITEM_IDS[@]}"; do
  STEAMCMD_ARGS+=(+"workshop_download_item $APP_ID $item_id")
done
STEAMCMD_ARGS+=(+quit)

run_steamcmd

for item_id in "${WORKSHOP_ITEM_IDS[@]}"; do
  ITEM_DIR="$DOWNLOAD_DIR/steamapps/workshop/content/$APP_ID/$item_id"
  echo
  echo "Expected item directory:"
  echo "$ITEM_DIR"

  if [[ -d "$ITEM_DIR" ]]; then
    echo
    echo "Downloaded files:"
    find "$ITEM_DIR" -maxdepth 2 -type f
  else
    echo
    echo "SteamCMD finished, but the expected item directory was not found yet."
  fi
done
