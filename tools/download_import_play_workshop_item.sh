#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Cold-T
set -euo pipefail

APP_ID="${STEAM_APP_ID:-431960}"
ITEM_INPUT="${1:-https://steamcommunity.com/sharedfiles/filedetails/?id=3256053563}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -f "$REPO_ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
fi

WORKSHOP_DIR="${LIVEWALLPAPER_STEAM_WORKSHOP_DIR:-$HOME/Library/Application Support/LiveWallpaper/SteamWorkshop}"
IMPORT_DIR="${LIVEWALLPAPER_IMPORT_DIR:-$HOME/Library/Application Support/LiveWallpaper/ImportedWallpapers}"
IMPORT_MODE="${LIVEWALLPAPER_IMPORT_MODE:-symlink}"
VOLUME="${LIVEWALLPAPER_VOLUME:-0.0}"
SCALE_MODE="${LIVEWALLPAPER_SCALE_MODE:-0}"

usage() {
  cat <<'USAGE'
Usage:
  tools/download_import_play_workshop_item.sh [workshop_url_or_item_id]

Downloads a Steam Wallpaper Engine Workshop item, finds a directly referenced
.mp4/.mov video, imports it into LiveWallpaper's wallpaper folder, and starts
playback through wallpaperdaemon when a LiveWallpaper.app bundle or daemon path
is available. Scene packages, web wallpapers, application wallpapers, and other
Workshop project types are not supported yet.

Environment:
  STEAM_USERNAME                         Steam account name, usually loaded from .env.
  LIVEWALLPAPER_STEAM_WORKSHOP_DIR       SteamCMD download root.
  LIVEWALLPAPER_IMPORT_DIR               Folder LiveWallpaper should scan.
  LIVEWALLPAPER_IMPORT_MODE              symlink or copy. Defaults to symlink.
  LIVEWALLPAPER_APP                      Path to LiveWallpaper.app.
  LIVEWALLPAPER_DAEMON                   Path to wallpaperdaemon.
  LIVEWALLPAPER_VOLUME                   Playback volume, defaults to 0.0.
  LIVEWALLPAPER_SCALE_MODE               0 fill, 1 fit, 2 stretch, defaults to 0.
  LIVEWALLPAPER_SKIP_PLAY                Set to 1 to import only and let the app UI handle playback.
  LIVEWALLPAPER_SET_STATIC_FRAME         Set to 1 to let the daemon replace the static desktop image.

Example:
  tools/download_import_play_workshop_item.sh \
    "https://steamcommunity.com/sharedfiles/filedetails/?id=3256053563"
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

read_project_field() {
  local project_json="$1"
  local field="$2"
  python3 - "$project_json" "$field" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
value = data.get(sys.argv[2], "")
print(value if isinstance(value, str) else "")
PY
}

find_video_file() {
  local item_dir="$1"
  local project_json="$item_dir/project.json"
  local project_file=""

  if [[ -f "$project_json" ]]; then
    project_file="$(read_project_field "$project_json" file)"
    if [[ -n "$project_file" && -f "$item_dir/$project_file" ]]; then
      local project_file_lower
      project_file_lower="$(printf '%s' "$project_file" | tr '[:upper:]' '[:lower:]')"
      case "$project_file_lower" in
        *.mp4|*.mov)
          printf '%s\n' "$item_dir/$project_file"
          return 0
          ;;
      esac
    fi
  fi

  local found=""
  found="$(find "$item_dir" -maxdepth 3 -type f \( -iname '*.mp4' -o -iname '*.mov' \) -print -quit)"
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi

  return 1
}

