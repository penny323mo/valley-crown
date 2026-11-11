"""INERT proposal. Pure validation/planning; no imports capable of process launch.

This is NOT a live execution guard and deliberately has no executable adapter.
Parent must review the README and implement/review host supervision separately.
"""
import re

GIB = 1024 ** 3
BUILD = 'vc-46221f522751'


def require(ok, why):
    if not ok:
        raise ValueError(why)


def validate_lock(lock, actual_files):
    require(lock.get('reviewed') is True, 'Parent review missing')
    require(lock.get('build') == BUILD, 'Wrong build')
    require(lock.get('engine') == '4.6.3', 'Wrong engine')
    require(re.fullmatch(r'mcr\.microsoft\.com/playwright:v\d+\.\d+\.\d+-noble@sha256:[0-9a-f]{64}', lock.get('image', '')), 'Pin official version and verified digest')
    require(re.fullmatch(r'[0-9a-f]{64}', lock.get('npm_lock_sha256', '')), 'Reviewed npm lock missing')
    expected = lock.get('export_files', {})
    require(expected and expected == actual_files, 'Exact export inventory mismatch')
    require('index.html' in expected, 'Missing entrypoint')
    require(any(p.endswith('.wasm') for p in expected), 'Missing wasm')
    require(any(p.endswith('.pck') for p in expected), 'Missing game pack')
    for name, digest in expected.items():
        require(isinstance(name, str) and not name.startswith('/') and all(x not in ('', '.', '..') for x in name.split('/')) and '\\' not in name, 'Unsafe export path')
        require(re.fullmatch(r'[0-9a-f]{64}', digest), 'Invalid export digest')


def admit(host):
    require(host.get('github_actions') is True and host.get('runner_environment') == 'github-hosted', 'Fresh GitHub-hosted runner only')
    require(host.get('os_release') == 'ubuntu-24.04', 'Wrong OS')
    require(host.get('fresh_job') is True, 'Dedicated fresh job required')
    require(host.get('mem_available', 0) >= 4 * GIB, 'Need 4 GiB available before launch')
    require(host.get('memory_events_oom') == 0 and host.get('memory_events_oom_kill') == 0, 'Prior OOM; do not launch')
    require(host.get('container_count') == 0, 'Unexpected containers; do not clean them')


def create_args(image, token):
    require(re.fullmatch(r'[0-9a-f]{32}', token), 'Unique random owner token required')
    require(re.fullmatch(r'mcr\.microsoft\.com/playwright:v\d+\.\d+\.\d+-noble@sha256:[0-9a-f]{64}', image), 'Invalid pinned image')
    # Adapter must add fixed reviewed mounts, workdir/user and command, never secrets
    # or a docker socket. No --privileged, host network/ipc, sandbox bypass or sysctl.
    return ['docker', 'create', '--name', 'rts-web-qa-' + token,
            '--label', 'rts.webqa.owner=' + token,
            '--network=none', '--memory=3g', '--memory-swap=3g',
            '--pids-limit=256', '--cpus=2', '--shm-size=256m',
            '--init', '--log-driver=local', '--log-opt=max-size=1m',
            '--log-opt=max-file=1', image]


def check_owner(container_id, token, inspected):
    require(re.fullmatch(r'[0-9a-f]{64}', container_id), 'Full exact container ID required')
    require(inspected.get('Id') == container_id, 'Container identity mismatch')
    require(inspected.get('Config', {}).get('Labels', {}).get('rts.webqa.owner') == token, 'Container owner mismatch')


def cleanup_owned(container_id, token, inspect, stop, kill, remove, exists):
    """Callbacks only. Adapter must impose per-call timeouts and preserve failures.

    An uncertain create response MUST be resolved by name+label inspection before
    this function is called. Never search/kill host PIDs, container groups or images.
    """
    record = inspect(container_id)
    check_owner(container_id, token, record)
    if record.get('State', {}).get('Running'):
        stop(container_id, 3)
        record = inspect(container_id)
        check_owner(container_id, token, record)
        if record.get('State', {}).get('Running'):
            kill(container_id)
            record = inspect(container_id)
            check_owner(container_id, token, record)
            require(not record.get('State', {}).get('Running'), 'Owned container still running')
    remove(container_id)
    require(not exists(container_id), 'Cleanup unverified')


def abort_reason(elapsed_seconds, host_mem_available, original_oom, current_oom, container_state):
    if elapsed_seconds >= 120:
        return '120-second runtime limit'
    if host_mem_available < GIB:
        return 'Host reserve below 1 GiB'
    if original_oom != current_oom or container_state.get('OOMKilled'):
        return 'OOM event changed'
    return None
