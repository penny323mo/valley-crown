"""Fake-file preflight only: no subprocess, Chrome, systemd or resource reads."""
import unittest
from unittest.mock import patch
from run_host_browser import verify_chrome

class NodePreflight(unittest.TestCase):
    def test_exact_observed_local_node(self):
        digest = '94efd062ed066c1a0b332e18249859c905e920eeada5df55d24c99b919629a90'
        lock = {'chrome_path': '/opt/google/chrome/chrome', 'chrome_sha256': '11' * 32, 'chrome_version': '156.0.8078.79-1', 'node_path': '/usr/local/bin/node', 'node_sha256': digest}
        def fake_sha(path):
            return bytes.fromhex(lock['chrome_sha256'] if str(path) == lock['chrome_path'] else digest)
        with patch('pathlib.Path.is_file', return_value=True), patch('pathlib.Path.is_symlink', return_value=False), patch('run_host_browser.sha', side_effect=fake_sha):
            verify_chrome(lock)
            lock['node_sha256'] = '00' * 32
            with self.assertRaises(ValueError):
                verify_chrome(lock)
            lock['node_sha256'] = digest
            lock['node_path'] = '/tmp/node'
            with self.assertRaises(ValueError):
                verify_chrome(lock)
        lock['node_path'] = '/usr/local/bin/node'
        with patch('pathlib.Path.is_file', return_value=True), patch('pathlib.Path.is_symlink', return_value=False), patch('run_host_browser.sha', return_value=bytes.fromhex('11' * 32)):
            with self.assertRaisesRegex(ValueError, 'Node executable changed'):
                verify_chrome(lock)

if __name__ == '__main__':
    unittest.main()
