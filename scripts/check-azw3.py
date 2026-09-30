"""Reject AZW3 conversions that lose EPUB headings, code or embedded images."""
from collections import Counter
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
helpers = runpy.run_path(str(ROOT / 'scripts/check-content.py'))
with ZipFile(ROOT / 'output/from-javascript-to-rust.epub') as epub:
    before = helpers['parse'](epub)
    images = sum(name.lower().endswith(('.png', '.gif', '.jpg', '.jpeg', '.svg')) for name in epub.namelist())
with tempfile.TemporaryDirectory(prefix='node-to-rust-azw3-') as folder:
    target = Path(folder) / 'book'
    subprocess.run([sys.argv[1], '--explode-book', str(ROOT / 'output/from-javascript-to-rust.azw3'), str(target)], check=True)
    after = helpers['Content']()
    for path in sorted(target.rglob('*.html')):
        after.feed(path.read_text())
    for kind in before.items:
        missing = Counter(before.items[kind]) - Counter(after.items[kind])
        assert not missing, (kind, missing)
    packaged_images = list((target / 'images').glob('*'))
    assert len(packaged_images) >= images, ('images lost', images, len(packaged_images))
    print(f'AZW3 preserves all EPUB headings/code and {len(packaged_images)} images.')
