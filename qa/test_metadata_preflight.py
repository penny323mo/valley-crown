"""Inert source-contract checks; never invoke package tools or a browser."""
import ast
from pathlib import Path
import unittest

HERE = Path(__file__).resolve().parent


class MetadataPreflight(unittest.TestCase):
    def test_only_ownership_metadata_lookup_has_fifteen_second_bound(self):
        source = (HERE / 'prepare_browser_qa.py').read_text()
        calls = [node for node in ast.walk(ast.parse(source)) if isinstance(node, ast.Call)
                 and isinstance(node.func, ast.Attribute) and node.func.attr == 'check_output']
        self.assertEqual(len(calls), 2)
        bounds = {}
        for call in calls:
            command = call.args[0].elts
            self.assertEqual(ast.literal_eval(command[0]), '/usr/bin/dpkg-query')
            mode = ast.literal_eval(command[1])
            bounds[mode] = ast.literal_eval(next(k.value for k in call.keywords if k.arg == 'timeout'))
            if mode == '-S':
                self.assertEqual(ast.unparse(command[2]), 'str(chrome)')
                self.assertEqual(len(command), 3)
            elif mode == '-W':
                self.assertEqual([ast.literal_eval(x) for x in command], ['/usr/bin/dpkg-query', '-W', '-f=${Version}', 'google-chrome-stable'])
        self.assertEqual(bounds, {'-S': 15, '-W': 5})
        self.assertIn("owner == 'google-chrome-stable: /opt/google/chrome/chrome'", source)
        self.assertIn('chrome_sha256=sha(chrome)', source)

    def test_browser_limits_and_desktop_only_followup(self):
        guard = (HERE / 'run_host_browser.py').read_text()
        for setting in ['--property=MemoryMax=3G', '--property=MemorySwapMax=0', '--property=TasksMax=256',
                        '--property=CPUQuota=200%', '--property=RuntimeMaxSec=100', '--property=TimeoutStopSec=5',
                        '--property=KillMode=control-group']:
            self.assertIn(setting, guard)
        host = (HERE / 'host_main.mjs').read_text()
        self.assertIn('Math.min(90000,', host)
        self.assertIn('chromiumSandbox:true', host)
        workflow = (HERE.parent / '.github/workflows/public-web-browser.yml').read_text()
        self.assertIn('profile: [desktop]', workflow)
        self.assertNotIn('profile: [desktop, portrait]', workflow)


if __name__ == '__main__': unittest.main()
