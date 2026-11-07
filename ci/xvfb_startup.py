"""Bound the observed Ubuntu Xvfb keyboard compiler during startup only.

No processes are launched here. Normal Godot capture has no helper exemption.
"""
from pathlib import Path
import hashlib
import os
import re
import select
from types import SimpleNamespace

EXPECTED = {'xvfb': ('/usr/bin/Xvfb', 'xvfb'),
            'dash': ('/usr/bin/dash', 'dash'),
            'xkbcomp': ('/usr/bin/xkbcomp', 'x11-xkb-utils')}


def need(ok, message):
    if not ok:
        raise RuntimeError(message)


def sha(path):
    with Path(path).open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def root_regular(path):
    path = Path(path)
    info = path.lstat()
    need(path.is_file() and not path.is_symlink() and info.st_uid == 0
         and not info.st_mode & 0o6022, 'Untrusted distribution file: ' + str(path))
    return path


def distribution_inventory():
    """Verify apt-installed package files, then bind their SHA256 for this run.

    The workflow installs these exact package names from Ubuntu. Dpkg MD5s are
    installation-integrity checks, not a replacement for apt signature trust.
    No package manager command or subprocess is executed by this function.
    """
    status_path = root_regular('/var/lib/dpkg/status')
    statuses = {}
    for paragraph in status_path.read_text().split('\n\n'):
        fields = dict(line.split(': ', 1) for line in paragraph.splitlines()
                      if ': ' in line and not line.startswith(' '))
        if fields.get('Package') in {package for path, package in EXPECTED.values()}:
            statuses[fields['Package']] = fields
    result = {}
    for role, (name, package) in EXPECTED.items():
        binary = root_regular(name)
        need(binary.resolve() == binary, 'Distribution binary path was redirected')
        entry = statuses.get(package, {})
        need(entry.get('Status') == 'install ok installed' and entry.get('Architecture') == 'amd64',
             'Required Ubuntu package is not installed for amd64: ' + package)
        version = entry.get('Version', '')
        need(re.fullmatch(r'[A-Za-z0-9.+:~\-]{1,80}', version), 'Invalid package version')
        candidates = [Path('/var/lib/dpkg/info') / (package + suffix + '.md5sums')
                      for suffix in ('', ':amd64')]
        metadata = [root_regular(path) for path in candidates if path.exists()]
        need(len(metadata) == 1, 'Ambiguous/missing installed package metadata')
        rows = [line.split() for line in metadata[0].read_text().splitlines()]
        matches = [md5 for md5, rel in rows if rel in (name.lstrip('/'), name.removeprefix('/usr/'))]
        need(len(matches) == 1 and re.fullmatch(r'[0-9a-f]{32}', matches[0]), 'Binary missing from package checksum list')
        with binary.open('rb') as stream:
            installed = hashlib.file_digest(stream, 'md5').hexdigest()
        need(installed == matches[0], 'Installed binary differs from its package: ' + package)
        result[role] = {'path': name, 'package': package, 'version': version,
                        'sha256': sha(binary), 'package_metadata_sha256': sha(metadata[0])}
    need(Path('/bin/sh').resolve() == Path('/usr/bin/dash'), 'Ubuntu /bin/sh is not the reviewed dash')
    return result


