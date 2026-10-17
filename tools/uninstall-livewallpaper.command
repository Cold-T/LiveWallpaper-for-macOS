#!/bin/bash
# Livewallpaper for macOS uninstaller. No Python, Wine or developer tools needed.
set -euo pipefail
mode=ask
case "${1:-}" in
  --dry-run) mode=dry ;;
  --yes) mode=yes ;;
  --help|-h) printf '%s\n' 'Usage: bash uninstall-livewallpaper.command [--dry-run|--yes]' 'Default: preview and ask; --dry-run: inspect only; --yes: skip confirmation.'; exit 0 ;;
  '') ;;
  *) echo 'Unknown argument. Use --help.' >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo 'Too many arguments.' >&2; exit 2; }
[[ $(uname -s) == Darwin ]] || { echo 'macOS only.' >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo 'Run as your normal user, without sudo.' >&2; exit 1; }
[[ -n "$HOME" && "$HOME" != / ]] || exit 1
support="$HOME/Library/Application Support/LiveWallpaper-Wine"
paths=()
for app in '/Applications/Livewallpaper for macOS.app' '/Applications/LiveWallpaper.app' "$HOME/Applications/Livewallpaper for macOS.app" "$HOME/Applications/LiveWallpaper.app"; do
  [[ -d "$app" && ! -L "$app" ]] || continue
  identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)
  case "$identifier" in
    uk.coldt.LiveWallpaper|uk.coldt.LiveWallpaper.WinePreview|com.thusvill.LiveWallpaper) paths+=("$app") ;;
    *) printf 'Skipping unrecognized app: %s\n' "$app" ;;
  esac
done
paths+=("$support")
for name in 'LiveWallpaper' 'LiveWallpaper Personal' 'LiveWallpaper Wine'; do
  paths+=("$HOME/Library/Caches/$name")
done
for name in LiveWallpaper.yaml LiveWallpaper-Wine.yaml; do
  paths+=("$HOME/Library/Preferences/$name")
done
domains=(uk.coldt.LiveWallpaper uk.coldt.LiveWallpaper.WinePreview com.thusvill.LiveWallpaper uk.coldt.LiveWallpaper.SetupQA202 uk.coldt.LiveWallpaper.SetupQA203)
for domain in "${domains[@]}"; do
  paths+=("$HOME/Library/Preferences/$domain.plist" "$HOME/Library/Caches/$domain" "$HOME/Library/Saved Application State/$domain.savedState" "$HOME/Library/HTTPStorages/$domain" "$HOME/Library/WebKit/$domain")
done
printf '%s\n' 'Livewallpaper for macOS — uninstall / 卸载' 'The following existing items will move to Trash; app preferences will reset:'
count=0
for path in "${paths[@]}"; do
  if [[ -e "$path" || -L "$path" ]]; then printf '  %s\n' "$path"; count=$((count+1)); fi
done
printf '%s\n' 'Includes managed Wine, DXMT, media libraries, private prefixes and imported engine copies.' 'Preserves original engine files, all wallpaper folders/SteamWorkshop, project files,' 'and shared SteamCMD, Python, Rosetta or other Wine installations.'
[[ "$mode" != dry ]] || { printf 'Dry run: %s existing paths; no changes.\n' "$count"; exit 0; }
# Do not kill arbitrary Wine instances. Quit the app normally before uninstalling.
processes=$(/bin/ps -axo comm=)
if printf '%s\n' "$processes" | /usr/bin/grep -E '/(LiveWallpaper|wallpaperdaemon)$|/LiveWallpaper-Wine/.*(wine|wineserver)$' >/dev/null; then
  echo 'Quit Livewallpaper from its menu bar first, then run this script again.' >&2
  exit 1
fi
if [[ "$mode" == ask ]]; then
  printf 'Continue? / 继续卸载？ [y/N] '
  read -r answer
  [[ "$answer" == y || "$answer" == Y ]] || { echo 'Cancelled.'; exit 0; }
fi
trash="$HOME/.Trash/Livewallpaper-uninstall-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$trash"
failed=0
index=0
for path in "${paths[@]}"; do
  [[ -e "$path" || -L "$path" ]] || continue
  index=$((index+1))
  if /bin/mv "$path" "$trash/$index-$(basename "$path")"; then
    printf '%s\n' "$path" >> "$trash/original-paths.txt"
  else
    printf 'Could not remove: %s (move it to Trash in Finder).\n' "$path" >&2
    failed=1
  fi
done
for domain in "${domains[@]}"; do /usr/bin/defaults delete "$domain" >/dev/null 2>&1 || true; done
printf 'Removed items are in: %s\n' "$trash"
printf '%s\n' 'Wallpapers remain in their original folders. Empty Trash when ready to reclaim disk space.'
if [[ $failed == 1 ]]; then echo 'Some items remain; see errors above.' >&2; exit 1; fi
echo 'Uninstall complete. The next installation will start the setup wizard.'
