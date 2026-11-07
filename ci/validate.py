from pathlib import Path
import argparse,json,hashlib,re,math
p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('report',type=Path);a=p.parse_args()
build="unknown"
names=['start owns guidance','cancel retires immediately','repeat cancel stays retired','army selection retires','home selection retires','valid preview legal premise','valid preview owns guidance','valid preview retires','invalid preview owns guidance','invalid preview retires']+['ordinary feedback preserved '+s for s in ['建造完成。','資源不足，未有扣款。','已取消指令。']]+['confirm rejection ordinary','confirm rejection preserved','terminal submit legal premise','submit authority rejection preserved','rejected confirm still retires mode','ordinary expiry unchanged','guidance expiry hides','reentry owns fresh guidance','economy and tick unchanged']
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
 require(len(lock['imported_extras'])==5 and not (set(lock['files']) & set(lock['imported_extras'])),'import extra count')
 require(actual==set(lock['files'])|set(lock['imported_extras']),'exact imported source set')
 for path,digest in lock['imported_extras'].items(): require(sha(a.root/path)==digest,'import extra hash '+path)
 for path,digest in lock['files'].items(): require(sha(a.root/path)==digest,'source hash '+path)
 require(r['build']==build,'report build')
 require(r['game_sha256']==sha(a.root/'scripts/game.gd'),'game hash')
 require(r['manifest_sha256']==sha(a.root/'reports/build-manifest.json'),'manifest hash')
 require(r['contract_sha256']==sha(Path(__file__).with_name('contract.gd')),'contract hash')
 require(r['source_lock_sha256']==sha(lock_path),'source lock hash')
 require([c['name'] for c in r['checks']]==names,'ordered exact22 rows')
 require(all(c['pass'] is True for c in r['checks']),'all true')
 require(r['completed'] is True and type(r['failed']) is int and r['failed']==0,'completion')
 premises=r['premises']
 require(type(premises) is list and len(premises)==2,'two legal premises')
 plots=[[-29,0,23],[-21,0,23],[-25,0,28],[-21,0,28],[-31,0,23]]
 for row,name in zip(premises,['valid preview legal premise','terminal submit legal premise']):
  require(set(row)=={'name','initial_reason','selected_reason','found','examined','builder','position','legal'},'premise fields')
  require(row['name']==name and row['found'] is True and row['legal'] is True and row['selected_reason']=='','legal premise verdict')
  require(type(row['initial_reason']) is str and len(row['initial_reason'])<=128,'bounded initial reason')
  require(type(row['builder']) is int and 1<=row['builder']<=5,'owned builder identity')
  require(type(row['examined']) is int and 1<=row['examined']<=len(plots),'bounded public plot search')
  pos=row['position'];require(type(pos) is list and len(pos)==3 and all(type(v) in (int,float) and math.isfinite(v) for v in pos),'finite plot')
  if type(row['examined']) is int and 1<=row['examined']<=len(plots):require(pos==plots[row['examined']-1],'source-bound public plot')

except Exception as e: errors.append(type(e).__name__)
print(json.dumps({'status':'FAIL' if errors else 'PASS','build':build,'expected_checks':22,'errors':errors}))
raise SystemExit(bool(errors))
