"""Check native content, XML, metadata and source-image fidelity without dependencies."""
from collections import Counter
from html.parser import HTMLParser
from pathlib import Path
from zipfile import ZipFile
from xml.etree import ElementTree as ET
import hashlib
import re
import unicodedata

ROOT = Path(__file__).resolve().parents[1]

class Content(HTMLParser):
    def __init__(self):
        super().__init__()
        self.active = []
        self.items = {"heading": [], "pre": []}

    def handle_starttag(self, tag, attrs):
        kind = "heading" if tag in ("h1", "h2", "h3", "h4", "h5", "h6") else "pre" if tag == "pre" else None
        if kind:
            self.active.append([tag, kind, []])

    def handle_data(self, data):
        for item in self.active:
            item[2].append(data)

    def handle_endtag(self, tag):
        if self.active and self.active[-1][0] == tag:
            _, kind, chunks = self.active.pop()
            value = unicodedata.normalize("NFKC", "".join(chunks)).replace("\u00ad", "").replace("\u200b", "")
            self.items[kind].append(" ".join(value.split()))

def parse(archive, validate_xml=False):
    parser = Content()
    for name in archive.namelist():
        if name.endswith((".xhtml", ".html")):
            if validate_xml:
                ET.fromstring(archive.read(name))
            parser.feed(archive.read(name).decode())
    return parser

with ZipFile(ROOT / 'from-javascript-to-rust.epub') as old, ZipFile(ROOT / 'output/from-javascript-to-rust.epub') as new:
    assert new.testzip() is None
    assert new.infolist()[0].filename == 'mimetype'
    assert new.infolist()[0].compress_type == 0
    assert new.read('mimetype') == b'application/epub+zip'
    before, after = parse(old), parse(new, validate_xml=True)
    # The old converter leaked AsciiDoc's {pp} substitution into one JS example.
    # Current Asciidoctor correctly emits the source's increment operator (++).
    before.items['pre'] = [text.replace('{pp}', '++') for text in before.items['pre']]
    for kind in before.items:
        missing = Counter(before.items[kind]) - Counter(after.items[kind])
        assert not missing, (kind, missing)
        print(f'{kind}: {len(before.items[kind])} original, {len(after.items[kind])} rebuilt, none lost')
    rootfile = next(x.attrib['full-path'] for x in ET.fromstring(new.read('META-INF/container.xml')).iter() if x.tag.endswith('rootfile'))
    metadata = ET.fromstring(new.read(rootfile))
    fields = {x.tag.rsplit('}', 1)[-1]: x.text for x in metadata.iter() if x.tag.startswith('{http://purl.org/dc/elements/1.1/}')}
    assert fields['title'] == 'Go From JavaScript to Rust'
    assert fields['creator'] == 'Jarrod Overson'
    assert fields['language'] == 'en'
    hashes = {hashlib.sha256(new.read(name)).hexdigest() for name in new.namelist()}
    images = {ROOT / 'book/images/cover.png'}
    for chapter in (ROOT / 'book/chapters').glob('*.adoc'):
        images.update(ROOT / 'book/images' / name for name in re.findall(r'image::([^\[]+)\[', chapter.read_text()))
    for image in images:
        assert image.is_file(), image
        assert hashlib.sha256(image.read_bytes()).hexdigest() in hashes, f'image not packaged byte-for-byte: {image}'
    print(f'All {len(images)} referenced source images packaged unchanged; title/author/language correct.')
