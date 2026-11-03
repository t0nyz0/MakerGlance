#!/usr/bin/env python3
"""Generate local-evidence badges; check rejects stale source or badge claims."""
import argparse, hashlib, html, json, plistlib, re
from datetime import datetime, timezone
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/LOCAL_VALIDATION.json'
START, END = '<!-- verified-badges:start -->', '<!-- verified-badges:end -->'
def inputs():
    return sorted({*ROOT.glob('Sources/**/*.swift'), *ROOT.glob('Tests/**/*.swift'), *ROOT.glob('scripts/*.py'), *ROOT.glob('scripts/*.sh'), *ROOT.glob('scripts/*.swift'), ROOT/'Package.swift', ROOT/'Resources/Info.plist'})
def digest():
    h = hashlib.sha256()
    for p in inputs(): h.update(str(p.relative_to(ROOT)).encode()+b'\0'+p.read_bytes()+b'\0')
    return h.hexdigest()
def badge(label, value, color):
    a, b = len(label)*7+18, len(value)*7+18
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{a+b}" height="24" role="img" aria-label="{html.escape(label+": "+value)}"><rect width="{a+b}" height="24" rx="4" fill="#343539"/><path d="M{a} 0h{b-4}q4 0 4 4v16q0 4-4 4H{a}Z" fill="#{color}"/><g fill="#fff" text-anchor="middle" font-family="Verdana,sans-serif" font-size="11"><text x="{a/2}" y="16">{html.escape(label)}</text><text x="{a+b/2}" y="16">{html.escape(value)}</text></g></svg>\n'
def products(e):
    return [('version','source','v'+e['version'],'805D0A','#build--try-it'),('tests','local tests',str(e['tests'])+' passing','285B85','docs/LOCAL_VALIDATION.json'),('build','local build','verified','55565C','docs/LOCAL_VALIDATION.json'),('macos','macOS',e['macos']+' target','55565C','#build--try-it'),('swift','Swift','6','95420B','Package.swift'),('license','license','MIT','645489','LICENSE')]
def block(e):
    return START+'\n<p align="center">\n'+'\n'.join(f'<a href="{link}"><img src="docs/media/badges/{name}.svg" alt="{label}: {value}"></a>' for name,label,value,color,link in products(e))+'\n</p>\n'+END

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--write',action='store_true');p.add_argument('--check',action='store_true');p.add_argument('--test-log',type=Path);p.add_argument('--build-log',type=Path);a=p.parse_args()
    info=plistlib.loads((ROOT/'Resources/Info.plist').read_bytes())
    if a.write:
        assert a.test_log and a.build_log, 'Provide actual local test and build logs'
        tests=a.test_log.read_text(); build=a.build_log.read_text()
        assert "Test Suite 'All tests' passed" in tests and 'Built:' in build and re.search(r'Build(?: of product .+)? complete!', build)
        counts=re.findall(r'Executed (\d+) tests, with 0 failures',tests);assert counts
        assert min(a.test_log.stat().st_mtime,a.build_log.stat().st_mtime) >= max(x.stat().st_mtime for x in inputs()), 'Revalidate changed source first'
        e=dict(version=info['CFBundleShortVersionString'], build=info['CFBundleVersion'], tests=int(counts[-1]), macos=info['LSMinimumSystemVersion'], sourceSHA256=digest(), verifiedAtUTC=datetime.now(timezone.utc).isoformat(timespec='seconds'), scope='Local Apple Silicon tests and optimized ad-hoc build; not a CI result')
        EVIDENCE.write_text(json.dumps(e,indent=2)+'\n'); dest=ROOT/'docs/media/badges';dest.mkdir(exist_ok=True)
        for name,label,value,color,link in products(e): (dest/(name+'.svg')).write_text(badge(label,value,color))
        readme=ROOT/'README.md';s=readme.read_text()
        if START in s:s=re.sub(re.escape(START)+'.*?'+re.escape(END),block(e),s,flags=re.S)
        else:s=s.replace('<p align="center"><img src="docs/media/badges.svg" alt="Native macOS 14+, Swift 6, local-first, MIT licensed"></p>',block(e))
        readme.write_text(s)
    e=json.loads(EVIDENCE.read_text())
    assert e['sourceSHA256']==digest() and e['version']==info['CFBundleShortVersionString'] and e['build']==info['CFBundleVersion'], 'Local badge evidence is stale'
    assert block(e) in (ROOT/'README.md').read_text()
    for name,label,value,color,link in products(e): assert (ROOT/'docs/media/badges'/(name+'.svg')).read_text()==badge(label,value,color)
    print(f"Verified local source v{e['version']}, {e['tests']} passing tests, build evidence and six self-hosted badges. No remote CI claim.")
if __name__=='__main__':main()