class StartupTree:
    """At most one observed dash -> xkbcomp pair, before Xvfb readiness only."""
    def __init__(self, owner, inventory, api, receipt, tracked):
        self.owner, self.inventory, self.api = owner, inventory, api
        self.receipt, self.tracked = receipt, tracked
        self.bound = {}
        self.owner_identity = None
        self.seen = False
        self.complete = False
        self.visited = set()

    def executable(self, pid, role):
        expected = self.inventory[role]
        proc_exe = Path('/proc') / str(pid) / 'exe'
        need(os.readlink(proc_exe) == expected['path'], 'Startup helper executable path differs')
        need(sha(proc_exe) == expected['sha256'], 'Startup helper executable hash differs')

    def visit(self, pid, parent, role):
        need(role in ('dash', 'xkbcomp'), 'Unreviewed startup helper role')
        self.visited.add(pid)
        existing = self.bound.get(pid)
        if existing:
            need(not select.select([existing['fd']], [], [], 0)[0], 'Exited startup PID reappeared in live child list')
        first = self.api.process_identity(pid)
        need(first['ppid'] == parent['pid'] and self.api.same_lifetime(self.api.process_identity(parent['pid']), parent),
             'Startup helper ancestry/lifetime differs')
        self.executable(pid, role)
        second = self.api.process_identity(pid)
        need(self.api.same_lifetime(first, second) and second['ppid'] == parent['pid'], 'Startup identity changed during executable check')
        if existing:
            need(existing['role'] == role and self.api.same_lifetime(first, existing['identity']), 'Startup PID reused or role changed')
        else:
            need(len(self.bound) < 2 and not any(item['role'] == role for item in self.bound.values()),
                 'More than the reviewed single startup compiler pair')
            fd = os.pidfd_open(pid, 0)
            item = {'fd': fd, 'identity': first, 'parent': 'xvfb', 'role': role}
            # Transfer ownership immediately: even later validation errors close it.
            self.tracked.append(item)
            self.bound[pid] = item
            rebound = self.api.process_identity(pid)
            need(self.api.same_lifetime(first, rebound) and rebound['ppid'] == parent['pid'] and not select.select([fd], [], [], 0)[0],
                 'Startup helper exited/changed while binding pidfd')
            record = {'role': role, 'identity': first, 'executable_sha256': self.inventory[role]['sha256'],
                      'sampled_peak_rss_kib': 0, 'sampled_peak_hwm_kib': 0, 'sampled_peak_threads': 0}
            item['record'] = record
            self.receipt['helpers'].append(record)
        row = self.api.process_metrics(SimpleNamespace(pid=pid))
        record = self.bound[pid]['record']
        record['sampled_peak_rss_kib'] = max(record['sampled_peak_rss_kib'], row['VmRSS'])
        record['sampled_peak_hwm_kib'] = max(record['sampled_peak_hwm_kib'], row['VmHWM'])
        record['sampled_peak_threads'] = max(record['sampled_peak_threads'], row['Threads'])
        need(row['VmRSS'] <= 131072 and row['VmHWM'] <= 131072 and row['Threads'] <= 4,
             'Startup helper resource limit')
        children = row['child_pids']
        need(len(children) <= (1 if role == 'dash' else 0), 'Unexpected child below startup compiler')
        total = row['VmRSS']
        if children:
            total += self.visit(int(children[0]), first, 'xkbcomp')
        return total

    def sample(self, pids):
        need(not self.complete, 'Startup helper allowance is closed')
        need(self.owner.poll() is None, 'Xvfb exited during startup')
        need(len(pids) <= 1, 'Multiple Xvfb startup children')
        self.visited = set()
        if not pids:
            for item in self.bound.values():
                need(select.select([item['fd']], [], [], 0)[0], 'Bound startup helper left the owned tree while live')
            return 0
        self.seen = True
        # Record detection before all fallible proc/hash/descriptor operations.
        self.receipt['detected'] = True
        self.receipt['detected_pids'] = [str(pid) for pid in pids[:1]]
        if self.owner_identity is None:
            self.owner_identity = self.api.process_identity(self.owner.pid)
            self.executable(self.owner.pid, 'xvfb')
        need(self.api.same_lifetime(self.owner_identity, self.api.process_identity(self.owner.pid)), 'Xvfb startup lifetime changed')
        total = self.visit(int(pids[0]), self.owner_identity, 'dash')
        for pid, item in self.bound.items():
            if pid not in self.visited:
                need(select.select([item['fd']], [], [], 0)[0], 'Bound startup helper left the owned tree while live')
        return total

    def finish(self):
        # Readiness is emitted after Pclose and device initialization. Every
        # observed helper must have exited on its bound lifetime before Godot.
        for item in self.bound.values():
            need(select.select([item['fd']], [], [], 0)[0], 'Startup helper alive at Xvfb readiness')
        need(not self.seen or {item['role'] for item in self.bound.values()} == {'dash', 'xkbcomp'},
             'Observed startup compiler chain was incomplete')
        self.complete = True
        for item in self.bound.values():
            item['record']['exit_confirmed_before_engine'] = True
        self.receipt['complete'] = True
