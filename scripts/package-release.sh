#!/bin/bash
# Local preview packaging only. This script never publishes or changes visibility.
set -euo pipefail
cd "$(dirname "$0")/.."
if test "${1:-}" != --no-build; then bash scripts/build.sh; fi
app="$PWD/dist/MakerGlance.app"
version=$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")
build=$(plutil -extract CFBundleVersion raw "$app/Contents/Info.plist")
test "$version" = "$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)"
test "$build" = "$(plutil -extract CFBundleVersion raw Resources/Info.plist)"
arch=$(lipo -archs "$app/Contents/MacOS/MakerGlance")
test "$arch" = arm64
codesign --verify --deep --strict "$app"
output="$PWD/dist/release-$version-build$build"
if test -e "$output"; then echo 'Output already exists; choose a new build instead of mixing release assets.' >&2; exit 1; fi
mkdir -p "$output"
staging=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-package.XXXXXX")
trap 'rm -rf "$staging"' EXIT
ditto --norsrc --noextattr "$app" "$staging/MakerGlance.app"
python3 scripts/verify_release_app.py "$staging/MakerGlance.app" "$version" "$build"
ditto -c -k --norsrc --keepParent "$staging/MakerGlance.app" "$output/MakerGlance-$version-macos-arm64.zip"
cp LICENSE "$staging/LICENSE.txt"
cp docs/DOWNLOADS.md "$staging/Read Me.txt"
ln -s /Applications "$staging/Applications"
hdiutil create -volname MakerGlance -srcfolder "$staging" -format UDZO "$output/MakerGlance-$version-macos-arm64.dmg" > /dev/null
(
 cd "$output"
 shasum -a 256 "MakerGlance-$version-macos-arm64.zip" "MakerGlance-$version-macos-arm64.dmg" > SHA256SUMS.txt
)
verify_dir=$(mktemp -d "${TMPDIR:-/tmp}/makerglance-unzip.XXXXXX")
ditto -x -k "$output/MakerGlance-$version-macos-arm64.zip" "$verify_dir"
python3 scripts/verify_release_app.py "$verify_dir/MakerGlance.app" "$version" "$build"
cmp "$verify_dir/MakerGlance.app/Contents/MacOS/MakerGlance" "$app/Contents/MacOS/MakerGlance"
rm -rf "$verify_dir"
python3 - "$output" "$version" "$build" <<'PY'
import hashlib,json,subprocess,sys
from pathlib import Path
folder=Path(sys.argv[1]);version,build=sys.argv[2:]
commit=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip()
assets={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.suffix in ['.zip','.dmg']}
(folder/'BUILD.json').write_text(json.dumps(dict(version=version,build=build,architecture='arm64',minimumMacOS='14.0',signing='local ad-hoc',notarized=False,sourceCommit=commit,assets=assets),indent=2)+'\n')
print(f'Prepared {version} build {build}: Apple Silicon ZIP/DMG, checksums and build manifest. Nothing published.')
PY
