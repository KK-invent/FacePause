#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_APP="$ROOT_DIR/dist/FacePause.app"
DESTINATION_APP="/Applications/FacePause.app"
codesign --verify --strict "$SOURCE_APP"
if [[ ! -w /Applications ]]; then
  echo "无法写入 /Applications，尚未安装。" >&2; exit 1
fi
STAGED_APP="/Applications/.FacePause-install-$$.app"
ditto "$SOURCE_APP" "$STAGED_APP"
codesign --verify --strict "$STAGED_APP"
if [[ -e "$DESTINATION_APP" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DESTINATION_APP/Contents/Info.plist")"
  if [[ "$EXISTING_ID" != local.facepause.mac ]]; then
    echo "同名位置已有其他应用，已停止，未覆盖。" >&2; exit 1
  fi
  BACKUP_DIR="$ROOT_DIR/work/app-update-backups/$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -p "$BACKUP_DIR"
  mv "$DESTINATION_APP" "$BACKUP_DIR/FacePause.app"
fi
mv "$STAGED_APP" "$DESTINATION_APP"
codesign --verify --strict "$DESTINATION_APP"
echo "Installed: $DESTINATION_APP"
