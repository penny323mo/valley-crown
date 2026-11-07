"""Exact source-bound native contract gate; no gameplay simulation."""
import argparse, hashlib, json
from pathlib import Path
HERE=Path(__file__).resolve().parent
BUILD='vc-f605f947768e'
SCOPE='Native method/state integration at 390x844; controlled pointer-handler calls; not GUI dispatch, render, physical phone, or full-match acceptance'
SUFFIXES=['preview_setup','menu_preserves_preview','selection_and_menu','mode_cleared','pointer_quarantined','ghost_retired','normal_actions','no_economic_or_authority_changes']
EXPECTED=['identity:build','identity:game_source']+[f'{case}:{held}:{s}' for case,held in [(c,'held') for c in ['army','scout','home','empty','same','different']]+[('scout','unheld')] for s in SUFFIXES]+['negative:menu_close_reopen_preserves_preview','negative:ordinary_selection_preserves_pointer','confirm:preview_setup','confirm:original_builder_queued','confirm:preview_cleared','confirm:authority_paid_site','paid_site:fresh_preview','paid_site:selection_does_not_cancel','paid_site:stale_confirm_is_noop']
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def pairs(items):
 d={}
 for k,v in items:
  if k in d: raise ValueError('Duplicate JSON key')
  d[k]=v
 return d
def read(p): return json.loads(p.read_text(),object_pairs_hook=pairs,parse_constant=lambda _: (_ for _ in ()).throw(ValueError('Nonfinite JSON')))
def validate(root, report):
 errors=[]
 def need(ok,name):
  if not ok: errors.append(name)
 need(type(report) is dict,'report object')
 if not isinstance(report,dict): return errors
 lock=read(HERE/'source_lock.json')
 need(len(lock)==192,'source inventory192')
 for name,digest in lock.items():
  p=root/name
  need(p.is_file() and not p.is_symlink() and sha(p)==digest,'source:'+name)
 manifest=read(root/'reports/build-manifest.json')
 need(manifest['build']==BUILD and len(manifest['source_sha256'])==122,'runtime122 identity')
 need(all(lock.get(n)==h for n,h in manifest['source_sha256'].items()),'runtime source lock')
 expected_fields={'schema':1,'suite':'selection_preview_cancel_native','build':BUILD,'scope':SCOPE,'game_sha256':lock['scripts/game.gd'],'runtime_manifest_sha256':lock['reports/build-manifest.json'],'contract_sha256':sha(HERE/'contract.gd'),'source_lock_sha256':sha(HERE/'source_lock.json')}
 need(set(report)==set(expected_fields)|{'checks','passed','failed'},'exact report keys')
 for name,value in expected_fields.items(): need(type(report.get(name)) is type(value) and report.get(name)==value,'field:'+name)
 checks=report.get('checks')
 need(type(checks) is list,'check list')
 if not isinstance(checks,list): return errors
 need(len(checks)==len(EXPECTED)==67,'exact67 checks')
 need(all(type(row) is dict and set(row)=={'name','pass'} for row in checks),'exact row schema')
 need([row.get('name') if isinstance(row,dict) else None for row in checks]==EXPECTED,'exact ordered names')
 need(all(isinstance(row,dict) and row.get('pass') is True for row in checks),'every check passes')
 need(type(report.get('passed')) is int and report['passed']==67,'passed count')
 need(type(report.get('failed')) is int and report['failed']==0,'failed count')
 return errors
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('report',type=Path);a=p.parse_args()
 try:
  if a.report.is_symlink() or a.report.stat().st_size>131072: raise ValueError('Unsafe/oversize report')
  errors=validate(a.root.resolve(),read(a.report))
 except (OSError,KeyError,ValueError,TypeError) as exc: errors=['malformed or unavailable evidence: '+type(exc).__name__]
 print(json.dumps({'status':'PASS' if not errors else 'FAIL','build':BUILD,'expected_checks':67,'errors':errors[:12]},sort_keys=True))
 raise SystemExit(1 if errors else 0)
