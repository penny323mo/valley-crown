"""Lightweight source-bound checks and independent report gates, not a game simulator."""
import copy, hashlib, json, pathlib, sys, unittest
HERE=pathlib.Path(__file__).resolve().parent
PROJECT=HERE.parent/'rts_construction_local_demo_integration/candidate'
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(65536),b''): h.update(b)
    return h.hexdigest()
def validate(report, allow_fixture=False):
    try: return _validate(report, allow_fixture)
    except (KeyError, TypeError, ValueError, AttributeError, IndexError) as exc: return ['malformed report']
def _validate(report, allow_fixture=False):
    errors=[]
    def require(ok,message):
        if not ok: errors.append(message)
    require(not report.get('fixture_only') or allow_fixture,'synthetic fixture is not an actual run')
    require(report.get('failures')==[],'runtime failures')
    require(report.get('source_sha256')==sha(PROJECT/'scripts/game.gd'),'source hash')
    require(report.get('source_lock_sha256')==sha(HERE/'source_lock.json'),'source lock hash')
    require(report.get('harness_sha256')==sha(HERE/'expansion.gd'),'harness hash')
    trace=report.get('input_trace',[])
    require(bool(trace),'ordinary input trace')
    sequences=set()
    for t in trace:
        c=t['command']; actor=t['actor']; target=t['target']
        require(c['type'] in ['order','build','train','defend'] and c['team']==0,'ordinary player commands only')
        require(actor['owned'] and actor['alive'] and not actor['remembered'],'current owned actor')
        require(not target or (target['alive'] and not target['remembered']),'current target')
        require(c['sequence'] not in sequences,'unique command sequence'); sequences.add(c['sequence'])
    require(report.get('status')=='PASS_ONE_SIDE_LOOP','status')
    require(report.get('build')=='vc-43276605e0fb','build')
    require(report.get('economy_audit',{}).get('ok') is True,'conservation')
    events=report.get('events',[])
    def first(kind): return next((e for e in events if e.get('type')==kind),{})
    depletion=first('observed_home_depletion'); discovery=first('forward_discovered')
    site=first('store_paid_site'); built=first('store_completed')
    request=first('replacement_requested'); completed=first('replacement_completed')
    ordered=[depletion,discovery,site,built,request,completed]
    require(all(ordered),'milestones')
    if all(ordered):
        require([e['tick'] for e in ordered]==sorted(e['tick'] for e in ordered),'milestone order')
        require(len(depletion['nodes'])==6 and len(depletion['witnesses'])==6 and all(w['visible'] and w['absent'] for w in depletion['witnesses']) and len({w['id'] for w in depletion['witnesses']})==6,'six observed home nodes')
        require(site['wood_purchase_delta_milli']==80000,'paid 80 wood')
        require(site['record']['id']==built['record']['id'],'same store')
        require(built['record']['built'],'completed store')
        require(not discovery['record']['remembered'] and discovery['record']['alive'] and discovery['record']['kind']=='berry','live food discovery')
        for b in [site['record'],built['record']]: require(b['owned'] and b['alive'] and b['team']==0 and b['kind']=='storehouse','owned live store')
        require(any(t['command']['type']=='build' and t['command'].get('kind')=='storehouse' and t['tick']<site['tick'] for t in trace),'ordinary store command')
        require(any(t['command']['type']=='train' and t['command'].get('kind')=='spearman' and t['tick']==request['tick'] for t in trace),'ordinary replacement command')
        income={'food':0,'wood':0}; deposit_keys=set()
        for e in events:
            if e.get('type')!='forward_store_deposit' or not built['tick']<=e['tick']<=request['tick']: continue
            r=e['transaction']['result']
            require(e['transaction_key'] not in deposit_keys,'unique deposit transaction'); deposit_keys.add(e['transaction_key'])
            require(e['transaction']['signature']==['deposit',e['worker'],r['cargo_revision']],'deposit signature')
            require(e['transaction_key']=='deposit:%d:%d'%(e['worker'],r['cargo_revision']),'deposit key revision')
            require(r['worker_id']==e['worker'],'deposit worker')
            require(0<e['amount_milli']<=10000,'actual cargo capacity')
            depot=e['depot']
            require(depot['id']==e['store'] and depot['kind']=='storehouse' and depot['owned'] and depot['alive'] and depot['built'] and depot['team']==0,'valid actual depot')
            earned=0; last_revision=None; last_cargo=None; last_tick=-1
            for g in e['cargo_evidence']:
                node=g['source']; amount=g['after_milli']-g['before_milli']
                require(node['category']=='resource' and node['alive'] and not node['remembered'] and g['home_distance']>=14,'observed forward extraction')
                require(g['resource']==e['resource'] and ((node['kind']=='berry')==(e['resource']=='food')),'same cargo resource')
                require(0<amount<=40 and 0<=g['before_milli']<g['after_milli']<=10000,'actual gather increment')
                require(g['revision_after']==g['revision_before']+1,'gather revision')
                if last_revision is not None:
                    require(last_revision==g['revision_before'] and last_cargo==g['before_milli'],'contiguous cargo provenance')
                require(last_tick<g['tick']<=e['tick'],'extraction tick order'); last_tick=g['tick']
                earned+=amount; last_revision=g['revision_after']; last_cargo=g['after_milli']
            require(last_revision==r['cargo_revision'] and last_cargo==e['amount_milli'],'deposited cargo revision matches provenance')
            require(earned==e['attributed_forward_milli'],'derived forward credit')
            for resource in ['food','wood']:
                a=e['stats_after']; b=e['stats_before']
                delta=a['delivered'][resource]-b['delivered'][resource]-(a['purchased'][resource]-b['purchased'][resource])+(a['refunded'][resource]-b['refunded'][resource])-(a['repaired'][resource]-b['repaired'][resource])
                require(e['bank_after'][resource]-e['bank_before'][resource]==delta,'bank reconciliation')
            require(e['stats_after']['delivered'][e['resource']]-e['stats_before']['delivered'][e['resource']]>=e['amount_milli'],'delivery counter witness')
            require(e['store']==built['record']['id']==e['before']['target'],'actual store target')
            require(e['before']['state']=='deliver' and e['before']['cargo_milli']==e['amount_milli'] and e['after']['cargo_milli']==0,'actual cargo deposit')
            require(r['applied'] and r['amount_milli']==e['amount_milli'] and r['resource_type']==e['resource'],'ledger deposit')
            require(0<=e['attributed_forward_milli']<=e['amount_milli'],'forward attribution bound')
            income[e['resource']]+=e['attributed_forward_milli']
        require(income['food']>=50000 and income['wood']>=20000,'forward-funded full replacement')
        require(any(e.get('type')=='military_loss' and e['tick']<=request['tick'] for e in events),'actual military loss')
        receipt=completed['receipt']
        require(receipt['state']=='fulfilled' and receipt['team']==0 and receipt['paid_milli']=={'food':50000,'wood':20000},'fulfilled paid replacement')
        require(completed['record']['id']==completed['spawn'] and completed['record']['kind']=='spearman' and completed['record']['owned'] and completed['record']['alive'] and completed['record']['team']==0,'replacement spawned')
        require(any(e.get('type')=='military_paid' and e['tick']>request['tick'] and e['queue']['receipt_id']==completed['receipt_id'] for e in events),'replacement receipt identity')
    return errors
