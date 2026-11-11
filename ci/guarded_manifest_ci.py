#!/usr/bin/env python3
"""Hash-bound hosted import/test adapter for a reviewed portable suite manifest.

No workflow, upload, export or deployment. The frozen source manifest is data,
not executable Python. Process ownership/telemetry stays in the unchanged monitor.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import sys
import zipfile

HERE = Path(__file__).resolve().parent
MONITOR_SHA = '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
ENGINE_VERSION = '4.6.3.stable.official.7d41c59c4'


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def checked(path, digest):
    path = Path(path)
    require(path.is_file() and not path.is_symlink(), 'Missing/nonregular input: ' + str(path))
    require(sha(path) == digest, 'Input hash mismatch: ' + str(path))
    return path.resolve()


def relative(name):
    p = PurePosixPath(name)
    require(isinstance(name, str) and name and not p.is_absolute() and '\\' not in name
            and all(part not in ('', '.', '..') for part in name.split('/')), 'Unsafe relative path')
    return p.as_posix()


def child_path(root, name):
    name = relative(name)
    path = root / name
    require(path.resolve().is_relative_to(root), 'Path escapes its root')
    for p in [path, *path.parents]:
        if p == root:
            break
        require(not p.is_symlink(), 'Symlink in path: ' + name)
    return path


def load_monitor():
    path = checked(HERE / 'hardened_monitored_run.py', MONITOR_SHA)
    spec = importlib.util.spec_from_file_location('manifest_ci_monitor', path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def verify_source(project, archive, manifest, archive_sha, manifest_sha):
    checked(archive, archive_sha)
    checked(manifest, manifest_sha)
    package = json.loads(manifest.read_text())
    require(package.get('engine_expected') == ENGINE_VERSION, 'Unexpected engine version')
    require(package.get('execution_enabled') is False, 'Source-review manifest must remain frozen disabled')
    entries = {relative(row['file']): row['sha256'] for row in package['files']}
    require(entries and len(entries) == len(package['files']), 'Empty/duplicate source inventory')
    with zipfile.ZipFile(archive) as z:
        require(set(z.namelist()) == set(entries) and len(z.infolist()) == len(entries), 'Archive inventory differs')
        require(z.testzip() is None, 'Archive CRC failure')
        for info in z.infolist():
            require(not info.is_dir() and (info.external_attr >> 16) & 0o170000 != 0o120000, 'Archive symlink/directory')
            require(hashlib.sha256(z.read(info)).hexdigest() == entries[info.filename], 'Archive member hash differs')
    for name, digest in entries.items():
        checked(child_path(project, name), digest)
    import diagnostic_policy
    original_product = diagnostic_policy.import_policy(package, entries)
    descriptor = package['runtime_manifest']
    runtime = package['public_runtime_descriptor']
    require(hashlib.sha256(json.dumps(runtime,sort_keys=True,separators=(',',':')).encode()).hexdigest()==descriptor['sha256'], 'Public runtime descriptor differs')
    require(runtime['build'] == package['candidate'] and runtime['engine'] == ENGINE_VERSION, 'Runtime identity mismatch')
    require(len(runtime['source_sha256']) == descriptor['inputs'], 'Runtime input count mismatch')
    h = hashlib.sha256()
    for name, digest in sorted(runtime['source_sha256'].items()):
        require(original_product['project_files'].get(name) == digest, 'Runtime entry differs from original product')
        data = original_product['original_project_text'].encode() if name == 'project.godot' else child_path(project, name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == digest, 'Original product runtime bytes differ')
        if name == 'scripts/rules.gd':
            require(re.findall(rb'const BUILD_ID = "([^"]*)"', data)==[runtime['build'].encode()], 'Rules build ID mismatch')
            data = re.sub(rb'const BUILD_ID = "[^"]*"', b'const BUILD_ID = "normalized"', data)
        h.update(name.encode()); h.update(b'\0'); h.update(data)
    require('vc-' + h.hexdigest()[:12] == runtime['build'], 'Derived runtime build mismatch')
    names, reports = set(), set()
    for suite in package['suites']:
        require(suite['name'] not in names and re.fullmatch(r'[a-z0-9_]+', suite['name']), 'Invalid/duplicate suite name')
        names.add(suite['name'])
        script = relative(suite['script'])
        require(script.endswith('.gd') and entries.get(script) == suite['script_sha256'], 'Suite script is not bound')
        prefix = ['GODOT', '--headless', '--path', 'PROJECT', '--script', 'res://' + script, '--']
        require(suite['argv'][:7] == prefix and all(isinstance(v, str) for v in suite['argv']), 'Unexpected command shape')
        report = suite['report']
        require(report not in reports and (report.startswith('OUTPUT/') or report.startswith('PROJECT/reports/')), 'Invalid/duplicate report path')
        reports.add(report)
        relative(report.split('/', 1)[1])
        require(not report.startswith('PROJECT/') or report[8:] not in entries, 'Report would overwrite source')
        c = suite['report_contract']
        require(c['format'] == 'JSON object' and c['must_be_new_file_from_this_run'] is True and c['process_exit_code'] == 0, 'Unsupported report contract')
        require(c['required_integer_fields']['passed'] == {'minimum': 1} and c['required_integer_fields']['failed'] == {'equals': 0}, 'Nonpositive/lenient result contract')
        require(c['minimum_rows'] == 1 and c['rows_field'] in ('checks', 'results'), 'Unsupported rows contract')
        require(c['row_verdict'] in [{'key': 'pass', 'equals': True, 'type': 'boolean'},
                                      {'key': 'passed', 'equals': True, 'type': 'boolean'},
                                      {'key': 'status', 'equals': 'PASS', 'type': 'string'}], 'Lenient/unsupported row verdict')
        require(c['count_equations'] == ['passed == len(' + c['rows_field'] + ')', 'failed == 0'], 'Unsupported count equations')
        receipt = c['required_external_receipt']
        require(receipt == {'candidate_build': package['candidate'], 'runtime_manifest_sha256': descriptor['sha256'],
                           'suite_sha256': suite['script_sha256'], 'require_process_and_output_hash_binding': True}, 'Invalid report receipt binding')
    require(names, 'Empty suite set')
    return package, entries


UID_ALPHABET = b'abcdefghijklmnopqrstuvwxy012345678'

def parse_generated_uid(data):
    # Godot 4.6.3 ResourceUID::id_to_text: base 34, no z/9, canonical 63-bit ID.
    require(re.fullmatch(rb'uid://[a-y0-8]{1,13}\n', data) is not None, 'Malformed generated UID sidecar')
    digits = data[6:-1]
    require(len(digits) == 1 or digits[0] != ord('a'), 'Noncanonical generated UID sidecar')
    number = 0
    for digit in digits:
        number = number * 34 + UID_ALPHABET.index(digit)
    require(number <= 0x7fffffffffffffff, 'Generated UID exceeds Godot signed ID range')
    return number


def inventory(project, entries, allowed_reports=()):
    """Input bytes are immutable; only named reports, import caches and new script UIDs may appear."""
    generated_uids = {name + '.uid' for name in entries if name.endswith('.gd') and name + '.uid' not in entries}
    if 'assets/mature/shaders/building_damage_soot.gdshader' in entries and 'assets/mature/shaders/building_damage_soot.gdshader.uid' not in entries: generated_uids.add('assets/mature/shaders/building_damage_soot.gdshader.uid')
    if 'assets/mature/menu/menu_backdrop.gdshader' in entries and 'assets/mature/menu/menu_backdrop.gdshader.uid' not in entries: generated_uids.add('assets/mature/menu/menu_backdrop.gdshader.uid')
    extra = {}; ids = set(); original_uid_contents = {(project/n).read_bytes() for n in entries if n.endswith('.uid')}
    for path in project.rglob('*'):
        require(not path.is_symlink(), 'Project symlink found')
        if not path.is_file():
            continue
        name = path.relative_to(project).as_posix()
        if name in entries:
            require(sha(path) == entries[name], 'Source inventory mutated: ' + name)
        else:
            require(name.startswith('.godot/') or name in generated_uids or name in allowed_reports, 'Unexpected project write: ' + name)
            if name in generated_uids:
                require(path.stat().st_size <= 20, 'Oversize generated UID sidecar')
                data=path.read_bytes(); number=parse_generated_uid(data)
                require(number not in ids and data not in original_uid_contents, 'Duplicate generated UID sidecar')
                ids.add(number)
            extra[name] = sha(path)
    require(all((project / name).is_file() for name in entries), 'Source inventory lost a file')
    return extra


def import_cache(project, entries, allowed_reports=()):
    extras = inventory(project, entries, allowed_reports)
    cache = {name: digest for name, digest in extras.items()
             if name.startswith('.godot/imported/') or name in ('.godot/uid_cache.bin', '.godot/global_script_class_cache.cfg')}
    require(any(n.startswith('.godot/imported/') for n in cache), 'Import produced no resource cache')
    return dict(sorted(cache.items()))


def report_path(token, project, output):
    if token.startswith('OUTPUT/'):
        return child_path(output, token[7:])
    require(token.startswith('PROJECT/reports/'), 'Report token is not scoped')
    return child_path(project, token[8:])


def validate_report(path, contract):
    require(path.is_file() and not path.is_symlink(), 'Missing/nonregular report')
    report = json.loads(path.read_text())
    require(type(report) is dict, 'Report must be a JSON object')
    rows = report.get(contract['rows_field'])
    require(type(rows) is list and len(rows) >= contract['minimum_rows'], 'Report rows missing/empty')
    for key, constraints in contract['required_integer_fields'].items():
        value = report.get(key)
        require(type(value) is int, 'Report count is not an integer: ' + key)
        if 'minimum' in constraints:
            require(value >= constraints['minimum'], 'Report count below minimum')
        if 'equals' in constraints:
            require(value == constraints['equals'], 'Report reports a failure')
        if constraints.get('equals_rows_length'):
            require(value == len(rows), 'Report total/rows differ')
    require(report['passed'] == len(rows) and report['failed'] == 0, 'Report count/rows differ')
    verdict = contract['row_verdict']
    kind = bool if verdict['type'] == 'boolean' else str
    require(verdict['type'] in ('boolean', 'string'), 'Unknown verdict type')
    for row in rows:
        require(type(row) is dict and type(row.get(verdict['key'])) is kind
                and row[verdict['key']] == verdict['equals'], 'Failed/malformed assertion row')
    for key, expected in contract.get('required_field_values', {}).items():
        require(type(report.get(key)) is type(expected) and report[key] == expected, 'Report identity/status mismatch: ' + key)
    for key, count in contract.get('required_array_lengths', {}).items():
        require(type(report.get(key)) is list and len(report[key]) == count, 'Report coverage count mismatch: ' + key)
    return {'passed': report['passed'], 'failed': 0, 'rows': len(rows), 'sha256': sha(path)}


def guard_receipt(receipt, invocation):
    result = json.loads(receipt.read_text()); request = json.loads(invocation.read_text())
    require(result.get('passed') is True and result.get('cleanup_complete') is True and result.get('child_started') is True
            and type(result.get('exit')) is int and result['exit'] == 0, 'Guarded process failed')
    require(result.get('log_sha256') == sha(receipt.with_suffix('.log')), 'Monitor log bytes changed')
    require(result.get('invocation_sha256') == sha(invocation) and request.get('test_dependencies') is False, 'Mocked/mismatched monitor invocation')
    require(request['helper']['load_sha256'] == request['helper']['invocation_sha256'] == MONITOR_SHA, 'Monitor provenance mismatch')
    require(not result.get('exception') and not result.get('stop_reason') and not result.get('cleanup_errors')
            and not result.get('output_errors') and result.get('post_run_binding_matches')
            and all(v is True for v in result['post_run_binding_matches'].values()), 'Incomplete/failed monitor evidence')
    return result


def require_hosted_approval(approved, environment):
    require(approved is True and environment.get('GITHUB_ACTIONS') == 'true'
            and environment.get('RUNNER_ENVIRONMENT') == 'github-hosted',
            'Explicit reviewed approval and GitHub-hosted Actions are required; no local/self-hosted engine use')


def require_fresh_import(project, entries, xdg):
    require(not xdg.exists() and not xdg.is_symlink() and not (project / '.godot').exists()
            and not (project / '.godot').is_symlink(), 'Import requires fresh source cache and XDG roots')
    require(inventory(project, entries) == {}, 'Initial import requires exactly the declared package files; no generated extras')


def isolated_environment(xdg):
    env = {key: os.environ[key] for key in ('PATH', 'LANG', 'LC_ALL', 'TZ') if key in os.environ}
    for key, name in [('HOME', 'home'), ('TMPDIR', 'tmp'), ('XDG_DATA_HOME', 'data'), ('XDG_CONFIG_HOME', 'config'), ('XDG_CACHE_HOME', 'cache')]:
        folder = xdg / name; folder.mkdir(parents=True, exist_ok=True); env[key] = str(folder)
    env['GODOT_SILENCE_ROOT_WARNING'] = '1'
    return env


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('phase', choices=['import', 'test'])
    for name in ('project', 'archive', 'manifest', 'output', 'xdg'):
        p.add_argument('--' + name, type=Path, required=True)
    p.add_argument('--godot', required=True)
    p.add_argument('--archive-sha256', required=True); p.add_argument('--manifest-sha256', required=True)
    p.add_argument('--hosted-execution-approved', action='store_true', help='Delivery may set only after exact adapter/workflow review')
    args = p.parse_args()
    require_hosted_approval(args.hosted_execution_approved, os.environ)
    project, archive, manifest, output, xdg = [getattr(args, n).resolve() for n in ('project', 'archive', 'manifest', 'output', 'xdg')]
    require(project.is_dir() and not output.exists() and not output.is_symlink(), 'Fresh evidence directory required')
    require(not output.is_relative_to(project) and not project.is_relative_to(output)
            and not xdg.is_relative_to(project) and not project.is_relative_to(xdg)
            and not output.is_relative_to(xdg) and not xdg.is_relative_to(output), 'Evidence/XDG roots must be separate from source and each other')
    engine_name = shutil.which(args.godot); require(engine_name is not None, 'Godot binary not found')
    import diagnostic_policy
    diagnostic_policy.admitted()
    engine = checked(engine_name, ENGINE_SHA)
    package, entries = verify_source(project, archive, manifest, args.archive_sha256, args.manifest_sha256)
    if args.phase == 'import':
        require_fresh_import(project, entries, xdg)
    output.mkdir(parents=True)
    env = isolated_environment(xdg); monitor = load_monitor()
    limits = monitor.Limits(timeout_s=300, sample_target_s=0.05, terminate_grace_s=5, kill_reap_grace_s=5,
                            launch_min_available_kib=4194304, runtime_min_available_kib=1048576, max_rss_kib=2097152)
    marker = xdg / 'import-complete.json'
    summary = {'build': package['candidate'], 'phase': args.phase, 'passed': False, 'commands': [],
               'manifest_sha256': args.manifest_sha256, 'archive_sha256': args.archive_sha256,
               'runtime_manifest_sha256': package['runtime_manifest']['sha256'],
               'scope': 'Guarded native synthetic import/tests only; no browser, physical phone, visual, balance or release acceptance.'}
    summary_path = output / 'phase-summary.json'; allowed_reports = set(); previous_outputs = {}
    def save():
        summary_path.write_text(json.dumps(summary, indent=2) + '\n')
    def invoke(name, argv, extra=None):
        verify_source(project, archive, manifest, args.archive_sha256, args.manifest_sha256)
        inventory(project, entries, allowed_reports)
        artifacts = {'adapter': Path(__file__).resolve(), 'monitor': HERE / 'hardened_monitored_run.py',
                     'engine': engine, 'archive': archive, 'suite-manifest': manifest}
        expected = {'adapter': sha(__file__), 'monitor': MONITOR_SHA, 'engine': ENGINE_SHA,
                    'archive': args.archive_sha256, 'suite-manifest': args.manifest_sha256}
        for name, path in diagnostic_policy.binding_inputs(package['diagnostic_binding']['side']).items():
            key = 'diagnostic:' + name; digest = package['diagnostic_binding']['bound_files_sha256'][name]
            artifacts[key] = checked(path, digest); expected[key] = digest
        for path, digest in {**(extra or {}), **previous_outputs}.items():
            key = 'bound:' + str(path); artifacts[key] = checked(path, digest); expected[key] = digest
        for name_in, digest in entries.items():
            key = 'source:' + name_in; artifacts[key] = project / name_in; expected[key] = digest
        print('START ' + args.phase + ' ' + name, flush=True)
        monitor.run(output / name, argv, env=env, limits=limits, artifacts=artifacts, expected_artifact_hashes=expected)
        receipt = output / (name + '.json'); invocation = output / (name + '.invocation.json')
        result = guard_receipt(receipt, invocation)
        row = {key: result[key] for key in ('passed', 'exit', 'cleanup_complete', 'stop_reason', 'seconds', 'sampled_peak_rss_kib')}
        row.update(name=name, receipt=receipt.name, receipt_sha256=sha(receipt), invocation_sha256=sha(invocation))
        summary['commands'].append(row); save()
        verify_source(project, archive, manifest, args.archive_sha256, args.manifest_sha256)
        inventory(project, entries, allowed_reports)
        if args.phase == 'test':
            require(import_cache(project, entries, allowed_reports) == certificate['cache_sha256'], 'Imported cache inventory drift during tests')
        return row
    save()
    try:
        if args.phase == 'import':
            require(not marker.exists(), 'Import marker exists')
            inventory(project, entries)
            invoke('import', [str(engine), '--headless', '--editor', '--path', str(project), '--import'])
            certificate = {'build': package['candidate'], 'project': str(project), 'archive_sha256': args.archive_sha256,
                           'manifest_sha256': args.manifest_sha256, 'engine_sha256': ENGINE_SHA, 'adapter_sha256': sha(__file__),
                           'receipt': str(output / 'import.json'), 'receipt_sha256': sha(output / 'import.json'),
                           'invocation': str(output / 'import.invocation.json'), 'invocation_sha256': sha(output / 'import.invocation.json'),
                           'cache_sha256': import_cache(project, entries),
                           'generated_uid_sha256': {n:h for n,h in inventory(project,entries).items() if n.endswith('.uid') and not n.startswith('.godot/')}}
            with marker.open('x') as f:
                json.dump(certificate, f, indent=2); f.write('\n')
        else:
            require(marker.is_file() and not marker.is_symlink(), 'Guarded import certificate required')
            certificate = json.loads(marker.read_text())
            for key, expected in {'build': package['candidate'], 'project': str(project), 'archive_sha256': args.archive_sha256,
                                  'manifest_sha256': args.manifest_sha256, 'engine_sha256': ENGINE_SHA, 'adapter_sha256': sha(__file__)}.items():
                require(certificate.get(key) == expected, 'Import certificate input mismatch: ' + key)
            receipt = checked(certificate['receipt'], certificate['receipt_sha256'])
            invocation = checked(certificate['invocation'], certificate['invocation_sha256'])
            guard_receipt(receipt, invocation)
            require(import_cache(project, entries) == certificate['cache_sha256'], 'Imported cache drift')
            extra = {marker: sha(marker), receipt: sha(receipt), invocation: sha(invocation)}
            extra.update({project / name: digest for name, digest in certificate['cache_sha256'].items()})
            for suite in package['suites']:
                path = report_path(suite['report'], project, output)
                require(not path.exists() and not path.is_symlink(), 'Test report already exists')
                if suite['report'].startswith('PROJECT/'):
                    allowed_reports.add(suite['report'][8:])
                argv = []
                for token in suite['argv']:
                    if token == 'GODOT': argv.append(str(engine))
                    elif token == 'PROJECT': argv.append(str(project))
                    elif token.startswith('OUTPUT/'): argv.append(str(report_path(token, project, output)))
                    else: argv.append(token)
                row = invoke(suite['name'], argv, extra)
                row['report'] = validate_report(path, suite['report_contract'])
                row['report'].update(path=suite['report'], build=package['candidate'], suite_sha256=suite['script_sha256'],
                                     runtime_manifest_sha256=package['runtime_manifest']['sha256'])
                # Explicit PROJECT/reports outputs are copied into evidence only
                # after validation. Their source-side originals stay hash-bound.
                if suite['report'].startswith('PROJECT/'):
                    copy = output / (suite['name'] + '.report.json'); copy.write_bytes(path.read_bytes())
                    previous_outputs[copy] = sha(copy)
                previous_outputs[path] = sha(path)
                save()
        summary['source_inventory_preserved'] = True; summary['passed'] = True; save(); return 0
    except BaseException as exc:
        summary['error'] = {'type': type(exc).__name__, 'message': str(exc)}; save()
        print(json.dumps({'phase': args.phase, 'passed': False, 'error': summary['error']}), flush=True)
        return 1


if __name__ == '__main__':
    sys.exit(main())
