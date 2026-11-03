#!/bin/bash
# Isolated native pointer regression; no account, live library or credentials.
set -euo pipefail
cd "$(dirname "$0")/.."
if test "${1:-}" != --no-build; then bash scripts/build.sh; fi
qa_dir=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-pointer-test.XXXXXX")
chmod 700 "$qa_dir"
trap 'rm -rf "$qa_dir"' EXIT
qa_app="$qa_dir/MakerGlance Pointer QA.app"
ditto dist/MakerGlance.app "$qa_app"
qa_id="com.t0nyz0.MakerPulse.PointerQA.$(uuidgen)"
plutil -replace CFBundleIdentifier -string "$qa_id" "$qa_app/Contents/Info.plist"
codesign --force --sign - --identifier "$qa_id" "$qa_app"
open -n "$qa_app" --args --qa-library "$qa_dir/library" --dashboard-pointer-audit "$qa_dir/report" --matrix
for ((attempt=0; attempt<240; attempt++)); do
 if test -f "$qa_dir/report/error.txt"; then cat "$qa_dir/report/error.txt" >&2; exit 1; fi
 if test -f "$qa_dir/report/pointer-matrix.json"; then
  python3 - "$qa_dir/report/pointer-matrix.json" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]));assert len(result)==9 and all(result.values()),result
print(json.dumps(result,indent=2))
PY
  exit 0
 fi
 sleep 0.25
done
echo 'Native pointer regression timed out.' >&2
exit 1
