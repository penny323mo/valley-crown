#!/usr/bin/env python3
"""Guarded fresh Web exports and native packed-resource validation; never publishes."""
from pathlib import Path
from html.parser import HTMLParser
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys

HERE = Path(__file__).resolve().parent
BASE_SHA = '1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
MANIFEST_SHA = '069473af06b2519fb4fff01c774533e76ac07eb77d89b7d918064ad1e7f92bb4'
TEMPLATE_SHA = '1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
FIXTURES = {'packed_inventory.gd': 'f7789476022bca450ebff0cee9a93946eb5e9cf81c9e82ea5147f14c1572857f', 'packed_state.gd': '38409a8b9508a08e5520cc74f84ac7628be86d5fa71f2b8ce2acbd577c20bc0d'}
WEB_FILES = {'index.html', 'index.js', 'index.wasm', 'index.pck', 'index.png', 'index.icon.png',
             'index.apple-touch-icon.png', 'index.audio.worklet.js', 'index.audio.position.worklet.js'}
COUNTS = {'construction_visual': 203, 'map80_placement_races': 38}
FONT_SHA = 'd8dc3f7d8ba62fb1172a6bdd867f8a09e503d3ac5cb349e726491736b5008790'

def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()

LOADED_SHA = sha(__file__)

def require(ok, message):
    if not ok:
        raise RuntimeError(message)

def regular(path):
    require(path.is_file() and not path.is_symlink(), 'Missing/nonregular file: ' + str(path))
    return path

def read_json(path):
    return json.loads(regular(path).read_text())

