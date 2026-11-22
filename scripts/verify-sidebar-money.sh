#!/bin/bash
# Focused offline native checks. Optional second argument retains reports/images.
set -euo pipefail
cd "$(dirname "$0")/.."
if test "${1:-}" != --no-build; then bash scripts/build.sh; fi
qa_dir=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-sidebar-test.XXXXXX")
chmod 700 "$qa_dir"
report_dir="${2:-$qa_dir/report}"
qa_pid=''
cleanup() {
  if test -n "$qa_pid" && kill -0 "$qa_pid" 2>/dev/null; then
    kill -TERM "$qa_pid" 2>/dev/null || true
    wait "$qa_pid" 2>/dev/null || true
  fi
  rm -rf "$qa_dir"
}
trap cleanup EXIT
qa_app="$qa_dir/MakerGlance Sidebar QA.app"
ditto dist/MakerGlance.app "$qa_app"
qa_id="com.t0nyz0.MakerPulse.SidebarQA.$(uuidgen)"
plutil -replace CFBundleIdentifier -string "$qa_id" "$qa_app/Contents/Info.plist"
codesign --force --sign - --identifier "$qa_id" "$qa_app"
"$qa_app/Contents/MacOS/MakerGlance" --qa-library "$qa_dir/library" --qa-demo-fixture --sidebar-money-audit "$report_dir" > "$qa_dir/process.log" 2>&1 &
qa_pid=$!
for ((attempt=0; attempt<240; attempt++)); do
  if test -f "$report_dir/error.txt"; then cat "$report_dir/error.txt" >&2; exit 1; fi
  if test -f "$report_dir/sidebar-money.json"; then
    python3 - "$report_dir/sidebar-money.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['fictionalDataOnly'] and not report['networkAndKeychainUsed']
assert report['checks'] and all(report['checks'].values()), {k:v for k,v in report['checks'].items() if not v}
print(f"Passed {len(report['checks'])} focused native sidebar/money checks using fictional data; no network or Keychain access.")
PY
    exit 0
  fi
  if ! kill -0 "$qa_pid" 2>/dev/null; then cat "$qa_dir/process.log" >&2; echo 'Focused QA exited without a result.' >&2; exit 1; fi
  sleep 0.25
done
cat "$qa_dir/process.log" >&2
echo 'Focused sidebar/money verification timed out.' >&2
exit 1
