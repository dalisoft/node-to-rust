"""Publish validated formats; unchanged source/toolchain inputs exit successfully."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
ASSETS = ['from-javascript-to-rust.epub', 'from-javascript-to-rust.azw3']

def gh(*args):
    return subprocess.run(['gh', *args], check=True, text=True, capture_output=True).stdout

def fingerprint():
    paths = subprocess.check_output([
        'git', 'ls-files', '-z', 'book', 'scripts', '.github/workflows/ebooks.yml',
        'Gemfile', 'Gemfile.lock', '.ruby-version', 'from-javascript-to-rust.epub'
    ]).decode().split('\0')
    digest = hashlib.sha256()
    for name in sorted(filter(None, paths)):
        digest.update(name.encode() + b'\0' + (ROOT / name).read_bytes() + b'\0')
    return digest.hexdigest()

def check():
    latest = json.loads(gh('release', 'list', '--limit', '1', '--json', 'tagName'))
    changed = True
    if latest:
        tag = latest[0]['tagName']
        assets = json.loads(gh('release', 'view', tag, '--json', 'assets'))['assets']
        names = {asset['name'] for asset in assets}
        if set(ASSETS + ['build-manifest.json']) <= names:
            with tempfile.TemporaryDirectory(prefix='node-to-rust-release-') as folder:
                gh('release', 'download', tag, '--pattern', 'build-manifest.json', '--dir', folder)
                manifest = json.loads((Path(folder) / 'build-manifest.json').read_text())
                changed = manifest['source_sha256'] != fingerprint()
    value = f'changed={str(changed).lower()}'
    print(value)
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a') as output:
            output.write(value + '\n')

def publish():
    output = ROOT / 'output'
    for name in ASSETS:
        assert (output / name).stat().st_size > 1000, f'Missing format: {name}'
    manifest = {
        'source_sha256': fingerprint(),
        'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD']).decode().strip(),
        'assets': {name: hashlib.sha256((output / name).read_bytes()).hexdigest() for name in ASSETS},
    }
    path = output / 'build-manifest.json'
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    today = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=5))).date()
    tag = f'release-{today}'
    releases = json.loads(gh('release', 'list', '--limit', '100', '--json', 'tagName'))
    files = [str(output / name) for name in ASSETS] + [str(path)]
    if tag in {release['tagName'] for release in releases}:
        gh('release', 'upload', tag, *files, '--clobber')
    else:
        gh('release', 'create', tag, *files, '--target', manifest['commit'],
           '--title', f'From JavaScript to Rust — {today}',
           '--notes', 'Repaired EPUB and Kindle-compatible AZW3, built from the original AsciiDoc sources. '
           'Includes packaged images, repaired internal references, code highlighting, and author metadata. '
           'Book license: CC BY-NC 4.0. build-manifest.json records source and asset SHA-256 hashes.')
    print(gh('release', 'view', tag, '--json', 'url'))

if __name__ == '__main__':
    if len(sys.argv) != 2 or sys.argv[1] not in ('check', 'publish'):
        raise SystemExit('Usage: python3 scripts/release.py check|publish')
    {'check': check, 'publish': publish}[sys.argv[1]]()
