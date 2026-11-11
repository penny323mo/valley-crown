"""Inert AST/text checks; no browser, service, resource probe or subprocess."""
import ast
import json
from pathlib import Path
import unittest
HERE=Path(__file__).resolve().parent
class MetadataPreflight(unittest.TestCase):
    def test_only_ownership_metadata_lookup_has_fifteen_second_bound(self):
        source=(HERE/'prepare_browser_qa.py').read_text()
        calls=[n for n in ast.walk(ast.parse(source)) if isinstance(n,ast.Call) and isinstance(n.func,ast.Attribute) and n.func.attr=='check_output']
        self.assertEqual(len(calls),2)
        bounds={}
        for call in calls:
            command=call.args[0].elts
            self.assertEqual(ast.literal_eval(command[0]),'/usr/bin/dpkg-query')
            mode=ast.literal_eval(command[1]);bounds[mode]=ast.literal_eval(next(k.value for k in call.keywords if k.arg=='timeout'))
        self.assertEqual(bounds,{'-S':15,'-W':5})
        self.assertIn("owner == 'google-chrome-stable: /opt/google/chrome/chrome'",source)
        self.assertIn('chrome_sha256=sha(chrome)',source)
    def test_unchanged_process_security_time_and_resource_limits(self):
        guard=(HERE/'run_host_browser.py').read_text()
        for setting in ['--property=MemoryMax=3G','--property=MemorySwapMax=0','--property=TasksMax=256','--property=CPUQuota=200%',
          '--property=RuntimeMaxSec=100','--property=TimeoutStopSec=5','--property=KillMode=control-group',"'supervisor_cleanup_seconds':105"]:self.assertIn(setting,guard)
        host=(HERE/'host_main.mjs').read_text();self.assertIn('Math.min(90000,',host);self.assertIn('chromiumSandbox:true',host)
        scenario=(HERE/'browser_qa.mjs').read_text();self.assertIn('Date.now()-started<70000',scenario);self.assertIn('exceeded5000ms',scenario)
    def test_one_diagnostic_job_and_attempt_gate(self):
        workflow=(HERE.parent.parent/'.github/workflows/public-web-browser.yml').read_text()
        self.assertEqual(workflow.count('fixture: menu390'),1)
        for other in ['fixture: menu320','fixture: menu844','fixture: menu1440']:self.assertNotIn(other,workflow)
        self.assertIn('if: ${{ github.run_attempt == 1 }}',workflow)
        self.assertIn('qa/test_initial_geometry_diagnostic.mjs',workflow)
        source=(HERE/'browser_qa.mjs').read_text()
        self.assertLess(source.index("throw new Error('DIAGNOSTIC_ONLY:"),source.index('let current=await observe();requireHome(current);'))
if __name__=='__main__':unittest.main()