find_livewallpaper_app() {
  if [[ -n "${LIVEWALLPAPER_APP:-}" && -d "$LIVEWALLPAPER_APP" ]]; then
    printf '%s\n' "$LIVEWALLPAPER_APP"
    return 0
  fi

  local candidates=(
    "/Applications/LiveWallpaper.app"
    "$REPO_ROOT/build-xcode/Build/Products/Debug/LiveWallpaper.app"
    "$REPO_ROOT/build/Build/Products/Debug/LiveWallpaper.app"
  )

  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/Build/Products/*/LiveWallpaper.app' \
    -type d -print -quit 2>/dev/null || true
}

find_wallpaperdaemon() {
  if [[ -n "${LIVEWALLPAPER_DAEMON:-}" && -x "$LIVEWALLPAPER_DAEMON" ]]; then
    printf '%s\n' "$LIVEWALLPAPER_DAEMON"
    return 0
  fi

  local app
  app="$(find_livewallpaper_app)"
  if [[ -n "$app" && -x "$app/Contents/MacOS/wallpaperdaemon" ]]; then
    printf '%s\n' "$app/Contents/MacOS/wallpaperdaemon"
    return 0
  fi

  return 1
}

make_frame_image() {
  local video="$1"
  local item_dir="$2"
  local frame="$item_dir/livewallpaper-frame.png"

  if command -v ffmpeg >/dev/null 2>&1; then
    ffmpeg -y -loglevel error -ss 1 -i "$video" -frames:v 1 "$frame" || true
  fi

  if [[ -f "$frame" ]]; then
    printf '%s\n' "$frame"
    return 0
  fi

  local preview=""
  preview="$(find "$item_dir" -maxdepth 1 -type f \( -iname 'preview.jpg' -o -iname 'preview.png' -o -iname 'preview.gif' \) -print -quit)"
  if [[ -n "$preview" ]]; then
    printf '%s\n' "$preview"
    return 0
  fi

  printf '%s\n' "$video"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

ITEM_ID="$(extract_item_id "$ITEM_INPUT")" || {
  echo "Could not parse a Steam Workshop item id from: $ITEM_INPUT" >&2
  exit 2
}

"$SCRIPT_DIR/download_wallpaper_engine_item.sh" "$ITEM_INPUT"

ITEM_DIR="$WORKSHOP_DIR/steamapps/workshop/content/$APP_ID/$ITEM_ID"
PROJECT_JSON="$ITEM_DIR/project.json"

if [[ ! -d "$ITEM_DIR" ]]; then
  echo "Downloaded item directory was not found: $ITEM_DIR" >&2
  exit 3
fi

TITLE=""
TYPE=""
if [[ -f "$PROJECT_JSON" ]]; then
  TITLE="$(read_project_field "$PROJECT_JSON" title)"
  TYPE="$(read_project_field "$PROJECT_JSON" type)"
fi

VIDEO_PATH="$(find_video_file "$ITEM_DIR")" || {
  echo "No .mp4/.mov file was found for item $ITEM_ID." >&2
  if [[ -n "$TYPE" ]]; then
    echo "Workshop project type: $TYPE" >&2
  fi
  echo "Current LiveWallpaper playback supports video Workshop items only: .mp4 and .mov." >&2
  echo "scene.pkg, web, application, and other Wallpaper Engine project types are not supported yet." >&2
  exit 4
}

mkdir -p "$IMPORT_DIR"
VIDEO_NAME="$(basename "$VIDEO_PATH")"
IMPORTED_PATH="$IMPORT_DIR/$ITEM_ID-$VIDEO_NAME"

if [[ "$IMPORT_MODE" == "copy" ]]; then
  cp -f "$VIDEO_PATH" "$IMPORTED_PATH"
else
  rm -f "$IMPORTED_PATH"
  ln -s "$VIDEO_PATH" "$IMPORTED_PATH"
fi

defaults write uk.coldt.LiveWallpaper WallpaperFolder "$IMPORT_DIR"
defaults write uk.coldt.LiveWallpaper WallpaperFolder "$IMPORT_DIR"

FRAME_PATH="$ITEM_DIR/.livewallpaper-no-static-frame.png"
if [[ "${LIVEWALLPAPER_SET_STATIC_FRAME:-0}" == "1" ]]; then
  FRAME_PATH="$(make_frame_image "$VIDEO_PATH" "$ITEM_DIR")"
fi

echo
echo "Workshop item: $ITEM_ID"
if [[ -n "$TITLE" ]]; then
  echo "Title: $TITLE"
fi
if [[ -n "$TYPE" ]]; then
  echo "Type: $TYPE"
fi
echo "Video: $VIDEO_PATH"
echo "Imported: $IMPORTED_PATH"
echo "LiveWallpaper folder: $IMPORT_DIR"

if [[ "${LIVEWALLPAPER_SKIP_PLAY:-0}" == "1" ]]; then
  echo "Playback skipped."
  exit 0
fi

if DAEMON_PATH="$(find_wallpaperdaemon)"; then
  echo "Starting wallpaperdaemon: $DAEMON_PATH"
  LABEL="com.livewallpaper.workshop.$ITEM_ID"
  launchctl remove "$LABEL" >/dev/null 2>&1 || true
  launchctl submit -l "$LABEL" -- "$DAEMON_PATH" "$IMPORTED_PATH" "$FRAME_PATH" "$VOLUME" "$SCALE_MODE"
  echo "launchctl label: $LABEL"
else
  echo
  echo "LiveWallpaper daemon was not found."
  echo "The video was imported. Build or install LiveWallpaper.app, then open it and select the imported video."
  exit 5
fi