def load_base():
    path = regular(HERE / 'guarded_manifest_ci.py')
    require(sha(path) == BASE_SHA, 'Base adapter hash mismatch')
    spec = importlib.util.spec_from_file_location('phone_artifact_base', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    module.BUILD = 'vc-43276605e0fb'
    module.ARCHIVE_SHA = 'a4740d4e00862128d06dea1030dfd0efea6c9c0e8bc0e89f3a0396b5314d8f98'
    manifest = module.checked(HERE / 'CONSTRUCTION_SOURCE_PACKAGE.json', MANIFEST_SHA)
    package = read_json(manifest)
    module.ENTRIES = {row['file']: row['sha256'] for row in package['files']}
    def verify_inputs(project, engine, archive):
        module.checked(engine, module.ENGINE_SHA)
        verified, entries = module.verify_source(project, archive, manifest, module.ARCHIVE_SHA, MANIFEST_SHA)
        require(verified['candidate'] == module.BUILD and len(entries) == 192 and verified['runtime_manifest']['inputs'] == 122, 'Unexpected frozen source identity')
        module.inventory(project, entries)
        artifacts = {'base-adapter': path, 'monitor': HERE / 'hardened_monitored_run.py',
                     'engine': engine, 'source-archive': archive, 'source-manifest': manifest}
        expected = {'base-adapter': BASE_SHA, 'monitor': module.MONITOR_SHA, 'engine': module.ENGINE_SHA,
                    'source-archive': module.ARCHIVE_SHA, 'source-manifest': MANIFEST_SHA}
        for name, digest in entries.items():
            artifacts['source:' + name] = project / name; expected['source:' + name] = digest
        return artifacts, expected
    module.verify_inputs = verify_inputs
    module.cache_snapshot = lambda project: module.import_cache(project, module.ENTRIES)
    return module

def import_bindings(base, project, xdg):
    marker = xdg / 'import-complete.json'
    cert = read_json(marker)
    require(cert['build'] == base.BUILD and cert['project'] == str(project), 'Import belongs to another project')
    require(cert['archive_sha256'] == base.ARCHIVE_SHA and cert['engine_sha256'] == base.ENGINE_SHA,
            'Import inputs differ')
    require(cert['manifest_sha256'] == MANIFEST_SHA and cert['adapter_sha256'] == BASE_SHA, 'Import manifest/adapter differs')
    receipt = base.checked(Path(cert['receipt']), cert['receipt_sha256'])
    invocation = base.checked(Path(cert['invocation']), cert['invocation_sha256'])
    base.guard_receipt(receipt, invocation)
    require(base.cache_snapshot(project) == cert['cache_sha256'], 'Imported cache changed')
    extra = {'import-marker': (marker, sha(marker)), 'import-receipt': (receipt, sha(receipt)), 'import-invocation': (invocation, sha(invocation))}
    for name, digest in cert['cache_sha256'].items():
        extra['cache:' + name] = (project / name, digest)
    return extra

def web_snapshot(dest):
    require(dest.is_dir() and not dest.is_symlink(), 'Web destination is not a directory')
    names = set()
    for path in dest.iterdir():
        regular(path)
        names.add(path.name)
    ignored = '.gdignore' in names
    if ignored:
        require((dest / '.gdignore').stat().st_size == 0, 'Nonempty .gdignore is not allowed')
        names.remove('.gdignore')
    require(names == WEB_FILES, 'Unexpected Web payload files: ' + repr(sorted(names ^ WEB_FILES)))
    require((dest / 'index.pck').read_bytes()[:4] == b'GDPC', 'PCK magic mismatch')
    require((dest / 'index.wasm').read_bytes()[:8] == b'\0asm\x01\0\0\0', 'Wasm magic/version mismatch')
    for name in ('index.png', 'index.icon.png', 'index.apple-touch-icon.png'):
        require((dest / name).read_bytes()[:8] == b'\x89PNG\r\n\x1a\n', 'PNG magic mismatch: ' + name)
    require(all((dest / name).stat().st_size > 0 for name in names), 'Empty Web payload')
    return {name: sha(dest / name) for name in sorted(names)}, ignored

def scan_web_payload(dest, roots):
    # Findings contain locations only, never potential credentials or path values.
    signatures = {
        'private_key_block': rb'-----BEGIN ((?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?)PRIVATE KEY-----[ \t]*\r?\n((?:[A-Za-z0-9+/=]+[ \t]*\r?\n)+)-----END \1PRIVATE KEY-----',
        'github_classic_token': rb'gh[pousr]_[A-Za-z0-9]{36,255}',
        'github_fine_grained_token': rb'github_pat_[A-Za-z0-9_]{40,255}',
        'aws_access_key_id': rb'AKIA[0-9A-Z]{16}',
        'openai_key': rb'sk-(?:proj-|svcacct-)?[A-Za-z0-9_-]{40,255}',
        'slack_token': rb'xox[baprs]-[A-Za-z0-9-]{20,255}',
    }
    path_needles = sorted({str(root.resolve()).encode() for root in roots})
    findings = []
    for name in sorted(WEB_FILES):
        contents = regular(dest / name).read_bytes()
        for kind, pattern in signatures.items():
            for match in re.finditer(pattern, contents):
                if kind == 'private_key_block':
                    body = b''.join(match.group(2).split())
                    if len(body) < 64 or len(body) % 4 or not re.fullmatch(rb'[A-Za-z0-9+/]+={0,2}', body):
                        continue
                findings.append({'file': name, 'kind': kind, 'offset': match.start()})
        for needle in path_needles:
            offset = contents.find(needle)
            if offset >= 0:
                findings.append({'file': name, 'kind': 'ci_absolute_path', 'offset': offset})
    return {'passed': not findings, 'files_scanned': len(WEB_FILES),
            'signature_groups': sorted(signatures), 'absolute_root_count': len(path_needles),
            'findings': findings,
            'scope': 'Generic high-confidence credential signatures and this run’s project/XDG/evidence absolute roots; not proof that every possible secret format is absent.'}

def export_bindings(base, evidence):
    summary_path = evidence / 'phase-summary.json'
    summary = read_json(summary_path)
    require(summary.get('passed') is True and summary.get('phase') == 'export', 'Export phase did not pass')
    manifest_path = base.checked(evidence / 'artifact-manifest.json', summary['artifact_manifest_sha256'])
    manifest = read_json(manifest_path)
    require(manifest['build'] == base.BUILD and manifest['archive_sha256'] == base.ARCHIVE_SHA,
            'Export source identity mismatch')
    require(manifest['engine_sha256'] == base.ENGINE_SHA and manifest['template_sha256'] == TEMPLATE_SHA,
            'Export tool identity mismatch')
    require(manifest['monitor_sha256'] == base.MONITOR_SHA and manifest['adapter_sha256'] == LOADED_SHA,
            'Export guard identity mismatch')
    scan_path = base.checked(evidence / 'payload-scan.json', manifest['payload_scan_sha256'])
    scan = read_json(scan_path)
    require(scan.get('passed') is True and scan.get('findings') == [] and scan.get('files_scanned') == len(WEB_FILES),
            'Export payload scan did not pass')
    dest = Path(manifest['destination'])
    observed, ignored = web_snapshot(dest)
    require(observed == manifest['files'] and ignored == manifest['empty_gdignore_excluded'], 'Export payload drift')
    extra = {'export-summary': (summary_path, sha(summary_path)), 'export-manifest': (manifest_path, sha(manifest_path)),
             'payload-scan': (scan_path, sha(scan_path))}
    for name, digest in observed.items():
        extra['web:' + name] = (dest / name, digest)
    require(summary['commands'] and summary['commands'][0]['name'] == 'web-export', 'Export command evidence is absent')
    for row in summary['commands']:
        receipt = evidence / row['receipt']
        result = base.guard_receipt(receipt, receipt.with_suffix('.invocation.json'))
        require(row['passed'] and result['passed'] and result['cleanup_complete'], 'Export command did not pass')
        require(sha(receipt) == row['receipt_sha256'], 'Export receipt drift')
        extra['export-receipt:' + row['name']] = (receipt, sha(receipt))
    return manifest, extra

def validate_state(path, build):
    state = read_json(path)
    require(state.get('build') == build and type(state.get('tick')) is int and state['tick'] == 1200,
            'State build/tick mismatch')
    require(state.get('audit', {}).get('ok') is True, 'State economy audit failed')
    require(state.get('font_sha256') == FONT_SHA and state.get('font_glyphs') is True, 'State font checks failed')
    require(isinstance(state.get('entities'), list) and len(state['entities']) > 0, 'State entities missing')
    return state

def validate_packed_test(path, name, base):
    report = read_json(path)
    require(type(report.get('failed')) is int and report['failed'] == 0, 'Packed suite failed or missing failure count')
    require(type(report.get('passed')) is int and report['passed'] == COUNTS[name], 'Packed assertion count differs')
    require(report.get('build') == base.BUILD, 'Packed report build mismatch')
    rows = report.get('checks')
    require(type(rows) is list and len(rows) == COUNTS[name], 'Packed row coverage differs')
    require(all(type(row) is dict and row.get('pass') is True for row in rows), 'Packed assertion row failed')
    return {'passed': report['passed'], 'failed': 0, 'sha256': sha(path),
            'external_suite_sha256': base.ENTRIES['tests/' + name + '.gd'],
            'identity_basis': 'Bound PCK and unchanged external harness hashes, strict build/rows/count and matching source state. No compiled-source hash claim.'}

class InlineScripts(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.current = None
        self.scripts = []
    def handle_starttag(self, tag, attrs):
        if tag == 'script':
            attributes = dict(attrs)
            if 'src' in attributes:
                require(attributes['src'] == 'index.js', 'Unexpected external script in export HTML')
            else:
                self.current = []
    def handle_data(self, data):
        if self.current is not None:
            self.current.append(data)
    def handle_endtag(self, tag):
        if tag == 'script' and self.current is not None:
            self.scripts.append(''.join(self.current))
            self.current = None

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('phase', choices=['source-state', 'export', 'packed', 'compare'])
    parser.add_argument('--project', type=Path)
    parser.add_argument('--godot')
    parser.add_argument('--archive', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--xdg', type=Path)
    parser.add_argument('--template', type=Path)
    parser.add_argument('--dest', type=Path)
    parser.add_argument('--export-evidence', type=Path)
    parser.add_argument('--source-state', type=Path)
    parser.add_argument('--empty-project', type=Path)
    parser.add_argument('--first', type=Path)
    parser.add_argument('--second', type=Path)
    parser.add_argument('--hosted-execution-approved', action='store_true')
    args = parser.parse_args()
    base = load_base()
    if args.phase != 'compare':
        base.require_hosted_approval(args.hosted_execution_approved, os.environ)
    roots = [getattr(args, key).resolve() for key in ('project', 'output', 'xdg', 'dest', 'empty_project') if getattr(args, key)]
    require(all(not a.is_relative_to(b) and not b.is_relative_to(a) for i, a in enumerate(roots) for b in roots[i+1:]), 'Operation roots overlap')
    output = args.output.resolve()
    require(not output.exists(), 'Evidence directory already exists')
    output.mkdir(parents=True)
    summary = {'build': base.BUILD, 'phase': args.phase, 'passed': False, 'commands': [],
               'scope': 'Fresh Web export reproducibility and native packed-resource validation only; no browser/device acceptance or publication.'}
    summary_path = output / 'phase-summary.json'
    def save():
        summary_path.write_text(json.dumps(summary, indent=2) + '\n')
    save()
    try:
        if args.phase == 'compare':
            require(args.first and args.second, '--first and --second are required')
            a, _ = export_bindings(base, args.first.resolve())
            b, _ = export_bindings(base, args.second.resolve())
            require(a['project'] != b['project'] and a['xdg'] != b['xdg'] and a['destination'] != b['destination'],
                    'Exports are not independently rooted')
            summary['first'] = a['files']; summary['second'] = b['files']
            summary['identical'] = a['files'] == b['files']
            save()
            require(summary['identical'], 'Independent clean Web payload hashes differ')
        else:
            require(args.project and args.godot and args.archive and args.xdg, 'Project, engine, archive and XDG are required')
            project = args.project.resolve(); archive = args.archive.resolve(); xdg = args.xdg.resolve()
            executable = shutil.which(args.godot)
            require(executable is not None, 'Godot binary not found')
            engine = Path(executable).resolve()
            require(not output.is_relative_to(project) and not xdg.is_relative_to(project), 'Evidence/XDG must be outside project')
            if args.phase == 'packed':
                require(not xdg.exists(), 'Packed XDG must be fresh')
            env = base.isolated_environment(xdg)
            monitor = base.load_monitor()
            limits = monitor.Limits(timeout_s=300, sample_target_s=.05, terminate_grace_s=5, kill_reap_grace_s=5,
                                    launch_min_available_kib=4194304, runtime_min_available_kib=1048576, max_rss_kib=2097152)
            def invoke(name, command, extra):
                require(sha(__file__) == LOADED_SHA, 'Artifact adapter changed since load')
                artifacts, expected = base.verify_inputs(project, engine, archive)
                artifacts['artifact-adapter'] = Path(__file__).resolve(); expected['artifact-adapter'] = LOADED_SHA
                for key, (path, digest) in extra.items():
                    artifacts[key] = base.checked(path, digest); expected[key] = digest
                print('START ' + args.phase + ' ' + name + ' build=' + base.BUILD, flush=True)
                result = monitor.run(output / name, command, env=env, limits=limits,
                                     artifacts=artifacts, expected_artifact_hashes=expected)
                base.guard_receipt(output / (name + '.json'), output / (name + '.invocation.json'))
                row = {key: result[key] for key in ('passed', 'exit', 'stop_reason', 'cleanup_complete', 'seconds', 'sampled_peak_rss_kib')}
                row.update(name=name, receipt=name + '.json', receipt_sha256=sha(output / (name + '.json')))
                summary['commands'].append(row); save(); print(json.dumps(row), flush=True)
                require(result['passed'] and result['cleanup_complete'], 'Guarded command failed: ' + name)
                base.verify_inputs(project, engine, archive)
                return row
            fixtures = {'fixture:' + name: (base.checked(HERE / name, digest), digest) for name, digest in FIXTURES.items()}
            if args.phase in ('export', 'source-state'):
                extra = import_bindings(base, project, xdg)
                extra.update(fixtures)
            if args.phase == 'source-state':
                report = output / 'state.report.json'
                row = invoke('source-state', [str(engine), '--headless', '--path', str(project), '--script',
                             str(HERE / 'packed_state.gd'), '--', str(report)], extra)
                validate_state(report, base.BUILD)
                row['report_sha256'] = sha(report)
            elif args.phase == 'export':
                require(args.template and args.dest, '--template and --dest are required')
                template = base.checked(args.template.resolve(), TEMPLATE_SHA)
                dest = args.dest.resolve()
                require(not dest.exists() and not dest.is_relative_to(project), 'Export destination must be fresh and outside project')
                require(not dest.is_relative_to(output) and not xdg.is_relative_to(dest), 'Export destination overlaps evidence/XDG')
                dest.mkdir(parents=True)
                installed = xdg / 'data/godot/export_templates/4.6.3.stable/web_nothreads_release.zip'
                installed.parent.mkdir(parents=True, exist_ok=True)
                require(not installed.exists(), 'Export template destination must be fresh')
                shutil.copyfile(template, installed)
                extra.update({'template-source': (template, TEMPLATE_SHA), 'template-installed': (installed, TEMPLATE_SHA)})
                invoke('web-export', [str(engine), '--headless', '--path', str(project), '--export-release', 'Web', str(dest / 'index.html')], extra)
                hashes, ignored = web_snapshot(dest)
                scan = scan_web_payload(dest, [project, xdg, output])
                scan_path = output / 'payload-scan.json'
                scan_path.write_text(json.dumps(scan, indent=2) + '\n')
                require(scan['passed'], 'Web payload credential/path scan failed; see file/kind/offset receipt')
                for name, digest in hashes.items():
                    extra['web:' + name] = (dest / name, digest)
                node = shutil.which('node', path=env.get('PATH'))
                require(node is not None, 'Node.js is required for exported JavaScript syntax checks')
                for name in ('index.js', 'index.audio.worklet.js', 'index.audio.position.worklet.js'):
                    invoke('syntax-' + name.replace('.', '-'), [node, '--check', str(dest / name)], extra)
                html = InlineScripts(); html.feed((dest / 'index.html').read_text()); html.close()
                require(html.scripts, 'No inline bootstrap script in exported HTML')
                for index, contents in enumerate(html.scripts):
                    script = output / ('inline-' + str(index) + '.js'); script.write_text(contents)
                    bound = dict(extra); bound['inline-script'] = (script, sha(script))
                    invoke('syntax-inline-' + str(index), [node, '--check', str(script)], bound)
                require(web_snapshot(dest) == (hashes, ignored), 'Export changed during syntax checks')
                manifest = {'build': base.BUILD, 'archive_sha256': base.ARCHIVE_SHA, 'engine_sha256': base.ENGINE_SHA,
                            'template_sha256': TEMPLATE_SHA, 'monitor_sha256': base.MONITOR_SHA, 'adapter_sha256': LOADED_SHA,
                            'project': str(project), 'xdg': str(xdg), 'destination': str(dest), 'files': hashes,
                            'empty_gdignore_excluded': ignored, 'payload_scan_sha256': sha(scan_path)}
                manifest_path = output / 'artifact-manifest.json'
                manifest_path.write_text(json.dumps(manifest, indent=2) + '\n')
                summary['artifact_manifest_sha256'] = sha(manifest_path)
            elif args.phase == 'packed':
                require(args.export_evidence and args.source_state and args.empty_project,
                        '--export-evidence, --source-state and --empty-project are required')
                manifest, extra = export_bindings(base, args.export_evidence.resolve())
                require(manifest['project'] == str(project), 'Pack belongs to another verified source project')
                require(args.xdg.resolve() != Path(manifest['xdg']), 'Packed validation needs a fresh isolated XDG')
                extra.update(fixtures)
                source_path = args.source_state.resolve()
                source_summary_path = source_path.parent / 'phase-summary.json'
                source_summary = read_json(source_summary_path)
                require(source_summary['passed'] is True and source_summary['phase'] == 'source-state'
                        and source_summary['build'] == base.BUILD, 'Source state did not pass')
                require(len(source_summary['commands']) == 1, 'Source state command evidence is absent')
                source_row = source_summary['commands'][0]
                require(source_row['name'] == 'source-state' and source_row['passed'] is True, 'Source state command failed')
                require(source_row['report_sha256'] == sha(source_path), 'Source state report drift')
                source_receipt = base.checked(source_path.parent / source_row['receipt'], source_row['receipt_sha256'])
                source_result = base.guard_receipt(source_receipt, source_receipt.with_suffix('.invocation.json'))
                require(source_result['passed'] is True and source_result['cleanup_complete'] is True, 'Source state guard failed')
                extra['source-state-receipt'] = (source_receipt, sha(source_receipt))
                source_state = validate_state(source_path, base.BUILD)
                extra['source-state'] = (source_path, sha(source_path))
                extra['source-state-summary'] = (source_summary_path, sha(source_summary_path))
                empty = args.empty_project.resolve()
                require(not empty.exists(), 'Packed project root must be new and empty')
                require(not empty.is_relative_to(project) and not xdg.is_relative_to(empty) and not output.is_relative_to(empty),
                        'Packed project root overlaps source/XDG/evidence')
                empty.mkdir(parents=True)
                pck = Path(manifest['destination']) / 'index.pck'
                for name in ['inventory', 'state'] + list(COUNTS):
                    require(not list(empty.iterdir()), 'Packed root contains files; source fallback is not permitted')
                    script = HERE / ('packed_' + name + '.gd') if name in ('inventory', 'state') else project / ('tests/' + name + '.gd')
                    report = output / (name + '.report.json')
                    row = invoke(name, [str(engine), '--headless', '--path', str(empty), '--main-pack', str(pck),
                                       '--script', str(script), '--', str(report)], extra)
                    require(not list(empty.iterdir()), 'Packed command wrote into the empty project root')
                    if name == 'inventory':
                        inventory = read_json(report)
                        require(inventory.get('passed') is True and inventory.get('required_resources_present') is True
                                and inventory.get('forbidden') == [] and inventory.get('resource_count', 0) > 0,
                                'Packed resource inventory failed')
                        row['report_sha256'] = sha(report)
                    elif name == 'state':
                        packed_state = validate_state(report, base.BUILD)
                        require(packed_state == source_state, 'Packed state differs from the 1200-tick source state')
                        row.update(report_sha256=sha(report), equals_source_state=True)
                    else:
                        row['test_report'] = validate_packed_test(report, name, base)
                    save()
        summary['passed'] = True; save(); return 0
    except BaseException as exc:
        summary['error'] = {'type': type(exc).__name__, 'message': str(exc)}
        save(); print(json.dumps({'phase': args.phase, 'passed': False, 'error': summary['error']}), flush=True)
        return 1

if __name__ == '__main__':
    sys.exit(main())
