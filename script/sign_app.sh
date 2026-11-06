#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 1 ]]; then echo "usage: $0 /path/to/FacePause.app" >&2; exit 2; fi
SIGN_METADATA="$HOME/Library/Application Support/FacePause/Signing/identity.json"
if [[ ! -f "$SIGN_METADATA" ]]; then
  echo "缺少固定签名身份。请先运行 script/setup_local_signing.py；不会退回临时签名。" >&2
  exit 1
fi
SIGN_FINGERPRINT="$(python3 - "$SIGN_METADATA" <<'PY'
import json,re,sys
value=json.load(open(sys.argv[1]))['sha1']
if not re.fullmatch(r'[A-Fa-f0-9]{40}',value): raise SystemExit('Invalid signing fingerprint')
print(value)
PY
)"
SIGN_REQUIREMENT="designated => identifier \"local.facepause.mac\" and certificate leaf = H\"$SIGN_FINGERPRINT\""
codesign --force --sign "$SIGN_FINGERPRINT" --identifier local.facepause.mac --timestamp=none --requirements "=$SIGN_REQUIREMENT" "$1"
codesign --verify --strict --test-requirement "=identifier \"local.facepause.mac\" and certificate leaf = H\"$SIGN_FINGERPRINT\"" "$1"
