#!/bin/bash
# Offline native regression suite. Never reads the user's library or Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
if test "${1:-}" != --no-build; then bash scripts/build.sh; fi
qa_dir=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-native-test.XXXXXX")
chmod 700 "$qa_dir"
qa_pid=''
cleanup() {
  if test -n "$qa_pid" && kill -0 "$qa_pid" 2>/dev/null; then
    kill -TERM "$qa_pid" 2>/dev/null || true
    wait "$qa_pid" 2>/dev/null || true
  fi
  rm -rf "$qa_dir"
}
trap cleanup EXIT
qa_app="$qa_dir/MakerGlance Native QA.app"
ditto dist/MakerGlance.app "$qa_app"
qa_id="com.t0nyz0.MakerPulse.NativeQA.$(uuidgen)"
plutil -replace CFBundleIdentifier -string "$qa_id" "$qa_app/Contents/Info.plist"
codesign --force --sign - --identifier "$qa_id" "$qa_app"
"$qa_app/Contents/MacOS/MakerGlance" --qa-library "$qa_dir/library" --qa-demo-fixture --ui-audit "$qa_dir/report" > "$qa_dir/process.log" 2>&1 &
qa_pid=$!
for ((attempt=0; attempt<720; attempt++)); do
  if test -f "$qa_dir/report/audit-error.txt"; then
    cat "$qa_dir/report/audit-error.txt" >&2
    exit 1
  fi
  if test -f "$qa_dir/report/audit.json"; then
    python3 - "$qa_dir/report/audit.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
assert report['isolatedQA'] and report['profile']=='samplecreator'
assert report['sessionAvailable'] is False
assert not any(report['privateFeedsVerifiedThisRun'].values())
groups=['watchedLayoutControls','dashboardSortControls','dashboardPointerControls','myPrintsControls','menuActions','textSizeControls']
checks={}
for group in groups:
    assert report[group], group
    checks.update({group+'.'+key:value for key,value in report[group].items()})
for key in ['nativePausedClick','fixtureWatchMovement','nativeWatchedClick','nativeAllClick']:
    checks['nativeControls.'+key]=report['nativeControls'][key]
for key in ['mainModelFilterClicks','dashboardWindowClicks','baselineDatesUnknown','appearanceRestoredFromStorage']:
    checks[key]=report[key]
assert all(value is True for value in checks.values()),checks
print(json.dumps({'fixture':'fictional offline demo','networkAndKeychainUsed':False,'version':report['version'],'build':report['build'],'passedChecks':len(checks),'checks':checks},indent=2))
PY
    exit 0
  fi
  if ! kill -0 "$qa_pid" 2>/dev/null; then
    cat "$qa_dir/process.log" >&2
    echo 'Native QA exited before producing a result.' >&2
    exit 1
  fi
  sleep 0.25
done
cat "$qa_dir/process.log" >&2
echo 'Native control regression timed out.' >&2
exit 1
