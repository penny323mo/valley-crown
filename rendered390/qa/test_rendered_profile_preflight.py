"""Pure mechanical profile and closed-gate checks. Never starts a process."""
from pathlib import Path
import unittest,json,hashlib,copy,ast
from rendered_profile import validate_profile
HERE=Path(__file__).resolve().parent
class RenderedProfile(unittest.TestCase):
 def test_mechanical_guard_extension(self):
  source=(HERE/'run_host_browser.py').read_text()
  source=source.replace("('1min 40s', '100s')","('7min 50s', '470s')").replace("'systemd_runtime_seconds':100, 'node_runtime_seconds':90","'systemd_runtime_seconds':470, 'node_runtime_seconds':460").replace("'supervisor_cleanup_seconds':105","'supervisor_cleanup_seconds':475").replace('--property=RuntimeMaxSec=100','--property=RuntimeMaxSec=470').replace("'remaining_seconds': 90 -","'remaining_seconds': 460 -").replace('elapsed < 105','elapsed < 475').replace("bundle/'host_main.mjs'","bundle/'host_rendered.mjs'")
  source=source.replace("    lock = read_json(lock_path)\n","    lock = read_json(lock_path)\n    from rendered_profile import validate_profile\n    validate_profile(read_json(bundle/'rendered-profile.json'), bundle)\n",1)
  self.assertEqual(source,(HERE/'run_host_rendered.py').read_text())
  source=(HERE/'host_main.mjs').read_text().replace("from './browser_qa.mjs'","from './browser_rendered.mjs'").replace('Math.min(90000,','Math.min(460000,')
  self.assertEqual(source,(HERE/'host_rendered.mjs').read_text())
 def test_missing_or_changed_profile_is_rejected(self):
  p=json.loads((HERE/'rendered-profile.json').read_text());p['reviewed_for_execution']=True
  p['bound_files_sha256']={n:hashlib.sha256((HERE/n).read_bytes()).hexdigest() for n in ['run_host_rendered.py','host_rendered.mjs','browser_rendered.mjs','rendered_profile.py','capture_handshake.mjs']}
  validate_profile(p,HERE)
  for name in ['reviewed_for_execution','name','product_source','fixture_seconds','scenario_seconds','node_seconds','service_seconds','outer_seconds','snapshot_read_seconds','diagnostic_overlay','bound_files_sha256']:
   bad=copy.deepcopy(p);bad[name]=None
   with self.assertRaises((ValueError,TypeError)):validate_profile(bad,HERE)
 def test_python_syntax(self):
  for p in HERE.glob('*.py'):ast.parse(p.read_text())
if __name__=='__main__':unittest.main()
