#!/usr/bin/env python3
"""Prepare the exact official single-threaded Web release template; no launch."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import stat
import zipfile
import official_download as official
from prepare_web_release import admitted

URL = 'https://github.com/godotengine/godot/releases/download/4.6.3-stable/Godot_v4.6.3-stable_export_templates.tpz'
ARCHIVE_SHA = '3fbe2c0e2dec9d537ab9ec97bcf8da91dcf23357fc51f67092dd068d839290a8'
ARCHIVE_BYTES = 1255918323
TEMPLATE_SHA = '1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
TEMPLATE_BYTES = 9574223
MEMBER = 'templates/web_nothreads_release.zip'

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

def prepare(work):
    admitted()
    work = work.resolve()
    official.need(work.is_dir() and not work.is_symlink(), 'Prepared work root required')
    archive = work / 'official-export-templates.tpz'
    official.download(URL, archive, maximum=ARCHIVE_BYTES)
    official.need(archive.stat().st_size == ARCHIVE_BYTES and sha(archive) == ARCHIVE_SHA, 'Official release archive identity differs')
    with zipfile.ZipFile(archive) as z:
        rows = [i for i in z.infolist() if i.filename == MEMBER]
        official.need(len(rows) == 1, 'Missing or duplicate Web template member')
        info = rows[0]
        official.need(info.file_size == TEMPLATE_BYTES and stat.S_IFMT(info.external_attr >> 16) in (0, stat.S_IFREG) and not info.flag_bits & 1, 'Invalid Web template member')
        data = z.read(info)
    official.need(len(data) == TEMPLATE_BYTES and hashlib.sha256(data).hexdigest() == TEMPLATE_SHA, 'Web template identity differs')
    destination = work / 'template'
    destination.mkdir()
    target = destination / 'web_nothreads_release.zip'
    target.write_bytes(data)
    with zipfile.ZipFile(target) as z:
        official.need(z.testzip() is None, 'Web template CRC failure')
        official.need(set(z.namelist()) == {'godot.js', 'godot.wasm', 'godot.audio.worklet.js', 'godot.audio.position.worklet.js', 'godot.html', 'godot.service.worker.js', 'godot.offline.html'}, 'Unexpected runtime template inventory')
    receipt = dict(source=URL, archive_sha256=ARCHIVE_SHA, archive_bytes=ARCHIVE_BYTES, template_sha256=TEMPLATE_SHA, template_bytes=TEMPLATE_BYTES, engine_executed=False)
    (work / 'template-provenance.json').write_text(json.dumps(receipt, indent=2) + '\n')
    print(json.dumps(receipt))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, required=True)
    prepare(parser.parse_args().work)
