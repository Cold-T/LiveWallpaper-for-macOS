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
CURRENT_CHILD_PID=""

cleanup_child_process() {
  local status=$?
  trap - INT TERM

  if [[ -n "$CURRENT_CHILD_PID" ]]; then
    kill "$CURRENT_CHILD_PID" >/dev/null 2>&1 || true
    wait "$CURRENT_CHILD_PID" >/dev/null 2>&1 || true
  fi

  exit "$status"
}

trap cleanup_child_process INT TERM

usage() {
  cat <<'USAGE'
Usage:
  tools/download_import_play_workshop_item.sh [workshop_url_or_item_id]

Downloads a Steam Wallpaper Engine Workshop item or collection/list URL, finds
directly referenced .mp4/.mov videos, imports them into LiveWallpaper's
wallpaper folder, and starts playback through wallpaperdaemon when a
LiveWallpaper.app bundle or daemon path is available. Scene packages, web
wallpapers, application wallpapers, and other Workshop project types are not
supported yet.

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

import_downloaded_item() {
  local item_id="$1"
  local item_dir="$WORKSHOP_DIR/steamapps/workshop/content/$APP_ID/$item_id"
  local project_json="$item_dir/project.json"

  if [[ ! -d "$item_dir" ]]; then
    echo "Downloaded item directory was not found: $item_dir" >&2
    return 3
  fi

  local title=""
  local type=""
  if [[ -f "$project_json" ]]; then
    title="$(read_project_field "$project_json" title)"
    type="$(read_project_field "$project_json" type)"
  fi

  local video_path=""
  video_path="$(find_video_file "$item_dir")" || {
    echo "No .mp4/.mov file was found for item $item_id." >&2
    if [[ -n "$type" ]]; then
      echo "Workshop project type: $type" >&2
    fi
    echo "Current LiveWallpaper playback supports video Workshop items only: .mp4 and .mov." >&2
    echo "scene.pkg, web, application, and other Wallpaper Engine project types are not supported yet." >&2
    return 4
  }

  mkdir -p "$IMPORT_DIR"
  local video_name
  local imported_path
  video_name="$(basename "$video_path")"
  imported_path="$IMPORT_DIR/$item_id-$video_name"

  if [[ "$IMPORT_MODE" == "copy" ]]; then
    cp -f "$video_path" "$imported_path"
  else
    rm -f "$imported_path"
    ln -s "$video_path" "$imported_path"
  fi

  local frame_path="$item_dir/.livewallpaper-no-static-frame.png"
  if [[ "${LIVEWALLPAPER_SET_STATIC_FRAME:-0}" == "1" ]]; then
    frame_path="$(make_frame_image "$video_path" "$item_dir")"
  fi

  IMPORTED_ITEM_IDS+=("$item_id")
  IMPORTED_PATHS+=("$imported_path")
  IMPORTED_FRAME_PATHS+=("$frame_path")

  echo
  echo "Workshop item: $item_id"
  if [[ -n "$title" ]]; then
    echo "Title: $title"
  fi
  if [[ -n "$type" ]]; then
    echo "Type: $type"
  fi
  echo "Video: $video_path"
  echo "Imported: $imported_path"

  return 0
}

emit_collection_download_progress() {
  local completed="$1"
  local total="$2"
  local remaining=$((total - completed))

  if [[ "$remaining" -lt 0 ]]; then
    remaining=0
  fi

  echo "Download progress: completed=$completed remaining=$remaining total=$total"
}

download_single_item() {
  local item_id="$1"

  env \
    LIVEWALLPAPER_SHOW_DOWNLOAD_PROGRESS=0 \
    LIVEWALLPAPER_SKIP_COLLECTION_RESOLVE=1 \
    "$SCRIPT_DIR/download_wallpaper_engine_item.sh" "$item_id" &
  CURRENT_CHILD_PID=$!

  local status=0
  wait "$CURRENT_CHILD_PID" || status=$?
  CURRENT_CHILD_PID=""

  return "$status"
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
while IFS= read -r item_id; do
  if [[ -n "$item_id" ]]; then
    WORKSHOP_ITEM_IDS+=("$item_id")
  fi
done < <(resolve_workshop_item_ids "$ITEM_ID")

if [[ "${#WORKSHOP_ITEM_IDS[@]}" -eq 0 ]]; then
  WORKSHOP_ITEM_IDS=("$ITEM_ID")
fi

IS_COLLECTION=0
if [[ "${#WORKSHOP_ITEM_IDS[@]}" -gt 1 || "${WORKSHOP_ITEM_IDS[0]}" != "$ITEM_ID" ]]; then
  IS_COLLECTION=1
  echo "Workshop collection: $ITEM_ID"
  echo "Collection items: ${#WORKSHOP_ITEM_IDS[@]}"
fi

IMPORTED_ITEM_IDS=()
IMPORTED_PATHS=()
IMPORTED_FRAME_PATHS=()
FAILED_COUNT=0

if [[ "$IS_COLLECTION" == "1" ]]; then
  DOWNLOADED_COUNT=0
  emit_collection_download_progress "$DOWNLOADED_COUNT" "${#WORKSHOP_ITEM_IDS[@]}"

  for item_id in "${WORKSHOP_ITEM_IDS[@]}"; do
    echo
    echo "Downloading collection item: $item_id"
    download_single_item "$item_id"

    if import_downloaded_item "$item_id"; then
      :
    else
      FAILED_COUNT=$((FAILED_COUNT + 1))
    fi

    DOWNLOADED_COUNT=$((DOWNLOADED_COUNT + 1))
    emit_collection_download_progress "$DOWNLOADED_COUNT" "${#WORKSHOP_ITEM_IDS[@]}"
  done
else
  "$SCRIPT_DIR/download_wallpaper_engine_item.sh" "$ITEM_INPUT" &
  CURRENT_CHILD_PID=$!
  wait "$CURRENT_CHILD_PID"
  CURRENT_CHILD_PID=""

  if import_downloaded_item "$ITEM_ID"; then
    :
  else
    status=$?
    exit "$status"
  fi
fi

defaults write uk.coldt.LiveWallpaper WallpaperFolder "$IMPORT_DIR"
defaults write uk.coldt.LiveWallpaper WallpaperFolder "$IMPORT_DIR"

if [[ "${#IMPORTED_PATHS[@]}" -eq 0 ]]; then
  echo "No .mp4/.mov file was imported." >&2
  exit 4
fi

echo
if [[ "$IS_COLLECTION" == "1" ]]; then
  echo "Imported collection: ${#IMPORTED_PATHS[@]} videos"
  if [[ "$FAILED_COUNT" -gt 0 ]]; then
    echo "Skipped items: $FAILED_COUNT"
  fi
else
  echo "Workshop item imported."
fi
echo "LiveWallpaper folder: $IMPORT_DIR"

if [[ "${LIVEWALLPAPER_SKIP_PLAY:-0}" == "1" ]]; then
  echo "Playback skipped."
  exit 0
fi

if DAEMON_PATH="$(find_wallpaperdaemon)"; then
  echo "Starting wallpaperdaemon: $DAEMON_PATH"
  if [[ "$IS_COLLECTION" == "1" ]]; then
    echo "Starting first imported video from collection."
  fi
  LABEL="com.livewallpaper.workshop.${IMPORTED_ITEM_IDS[0]}"
  if [[ "$IS_COLLECTION" == "1" ]]; then
    LABEL="com.livewallpaper.workshop.$ITEM_ID"
  fi
  launchctl remove "$LABEL" >/dev/null 2>&1 || true
  launchctl submit -l "$LABEL" -- "$DAEMON_PATH" "${IMPORTED_PATHS[0]}" "${IMPORTED_FRAME_PATHS[0]}" "$VOLUME" "$SCALE_MODE"
  echo "launchctl label: $LABEL"
else
  echo
  echo "LiveWallpaper daemon was not found."
  echo "The video was imported. Build or install LiveWallpaper.app, then open it and select the imported video."
  exit 5
fi
