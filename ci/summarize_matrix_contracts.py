#!/usr/bin/env python3
"""Bounded native scalar summaries; never emit raw logs, rows, paths or environment."""
from pathlib import Path
import hashlib
import json
import re
import guarded_manifest_ci as adapter

BUILD = 'vc-c7211e1083c8'
PACKAGE = 'cecdfe1c4f20ffeeab3aedc0bc2f085957e2f37f75496ce1078faa9feaa44154'
MONITOR = '4c7802bcfb53a2f73f501635cdf483e1459d3d86eb881a7450dccd3bbd705d50'
ADAPTER = '1737dfca2778614730b6dd6d3803009460139a19dfe901b830e84120abce75e0'
ENGINE = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
SCRIPTS = {
    'occlusion_geometry_contract': '22e294c2ef4c8682d73967d7dda89629db13cc0a63ef0cd7c8fbc75a915d0cec',
    'occlusion_observation_lifecycle': 'd1333014d1b741a7f78959ed3ca4307ccced15e6e4f96b32afae3b4655ac83f8',
}


def regular(path):
    assert path.is_file() and not path.is_symlink() and path.stat().st_size <= 16000000
    return path


def digest(path): return hashlib.sha256(regular(path).read_bytes()).hexdigest()


def read(path):
    value = json.loads(regular(path).read_text(), parse_constant=lambda _: (_ for _ in ()).throw(ValueError()))
    assert type(value) is dict
    return value


def integer(value):
    assert type(value) is int and -255 <= value <= 1000000000
    return value


def boolean(value):
    assert type(value) is bool
    return value


def expected_labels(script):
    labels = re.findall(r'check\("([^"]+)"', regular(script).read_text())
    expanded = []
    for name in labels:
        if name == 'nonzero visibility range fails closed ':
            expanded.extend(name + which for which in ('begin', 'end'))
        else: expanded.append(name)
    assert 1 <= len(expanded) <= 64 and len(set(expanded)) == len(expanded)
    return expanded


