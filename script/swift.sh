#!/usr/bin/env bash
# Some upgraded CLT installations retain a 2024 private PackageDescription
# interface beside the current public interface/library. Isolate the manifest
# runtime in this project instead of editing or deleting system files.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
SWIFT_BIN="$(xcrun --find swift)"
PM_LIB="$(dirname "$SWIFT_BIN")/../lib/swift/pm"
PUBLIC_INTERFACE="$PM_LIB/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.swiftinterface"
PRIVATE_INTERFACE="$PM_LIB/ManifestAPI/PackageDescription.swiftmodule/arm64-apple-macos.private.swiftinterface"
if [[ -f "$PRIVATE_INTERFACE" ]] && /usr/bin/grep -q swiftLanguageModes "$PUBLIC_INTERFACE" && ! /usr/bin/grep -q swiftLanguageModes "$PRIVATE_INTERFACE"; then
  RUNTIME_DIR="$ROOT_DIR/.build/swiftpm-runtime"
  mkdir -p "$RUNTIME_DIR/ManifestAPI/PackageDescription.swiftmodule"
  SOURCE_LIBRARY="$PM_LIB/ManifestAPI/libPackageDescription.dylib"
  cmp -s "$SOURCE_LIBRARY" "$RUNTIME_DIR/ManifestAPI/libPackageDescription.dylib" || cp "$SOURCE_LIBRARY" "$RUNTIME_DIR/ManifestAPI/"
  for SOURCE_INTERFACE in "$PM_LIB"/ManifestAPI/PackageDescription.swiftmodule/*-apple-macos.swiftinterface; do
    DEST_INTERFACE="$RUNTIME_DIR/ManifestAPI/PackageDescription.swiftmodule/$(basename "$SOURCE_INTERFACE")"
    cmp -s "$SOURCE_INTERFACE" "$DEST_INTERFACE" || cp "$SOURCE_INTERFACE" "$DEST_INTERFACE"
  done
  export SWIFTPM_CUSTOM_LIBS_DIR="$RUNTIME_DIR"
fi
exec "$SWIFT_BIN" "$@"
