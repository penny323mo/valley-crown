"""Inert negative tests. No subprocess, engine, metrics or supervisor call."""
import importlib.util,json,sys,tempfile
from pathlib import Path
HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE))
import run_full_match as a
checks=[]
def rejected(name,fn):
 try: fn()
 except (ValueError,RuntimeError,AssertionError): checks.append(name);return
 raise AssertionError('Accepted '+name)
lock={'full_match_reviewed_for_execution':False,'full_match_supervisor_sha256':a.LOGIC_SHA,'full_match_harness_sha256':a.HARNESS_SHA,'full_match_validator_sha256':a.VALIDATOR_SHA}
rejected('disabled gate',lambda:a.validate_gate(lock))
lock['full_match_reviewed_for_execution']=True
a.validate_gate(lock);checks.append('exact gate')
for key in ('full_match_supervisor_sha256','full_match_harness_sha256','full_match_validator_sha256'):
 bad=dict(lock);bad[key]='0'*64
 rejected('wrong '+key,lambda:a.validate_gate(bad))
rejected('arbitrary script name',lambda:a.argv(Path('/g'),Path('/p'),Path('/evil.gd'),Path('/o'),'x'))
argv=a.argv(Path('/g'),Path('/p'),Path('/ci/full_match.gd'),Path('/o'),'build')
assert argv[-3:]==['--','/o/full-match-report.json','build'];checks.append('fixed report argv')
report={'schema':'vc-normal-full-match-v1','passed':False,'build':'build','game_sha256':'game','rules_sha256':'rules','stop_reason':'bounded_100s_wall_incomplete','phases':{'cargo_deposited':200},'events':[],'commands':[],'engine_time_scale':1,'wall_seconds':100,'policy_version':'ordinary-policy-v2','final_public_records':[],'public_samples':[]}
source={'build':'build','project_files':{'scripts/game.gd':'game','scripts/rules.gd':'rules'}}
with tempfile.TemporaryDirectory() as td:
 path=Path(td)/a.REPORT
 path.write_text(json.dumps(report));assert a.read_report(path,source)['passed'] is False;checks.append('partial remains false')
 rejected('partial cannot validate as pass',lambda:a.v.validate(report))
 for name,payload in [('duplicates','{"x":1,"x":2}'),('NaN','{"x":NaN}'),('Infinity','{"x":Infinity}'),('exponent overflow','{"x":1e999}'),('oversized',' '* (4*1024*1024+1)),('empty','')]:
  path.write_text(payload);rejected(name,lambda:a.read_report(path,source))
 for name,key,value in [('wrong build','build','bad'),('wrong source','game_sha256','bad'),('missing stop reason','stop_reason',''),('wrong timescale','engine_time_scale',2)]:
  bad=dict(report);bad[key]=value;path.write_text(json.dumps(bad));rejected(name,lambda:a.read_report(path,source))
for name,key,value in [('wrong policy','policy_version','old'),('missing final observations','final_public_records',None),('oversized samples','public_samples',[{}]*65),('oversized commands','commands',[{}]*2049)]:
 with tempfile.TemporaryDirectory() as td:
  path=Path(td)/a.REPORT;bad=dict(report);bad[key]=value;path.write_text(json.dumps(bad));rejected(name,lambda:a.read_report(path,source))
source_text=(HERE/'run_full_match.py').read_text()
assert source_text.count('logic.supervise(')==1
assert "receipt['passed']=True" in source_text and source_text.index("receipt['validation']=v.validate(report)")<source_text.index("receipt['passed']=True")
assert source_text.index("report=read_report(stage/REPORT,lock)")<source_text.index("p.require(result['passed']")
checks.append('single child and partial-before-failure gate')
print(json.dumps({'passed':True,'checks':checks,'engine_run':False,'monitor_run':False,'resource_polling':False}))
