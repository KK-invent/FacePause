#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
case "$MODE" in
  run|--install|--verify|--ui-test|--overlay-test|--sample|--build-only|--logs|--telemetry|--debug) ;;
  *) echo "usage: $0 [--install|--verify|--ui-test|--sample|--build-only|--logs|--telemetry|--debug]" >&2; exit 2 ;;
esac
if pgrep -x FacePause >/dev/null; then
  pkill -TERM -x FacePause || true
  sleep 1
  if pgrep -x FacePause >/dev/null; then
    echo "FacePause 仍在运行，请关闭后重建。" >&2; exit 1
  fi
fi
./script/swift.sh build
APP_BUNDLE="$ROOT_DIR/dist/FacePause.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$(./script/swift.sh build --show-bin-path)/FacePause" "$APP_BUNDLE/Contents/MacOS/FacePause"
cp Support/Info.plist "$APP_BUNDLE/Contents/Info.plist"
cp Support/Assets/AppIcon.icns Support/Assets/Logo.png "$APP_BUNDLE/Contents/Resources/"
./script/sign_app.sh "$APP_BUNDLE"
case "$MODE" in
  --install)
    ./script/install_app.sh
    APP_BUNDLE="/Applications/FacePause.app"
    ;;
  run|--verify|--logs|--telemetry|--debug)
    if [[ -d /Applications/FacePause.app ]]; then
      ./script/install_app.sh
      APP_BUNDLE="/Applications/FacePause.app"
    fi
    ;;
esac
case "$MODE" in
  --build-only) ;;
  --ui-test) open -n "$APP_BUNDLE" --args --ui-test ;;
  --sample) open -n "$APP_BUNDLE" --args --ui-test --sample ;;
  --overlay-test) open -n "$APP_BUNDLE" --args --ui-test --sample --overlay-test ;;
  --verify) open -n "$APP_BUNDLE"; sleep 1; pgrep -x FacePause >/dev/null ;;
  --logs) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'process == "FacePause"' ;;
  --telemetry) open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate 'subsystem == "local.facepause.mac"' ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/FacePause" ;;
  run|--install) open -n "$APP_BUNDLE" ;;
esac
echo "App: $APP_BUNDLE"
