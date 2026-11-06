#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
mkdir -p .build/validation
xcrun swiftc -swift-version 5 -parse-as-library -emit-object -whole-module-optimization -emit-module -module-name FaceCore \
  Sources/FaceCore/*.swift -emit-module-path .build/validation/FaceCore.swiftmodule -o .build/validation/FaceCore.o
xcrun swiftc -swift-version 5 -parse-as-library -D FACEPAUSE_STANDALONE_TEST -I .build/validation \
  .build/validation/FaceCore.o Tests/FaceCoreTests/*.swift Support/TestMain.swift -o .build/validation/tests
.build/validation/tests
