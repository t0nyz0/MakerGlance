#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if test "${1:-}" != --no-build; then bash scripts/build.sh; fi
demo_temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-docs.XXXXXX")
trap 'rm -rf "$demo_temp_dir"' EXIT
demo_app="$demo_temp_dir/MakerGlance Demo.app"
ditto dist/MakerGlance.app "$demo_app"
demo_capture_id="com.t0nyz0.MakerPulse.DocumentationDemo.$(uuidgen)"
plutil -replace CFBundleIdentifier -string "$demo_capture_id" "$demo_app/Contents/Info.plist"
codesign --force --sign - --identifier "$demo_capture_id" "$demo_app"
mkdir -p docs/media
open -n "$demo_app" --args --demo --demo-capture "$demo_temp_dir/capture"
for ((attempt=0; attempt<480; attempt++)); do
  if test -f "$demo_temp_dir/capture/CAPTURE-ERROR.txt"; then
    cat "$demo_temp_dir/capture/CAPTURE-ERROR.txt" >&2
    exit 1
  fi
  if test -f "$demo_temp_dir/capture/PROVENANCE.txt"; then
    cp "$demo_temp_dir/capture/"*.png docs/media/
    cp "$demo_temp_dir/capture/PROVENANCE.txt" "$demo_temp_dir/capture/CAPTURE-CHECKS.json" docs/media/
    python3 scripts/build_demo_animations.py "$demo_temp_dir/capture" docs/media
    python3 scripts/check_documentation.py --strip-png-metadata
    sleep 0.3
    echo 'Captured fictional native demo screenshots; no live account or library was used.'
    exit 0
  fi
  sleep 0.25
done
echo 'Demo capture did not complete within 120 seconds.' >&2
exit 1
