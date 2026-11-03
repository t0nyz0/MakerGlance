#!/usr/bin/env python3
"""Prepare a local, history-free publication candidate. Never pushes or changes visibility."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

from check_repository import files, findings, prohibited_name

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--author-name', required=True)
    parser.add_argument('--author-email', required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('Output already exists; preserve it and choose a new destination.')
    if not args.author_email.endswith('@users.noreply.github.com') or any(c in args.author_email for c in '\r\n'):
        parser.error('Use an account-scoped GitHub noreply address for publication metadata.')
    inventory = {}
    for relative in files(ROOT):
        source = ROOT / relative
        if source.is_symlink() or not source.is_file() or not source.resolve().is_relative_to(ROOT):
            raise ValueError(f'Unsafe source entry: {relative}')
        data = source.read_bytes()
        if prohibited_name(relative) or findings(data):
            raise ValueError(f'Publication guard rejected {relative}; matching data withheld.')
        inventory[str(relative)] = hashlib.sha256(data).hexdigest()
    output.mkdir(parents=True)
    for relative in inventory:
        target = output / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / relative, target)
        target.chmod((ROOT / relative).stat().st_mode & 0o777)
    subprocess.run(['git', 'init', '--quiet', '--template=', '--initial-branch=main', str(output)], check=True)
    def git(*arguments):
        return subprocess.check_output(['git', '-C', str(output), *arguments], text=True).strip()
    git('config', 'user.name', args.author_name)
    git('config', 'user.email', args.author_email)
    git('-c', 'core.excludesFile=/dev/null', 'add', '--force', '--all')
    git('-c', 'commit.gpgsign=false', 'commit', '--quiet', '-m', 'Prepare MakerGlance 3.9.2 public source preview')
    assert git('rev-list', '--all', '--count') == '1'
    assert git('remote') == ''
    assert git('for-each-ref', '--format=%(refname)') == 'refs/heads/main'
    tracked = subprocess.check_output(['git', '-C', str(output), 'ls-files', '-z']).decode().split('\0')
    assert set(filter(None, tracked)) == set(inventory)
    for relative, checksum in inventory.items():
        assert hashlib.sha256((output / relative).read_bytes()).hexdigest() == checksum
    for options in [[], ['--history']]:
        subprocess.run([sys.executable, str(output / 'scripts/check_repository.py'), *options], cwd=output, check=True)
    commit = git('rev-parse', 'HEAD')
    manifest = output.with_name(output.name + '-manifest.json')
    manifest.write_text(json.dumps({'publicationCommit':commit, 'historyCommits':1,
        'remoteConfigured':False, 'files':inventory}, indent=2) + '\n')
    print(f'Prepared {len(inventory)} reviewed files in one clean commit: {commit}')
    print('Original repository/history are preserved. No remote or public repository was changed.')


if __name__ == '__main__':
    main()
