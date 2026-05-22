#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Cold-T
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

STEAM_USERNAME="${1:-${STEAM_USERNAME:-}}"
STEAM_PASSWORD="${2:-${STEAM_PASSWORD:-}}"

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

if [[ -z "$STEAM_USERNAME" ]]; then
  read -r -p "Steam username: " STEAM_USERNAME
fi

if [[ -z "$STEAM_PASSWORD" ]]; then
  read -r -s -p "Steam password: " STEAM_PASSWORD
  printf '\n'
fi

STEAMCMD_PATH="$(find_steamcmd)" || {
  echo "steamcmd was not found." >&2
  echo "Install it first, or set STEAMCMD=/path/to/steamcmd.sh." >&2
  echo "Valve macOS install: https://developer.valvesoftware.com/wiki/SteamCMD#macOS" >&2
  exit 127
}

echo "SteamCMD: $STEAMCMD_PATH"
echo "Steam username: $STEAM_USERNAME"
echo

"$STEAMCMD_PATH" +login "$STEAM_USERNAME" "$STEAM_PASSWORD" +quit