class SourceTests(unittest.TestCase):
    def test_frozen_sources(self):
        lock=json.loads((HERE/'source_lock.json').read_text())
        self.assertGreaterEqual(len(lock['files']),20)
        for p,h in lock['files'].items(): self.assertEqual(sha(PROJECT/p),h,p)
    def test_rules_and_actual_mechanics(self):
        g=(PROJECT/'scripts/game.gd').read_text(); r=(PROJECT/'scripts/rules.gd').read_text()
        for token in ['"storehouse":{"wood":80}','"spearman":{"food":50,"wood":20}','const MAP_SIZE = 80']: self.assertIn(token,r)
        for token in ['if not _at_work_approach(ent,target):','economy.deposit(transaction_id,ent.id,expected_revision)','economy.bank_milli(1)','"train": _enqueue_train(command.building,command.kind,team)']: self.assertIn(token,g)
    def test_harness_has_no_authority_writes(self):
        s=(HERE/'expansion.gd').read_text()
        for token in ['game._spawn(', 'game._kill(', 'game._pay(', 'game._deposit_cargo(', 'game._order(', 'game.ai_enabled =', 'game.entities', 'game.economy.pay(', 'game.economy.deposit(', 'game.economy.gather_tick(']: self.assertNotIn(token,s)
        for token in ['game._submit(kind, data, 0)','FileAccess.get_sha256("res://"+path)','bank_before.revisions[id]','forward_cargo.get(id,0)','var visible = bool(game.visible_cells[0]']: self.assertIn(token,s)
    def test_reject_empty_and_unexecuted(self):
        self.assertTrue(validate({}))
        self.assertTrue(validate({'status':'UNRUN'}))
    def test_fixture_positive_and_corruptions(self):
        r=json.loads((HERE/'validator_fixture.json').read_text())
        self.assertEqual(validate(r,allow_fixture=True),[])
        for kind,key,value in [('store_paid_site','wood_purchase_delta_milli',0),('replacement_completed','receipt_id','invented'),('forward_store_deposit','attributed_forward_milli',0),('observed_home_depletion','nodes',{})]:
            x=copy.deepcopy(r); next(e for e in x['events'] if e['type']==kind)[key]=value
            self.assertTrue(validate(x,allow_fixture=True),(kind,key))
        x=copy.deepcopy(r); x['events']=[e for e in x['events'] if e['type']!='military_loss']; self.assertTrue(validate(x,allow_fixture=True))
def cli():
    import argparse
    global PROJECT
    parser=argparse.ArgumentParser(description='Validate actual expansion evidence against an explicit frozen project root.')
    parser.add_argument('--root',required=True,type=pathlib.Path)
    parser.add_argument('report',type=pathlib.Path)
    args=parser.parse_args()
    PROJECT=args.root.resolve()
    errors=[]
    try:
        lock=json.loads((HERE/'source_lock.json').read_text())
        if any(not (PROJECT/p).is_file() or sha(PROJECT/p)!=h for p,h in lock['files'].items()):
            errors.append('source_inventory_mismatch')
        errors.extend(validate(json.loads(args.report.read_text())))
    except (OSError,ValueError,TypeError,KeyError): errors.append('input_unreadable_or_malformed')
    verdict={'schema':'resource-expansion-verdict-v1','status':'FAIL' if errors else 'PASS','passed':not errors,'error_count':len(errors),'errors':[e[:120] for e in errors[:16]]}
    print(json.dumps(verdict,separators=(',',':')))
    return bool(errors)
if __name__=='__main__':
    if len(sys.argv)>1: sys.exit(cli())
    unittest.main()
