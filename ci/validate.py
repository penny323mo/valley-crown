from pathlib import Path
import argparse,json,hashlib,re
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('report',type=Path);a=p.parse_args()
build="unknown"
names=['start owns guidance','cancel retires immediately','repeat cancel stays retired','army selection retires','home selection retires','valid preview owns guidance','valid preview retires','invalid preview owns guidance','invalid preview retires']+['ordinary feedback preserved '+s for s in ['建造完成。','資源不足，未有扣款。','已取消指令。']]+['confirm rejection ordinary','confirm rejection preserved','submit authority rejection preserved','rejected confirm still retires mode','ordinary expiry unchanged','guidance expiry hides','reentry owns fresh guidance','economy and tick unchanged']
errors=[]
def require(ok,label):
 if not ok: errors.append(label)
sha=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
try:
 r=json.loads(a.report.read_text()); build=re.search(r'const BUILD_ID = "([^"]+)"',(a.root/'scripts/rules.gd').read_text())[1]
 lock_path=Path(__file__).with_name('source_lock.json'); lock=json.loads(lock_path.read_text())
 require(build==lock['build'],'expected build')
 require(len(lock['files'])==192,'source lock count')
 actual={p.relative_to(a.root).as_posix() for p in a.root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts}
 require(actual==set(lock['files']),'exact source set')
 for path,digest in lock['files'].items(): require(sha(a.root/path)==digest,'source hash '+path)
 require(r['build']==build,'report build')
 require(r['game_sha256']==sha(a.root/'scripts/game.gd'),'game hash')
 require(r['manifest_sha256']==sha(a.root/'reports/build-manifest.json'),'manifest hash')
 require(r['contract_sha256']==sha(Path(__file__).with_name('contract.gd')),'contract hash')
 require(r['source_lock_sha256']==sha(lock_path),'source lock hash')
 require([c['name'] for c in r['checks']]==names,'ordered exact20 rows')
 require(all(c['pass'] is True for c in r['checks']),'all true')
 require(r['completed'] is True and type(r['failed']) is int and r['failed']==0,'completion')
except Exception as e: errors.append(type(e).__name__)
print(json.dumps({'status':'FAIL' if errors else 'PASS','build':build,'expected_checks':20,'errors':errors}))
raise SystemExit(bool(errors))