def summarize(root=Path('.')):
    package_path = root / 'OCCLUSION_NATIVE_CONTRACTS.json'
    assert digest(package_path) == PACKAGE and digest(Path(adapter.__file__)) == ADAPTER
    package = read(package_path); suites = package['suites']
    assert package['candidate'] == BUILD and [suite['name'] for suite in suites] == list(SCRIPTS)
    project = root / 'project'; evidence = root / 'contract-evidence'
    assert digest(project / package['runtime_manifest']['file']) == package['runtime_manifest']['sha256']
    phase_path = evidence / 'phase-summary.json'; phase = read(phase_path)
    assert phase['build'] == BUILD and phase['phase'] == 'test' and phase['manifest_sha256'] == PACKAGE
    assert phase['archive_sha256'] == package['source_archive_sha256'] and phase['runtime_manifest_sha256'] == package['runtime_manifest']['sha256']
    phase_passed = boolean(phase['passed'])
    commands = phase['commands']; assert type(commands) is list and len(commands) <= 2
    names = [command['name'] for command in commands]
    assert names == list(SCRIPTS)[:len(names)]
    out = {'build': BUILD, 'package_sha256': PACKAGE, 'runtime_manifest_sha256': package['runtime_manifest']['sha256'],
           'phase_passed': phase_passed, 'phase_sha256': digest(phase_path), 'suites': []}
    for suite in suites:
        name = suite['name']; script = project / suite['script']; source_sha = SCRIPTS[name]
        assert suite['script_sha256'] == source_sha == digest(script)
        labels = expected_labels(script)
        receipt = evidence / (name + '.json'); invocation = evidence / (name + '.invocation.json')
        log = evidence / (name + '.log'); report = project / suite['report'].removeprefix('PROJECT/')
        copy = evidence / (name + '.report.json')
        row = {'suite': name, 'suite_sha256': source_sha, 'expected_checks': len(labels),
               'receipt_available': receipt.exists(), 'report_available': report.exists(), 'status': 'not_run'}
        if receipt.exists():
            guard = read(receipt); request = read(invocation)
            assert request['test_dependencies'] is False and request['helper']['load_sha256'] == request['helper']['invocation_sha256'] == MONITOR
            assert guard['invocation_sha256'] == digest(invocation) and guard['log_sha256'] == digest(log)
            assert request['executable']['sha256'] == ENGINE
            assert request['artifacts']['suite-manifest']['sha256'] == PACKAGE
            assert request['artifacts']['source:' + suite['script']]['sha256'] == source_sha
            row.update(receipt_sha256=digest(receipt), guard_passed=boolean(guard['passed']),
                       cleanup_complete=boolean(guard['cleanup_complete']),
                       exit=integer(guard['exit']) if guard['exit'] is not None else None,
                       oom_before=integer(guard['system_before']['oom_kill']),
                       oom_after=integer(guard['system_after']['oom_kill']), peak_rss_kib=integer(guard['sampled_peak_rss_kib']))
            text = regular(log).read_text(errors='replace')
            row['diagnostic_categories'] = [category for category, pattern in [
                ('parse', 'Parse Error'), ('shader', 'Shader Error|SHADER ERROR'),
                ('script', 'SCRIPT ERROR'), ('assertion', 'Assertion failed|failed=[1-9]')]
                if re.search(pattern, text)][:4]
            row['status'] = 'guard_completed' if row['guard_passed'] else 'guard_failed'
            if row['guard_passed']:
                adapter.guard_receipt(receipt, invocation)
        if report.exists():
            assert receipt.exists()
            result = read(report); checks = result['checks']
            assert type(checks) is list and 1 <= len(checks) <= len(labels)
            passed, failed = integer(result['passed']), integer(result['failed'])
            assert passed >= 0 and failed >= 0 and passed + failed == len(checks)
            assert sum(boolean(check['pass']) for check in checks) == passed
            actual = [check['name'] for check in checks]
            assert all(type(name) is str and name in labels for name in actual) and len(set(actual)) == len(actual)
            assert actual == [name for name in labels if name in actual]
            for field, value in suite['report_contract']['required_field_values'].items():
                assert result.get(field) == value
            row.update(passed=passed, failed=failed, report_sha256=digest(report),
                       failed_test_ids=[check['name'] for check in checks if not check['pass']][:64])
            if copy.exists(): assert digest(copy) == row['report_sha256']
            if failed: row['status'] = 'checks_failed'
            elif row.get('guard_passed') and actual == labels: row['status'] = 'checks_passed'
        for command in commands:
            if command['name'] != name: continue
            assert command['receipt_sha256'] == row.get('receipt_sha256')
            assert command['invocation_sha256'] == digest(invocation)
            if 'report' in command:
                proof = command['report']
                assert proof['sha256'] == row.get('report_sha256') and proof['suite_sha256'] == source_sha
                assert proof['build'] == BUILD and proof['runtime_manifest_sha256'] == package['runtime_manifest']['sha256']
        if phase_passed:
            assert row['status'] == 'checks_passed' and row['cleanup_complete'] and row['exit'] == 0
            assert row['oom_before'] == row['oom_after'] and row['passed'] == len(labels) and row['failed'] == 0
            assert copy.exists() and name in names
            command = commands[names.index(name)]; assert 'report' in command
            adapter.validate_report(report, suite['report_contract'])
        out['suites'].append(row)
    if phase_passed: assert len(commands) == 2
    return out


def main():
    try:
        output = summarize()
        print('NATIVE_CONTRACTS_SUMMARY ' + json.dumps(output, sort_keys=True))
        return 0
    except BaseException:
        print('NATIVE_CONTRACTS_SUMMARY_INVALID')
        return 1


if __name__ == '__main__': raise SystemExit(main())
