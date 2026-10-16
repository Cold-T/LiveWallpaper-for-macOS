#!/bin/zsh
set -eu
project_root="$(cd "$(dirname "$0")/.." && pwd)"
export LIVEWALLPAPER_WINE_RUNTIME="${LIVEWALLPAPER_WINE_RUNTIME:-$project_root/build/runtime11}"
export LIVEWALLPAPER_LIBRARY="${LIVEWALLPAPER_LIBRARY:-$project_root/build/library}"
export LIVEWALLPAPER_WINE_STATE="${LIVEWALLPAPER_WINE_STATE:-$project_root/build/state11}"
exec "$project_root/build/preview/Livewallpaper for macOS.app/Contents/MacOS/LiveWallpaper"
