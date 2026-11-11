"""Inert source/metadata contracts; never launches Node, Chrome or Godot."""
from pathlib import Path
import json
import re
import unittest
HERE=Path(__file__).resolve().parent
class SplitScopes(unittest.TestCase):
 def test_exact_split_binding(self):
  m=json.loads((HERE/'scenario-manifest.json').read_text());s=(HERE/'browser_qa.mjs').read_text();b=(HERE/'validate_construction_binding.py').read_text()
  self.assertIn("PREPARED_SCENARIO = "+repr(m['scenario']),s)
  self.assertIn("PREPARED_SCENARIO = "+repr(m['scenario']),b)
  self.assertIn("COVERAGE_SCOPE = "+repr(m['coverage_scope']),s)
  self.assertEqual(m['viewport'],[390,844]);self.assertEqual(m['profile'],'portrait')
  self.assertEqual(json.loads((HERE/'expected-export.json').read_text())['artifact_id'],13854909658)
 def test_small_fixed_interaction_scope(self):
  m=json.loads((HERE/'scenario-manifest.json').read_text());s=(HERE/'browser_qa.mjs').read_text();body=s[s.index('    let current=await observe();requireHome(current);'):]
  calls=re.findall(r"await dragStrip\('([^']+)'(?:,([A-Z_]+))?\)",body)
  scope=m['coverage_scope'];expected={'producer-direct':1,'palette-first':1,'palette-last':3}[scope]
  self.assertEqual(len(calls),expected)
  self.assertEqual(body.count("await activate(worker.screen,'select-natural-worker')"),1)
  if scope=='producer-direct':
   self.assertEqual(calls,[('producer-strip-1','')]);self.assertIn("const gesture=async(points,label,steps=6)",s)
   for label in ['direct-ground-order-no-command-overlay','direct-resource-order-no-command-overlay','villager-queued-real-debit-reservation']:self.assertIn(label,body)
   self.assertLess(body.index("await dragStrip('producer-strip-1')"),body.index("await activate(worker.screen"))
   self.assertNotIn('palette-return',body)
  else:
   self.assertTrue(all(steps=='PALETTE_TOUCH_MOVE_STEPS' for _,steps in calls))
   self.assertIn('PALETTE_TOUCH_MOVE_STEPS = 2;',s)
   self.assertNotIn('beforeTrain',body)
   self.assertIn('recordPair(0)',body)
  self.assertIn("assert.equal(evidence.screenshots.length,"+('1' if scope=='producer-direct' else '2'),body)
  self.assertIn("assert.equal(r[2],100,'Full actual100px button required')",s)
  self.assertNotIn('scroll_horizontal=',body)
 def test_terminal_and_existing_caps(self):
  s=(HERE/'browser_qa.mjs').read_text()
  for marker in ['Date.now()-started<70000','exceeded5000ms',"assert.equal(evidence.error_count,0,'Browser errors during context close')",'assertPublicStreamCompletions(evidence.network.records,origin)',"evidence.basicSmokePassed=true;await checkpoint('completed')",'releaseQAPassed:false,visualAcceptancePassed:false']:
   self.assertIn(marker,s)
if __name__=='__main__':unittest.main()
