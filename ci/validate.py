from pathlib import Path
import argparse, hashlib, json, re
p=argparse.ArgumentParser(); p.add_argument('--root',type=Path,required=True); p.add_argument('report',type=Path); a=p.parse_args()
errors=[]; build="unknown"
sha=lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
def require(ok,label):
 if not ok: errors.append(label)
names=['successful authority release creates exactly one cue', 'cooldown failure and exact replay cannot duplicate cue', 'running cue consumes only visual elapsed time', 'gameplay pause cannot expire cue via independent tween', 'background focus freezes cue age', 'suspension freezes cue age', 'first stale focus-return frame is discarded by actual process', 'target motion cannot move or retarget release cue', 'resume retires cue after original bounded visual lifetime', 'presentation cannot settle or mutate combat state', 'expired node is actually freed', 'exploration memory does not retain a cue while paused', 'reappearance cannot replay a revoked cue', 'hidden target suppresses creation', 'hidden attacker suppresses creation', 'enemy origin losing vision revokes cue', 'real tick settles lethal attack while retaining frozen witnessed cue', 'repeated cleanup is safe and immediately hides nodes', 'burst is bounded by match population and hides evicted node', 'terminal state clears all effects without aging', 'terminal state rejects fresh visual effects', 'burst eviction and terminal cleanup free every node', 'reset removes effect ownership and hides old node', 'reset frees old cue node', 'scene exit clears effect registry and hides cue']
try:
 require(a.report.stat().st_size<=32768,'bounded report')
 r=json.loads(a.report.read_text()); root=a.root
 fixture=Path(__file__).resolve().parent
 lock=json.loads((fixture/'source_lock.json').read_text())
 build=re.search(r'const BUILD_ID = "([^"]+)"',(root/'scripts/rules.gd').read_text())[1]
 require(build==lock['build']==r['build'],'build binding')
 actual={p.relative_to(root).as_posix() for p in root.rglob('*') if p.is_file() and '.godot' not in p.parts and '__pycache__' not in p.parts}
 require(len(lock['files'])==192 and len(lock['imported_extras'])==5,'expected source counts')
 require(not (set(lock['files']) & set(lock['imported_extras'])),'disjoint source sets')
 require(actual==set(lock['files'])|set(lock['imported_extras']),'exact imported source set')
 for path,digest in (lock['files']|lock['imported_extras']).items(): require(sha(root/path)==digest,'source hash '+path)
 require(r['game_sha256']==sha(root/'scripts/game.gd'),'game binding')
 require(r['manifest_sha256']==sha(root/'reports/build-manifest.json'),'manifest binding')
 require(r['contract_sha256']==sha(fixture/'contract.gd'),'contract binding')
 require(r['source_lock_sha256']==sha(fixture/'source_lock.json'),'lock binding')
 require([c['name'] for c in r['checks']]==names,'ordered exact checks')
 require(all(set(c)=={'name','pass'} and c['pass'] is True for c in r['checks']),'all strict true')
 require(r['completed'] is True and type(r['failed']) is int and r['failed']==0,'completion')
 require(type(r['passed']) is int and r['passed']==len(names),'passed count')
 require(set(r['source_sha256'])=={'scripts/game.gd','scripts/attack_ledger.gd','scripts/rules.gd'},'source report fields')
 for path,digest in r['source_sha256'].items(): require(sha(root/path)==digest,'report source hash '+path)
 require(r['engine']['major']==4 and r['engine']['minor']==6 and r['engine']['patch']==3,'engine version')
except Exception as e: errors.append(type(e).__name__)
print(json.dumps({'status':'FAIL' if errors else 'PASS','build':build,'expected_checks':len(names),'errors':errors}))
raise SystemExit(bool(errors))
