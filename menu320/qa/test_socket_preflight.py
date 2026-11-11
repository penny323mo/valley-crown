"""Pure path checks only: no filesystem access, service or browser launch."""
from pathlib import Path
import unittest
from run_host_browser import verify_socket_path_budget


class SocketPreflight(unittest.TestCase):
    def test_actual_failed_long_root_rejected(self):
        with self.assertRaises(ValueError):
            verify_socket_path_budget(Path('/home/runner/work/_temp/current-web-qa-42965678809-1-desktop/evidence'))

    def test_short_owned_roots_fit_both_profiles(self):
        for profile in ('desktop', 'portrait'):
            result = verify_socket_path_budget(Path('/home/runner/work/_temp/q-42965678809-1-' + profile[0] + '/evidence'))
            self.assertLessEqual(result['reserved_socket_path_bytes'], 107)

    def test_exact_limit_and_byte_not_character_count(self):
        suffix = '/tmp/com.google.Chrome.' + 'X' * 16 + '/SingletonSocket'
        room = 107 - len(suffix.encode()) - 1
        result = verify_socket_path_budget(Path('/' + 'a' * room))
        self.assertEqual(result['reserved_socket_path_bytes'], 107)
        with self.assertRaises(ValueError): verify_socket_path_budget(Path('/' + 'a' * (room + 1)))
        with self.assertRaises(ValueError): verify_socket_path_budget(Path('/' + 'a' * (room - 1) + '界'))


if __name__ == '__main__': unittest.main()
