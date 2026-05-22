#!/usr/bin/env bash
set -euo pipefail

APP_ID="${STEAM_APP_ID:-431960}"
DEFAULT_ITEM_URL="https://steamcommunity.com/sharedfiles/filedetails/?id=3660962877"
ITEM_INPUT="${1:-$DEFAULT_ITEM_URL}"
DOWNLOAD_DIR="${WALLPAPERENGINE_STEAM_WORKSHOP_DIR:-$HOME/Library/Application Support/WallpaperEngine/SteamWorkshop}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

DOWNLOAD_DIR="${WALLPAPERENGINE_STEAM_WORKSHOP_DIR:-$DOWNLOAD_DIR}"

usage() {
  cat <<'USAGE'
Usage:
  STEAM_USERNAME=<username> tools/download_wallpaper_engine_item.sh [workshop_url_or_item_id]

Environment:
  STEAM_USERNAME                         Steam account name. If omitted, the script tries anonymous login.
  STEAMCMD                               Optional path to steamcmd or steamcmd.sh.
  STEAM_APP_ID                           Defaults to 431960 (Wallpaper Engine).
  WALLPAPERENGINE_STEAM_WORKSHOP_DIR       Download root directory.

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
echo "Workshop item: $ITEM_ID"
echo "Download root: $DOWNLOAD_DIR"
echo

"$STEAMCMD_PATH" \
  +force_install_dir "$DOWNLOAD_DIR" \
  "${LOGIN_ARGS[@]}" \
  +"workshop_download_item $APP_ID $ITEM_ID" \
  +quit

ITEM_DIR="$DOWNLOAD_DIR/steamapps/workshop/content/$APP_ID/$ITEM_ID"
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
